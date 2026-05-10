// rtdb_gps_listener_service.dart
// Phase 2: Subscribes to RTDB bus coordinate node for the assigned bus.
// Phase 3: Resolves nearest station with haversine + anti-jitter rules.
//
// RTDB input payload per bus node:
//   { id: "BUS_01", latitude: ..., longitude: ... }
//
// RTDB base path for bus GPS: /buses/{busRtdbId}
// Bus number → RTDB ID mapping: "BUS-001" → "BUS_01", "BUS-002" → "BUS_02"

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../utils/fare_calculator.dart';
import 'station_registry.dart';

class BusCoordinate {
  final double latitude;
  final double longitude;
  final DateTime receivedAt;

  const BusCoordinate({
    required this.latitude,
    required this.longitude,
    required this.receivedAt,
  });
}

class _GpsStationSourceEntry {
  final int routeOrder;
  final String name;
  final double latitude;
  final double longitude;

  const _GpsStationSourceEntry({
    required this.routeOrder,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class RtdbGpsListenerService {
  static final RtdbGpsListenerService _instance =
      RtdbGpsListenerService._internal();
  factory RtdbGpsListenerService() => _instance;
  RtdbGpsListenerService._internal() {
    _refreshStationSource();
  }

  final StreamController<int> _stationChangesController =
      StreamController<int>.broadcast();

  // ─── Configuration ───

  /// Max seconds before a GPS coordinate is considered stale.
  static const int _staleThresholdSeconds = 90;

  // ─── State ───
  StreamSubscription<DatabaseEvent>? _rtdbSubscription;
  StreamSubscription<void>? _fareTableSubscription;
  BusCoordinate? _lastCoordinate;
  List<_GpsStationSourceEntry> _stationSource = const [];
  String _stationSourceLabel = 'bundled';

  /// Current confirmed station (0-based routeOrder, north-to-south).
  int _currentStationOrder = 0;

  /// True once the first GPS fix has been received (used to suppress backward-regression
  /// check on cold-start — any direction is valid on first fix).
  bool _hasInitialFix = false;

  /// Route direction: 'north_to_south' or 'south_to_north'.
  String _routeDirection = 'north_to_south';

  // ─── Public getters ───
  BusCoordinate? get lastCoordinate => _lastCoordinate;
  int get currentStationOrder => _currentStationOrder;
  String get currentStationName => _stationNameForOrder(_currentStationOrder);
  Stream<int> get stationChanges => _stationChangesController.stream;

  bool get hasValidCoordinate {
    if (_lastCoordinate == null) return false;
    final age =
        DateTime.now().difference(_lastCoordinate!.receivedAt).inSeconds;
    return age <= _staleThresholdSeconds;
  }

  /// Convert POS bus number (e.g. "BUS-001") to RTDB node id (e.g. "BUS_01").
  static String busNumberToRtdbId(String busNumber) {
    // "BUS-001" → "BUS_01", "BUS-002" → "BUS_02", "BUS-010" → "BUS_10"
    final normalized = busNumber.trim().toUpperCase().replaceAll('-', '_');
    // Parse the numeric part and zero-pad to minimum 2 digits
    final match = RegExp(r'^BUS_0*(\d+)$').firstMatch(normalized);
    if (match != null) {
      final num = int.tryParse(match.group(1) ?? '0') ?? 0;
      return 'BUS_${num.toString().padLeft(2, '0')}';
    }
    return normalized;
  }

  /// Start listening to RTDB for the given bus number.
  Future<void> startListening({
    required String busNumber,
    required String routeDirection,
    required String rtdbBaseUrl,
  }) async {
    await stopListening();
    _routeDirection = routeDirection;
    _refreshStationSource();
    _fareTableSubscription = FareTable.changes.listen((_) {
      _handleFareTableChanged();
    });

    final rtdbId = busNumberToRtdbId(busNumber);
    final path = 'buses/$rtdbId';

    debugPrint(
        '[RtdbGps] Listening at RTDB path "$path" (bus: $busNumber → $rtdbId)');

    try {
      final db = FirebaseDatabase.instanceFor(
          app: Firebase.app(), databaseURL: rtdbBaseUrl);
      final ref = db.ref(path);

      _rtdbSubscription = ref.onValue.listen(
        (event) => _onRtdbUpdate(event),
        onError: (e) => debugPrint('[RtdbGps] RTDB stream error: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[RtdbGps] Failed to start listener: $e');
    }
  }

  Future<void> stopListening() async {
    await _rtdbSubscription?.cancel();
    _rtdbSubscription = null;
    await _fareTableSubscription?.cancel();
    _fareTableSubscription = null;
    _hasInitialFix =
        false; // Reset so next startListening does a fresh global search
    _currentStationOrder = 0;
    _refreshStationSource();
    debugPrint('[RtdbGps] Stopped RTDB listener.');
  }

  void updateRouteDirection(String direction) {
    _routeDirection = direction;
  }

  // ─── Internal ───

  void _onRtdbUpdate(DatabaseEvent event) {
    try {
      final raw = event.snapshot.value;
      if (raw == null) {
        debugPrint('[RtdbGps] RTDB snapshot is null.');
        return;
      }
      final data = Map<String, dynamic>.from(raw as Map);
      final lat = _parseDouble(data['latitude'] ?? data['lat']);
      final lng = _parseDouble(data['longitude'] ?? data['lng'] ?? data['lon']);

      if (lat == null || lng == null) {
        debugPrint('[RtdbGps] Invalid coordinate payload: $data');
        return;
      }

      _lastCoordinate = BusCoordinate(
        latitude: lat,
        longitude: lng,
        receivedAt: DateTime.now(),
      );

      _resolveNearestStation(lat, lng);
    } catch (e) {
      debugPrint('[RtdbGps] Error processing RTDB update: $e');
    }
  }

  void _resolveNearestStation(
    double lat,
    double lng, {
    bool emitIfSameStation = false,
    bool bypassDirectionGuard = false,
  }) {
    // ── Always do a full global search across all 56 stations ──
    // The RTDB GPS tracker already smooths raw GPS noise. We trust each incoming
    // coordinate update and resolve immediately — no stability window needed.
    final stations = _stationSource;
    if (stations.isEmpty) {
      debugPrint('[RtdbGps] No station source available for GPS resolution.');
      return;
    }

    int nearestOrder = stations.first.routeOrder;
    double nearestDist = double.infinity;

    for (final station in stations) {
      final dist = StationRegistry.haversineMetres(
          lat, lng, station.latitude, station.longitude);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestOrder = station.routeOrder;
      }
    }

    if (!_hasInitialFix) {
      // First fix: accept any station regardless of direction
      _currentStationOrder = nearestOrder;
      _hasInitialFix = true;
      _stationChangesController.add(_currentStationOrder);
      debugPrint(
        '[RtdbGps] Initial station fix: '
        '${_stationNameForOrder(nearestOrder)} '
        '(order: $nearestOrder, dist: ${nearestDist.toStringAsFixed(0)}m, '
        'source: $_stationSourceLabel)',
      );
      return;
    }

    if (nearestOrder == _currentStationOrder) {
      if (emitIfSameStation) {
        _stationChangesController.add(_currentStationOrder);
        debugPrint(
          '[RtdbGps] Station source refreshed at '
          '${_stationNameForOrder(nearestOrder)} '
          '(source: $_stationSourceLabel)',
        );
      }
      return;
    }

    // Route-order enforcement: for forward routes, don't allow going backward.
    // (Only meaningful on real trips; skip for south_to_north where order reverses.)
    final isForward = _routeDirection != 'south_to_north';
    if (!bypassDirectionGuard &&
        isForward &&
        nearestOrder < _currentStationOrder) {
      // GPS put us behind current station — could be a brief GPS bounce.
      // Accept only if it's a large jump (> 3 stations back) which may indicate
      // the bus truly reversed or we had a bad initial fix.
      if (_currentStationOrder - nearestOrder <= 3) {
        debugPrint(
          '[RtdbGps] Minor backward drift ignored '
          '(${_stationNameForOrder(_currentStationOrder)} → '
          '${_stationNameForOrder(nearestOrder)})',
        );
        return;
      }
    }

    final prev = _currentStationOrder;
    _currentStationOrder = nearestOrder;
    _stationChangesController.add(_currentStationOrder);
    debugPrint(
      '[RtdbGps] Station → ${_stationNameForOrder(nearestOrder)} '
      '(was: ${_stationNameForOrder(prev)}, '
      'dist: ${nearestDist.toStringAsFixed(0)}m, source: $_stationSourceLabel)',
    );
  }

  void _handleFareTableChanged() {
    final previousSource = _stationSourceLabel;
    final previousName = _stationNameForOrder(_currentStationOrder);
    _refreshStationSource();

    if (previousSource != _stationSourceLabel) {
      debugPrint(
        '[RtdbGps] Station source switched: $previousSource → $_stationSourceLabel',
      );
    }

    final lastCoordinate = _lastCoordinate;
    if (lastCoordinate != null) {
      _resolveNearestStation(
        lastCoordinate.latitude,
        lastCoordinate.longitude,
        emitIfSameStation: previousSource != _stationSourceLabel ||
            previousName != _stationNameForOrder(_currentStationOrder),
        bypassDirectionGuard: true,
      );
      return;
    }

    if (previousName != _stationNameForOrder(_currentStationOrder)) {
      _stationChangesController.add(_currentStationOrder);
    }
  }

  void _refreshStationSource() {
    final fareTableStations = FareTable.stationLocationsWithCoordinates;
    if (FareTable.hasCompleteStationCoordinates &&
        fareTableStations.length == FareTable.stationCount) {
      _stationSource = fareTableStations
          .map(
            (station) => _GpsStationSourceEntry(
              routeOrder: station.routeOrder,
              name: station.name,
              latitude: station.latitude,
              longitude: station.longitude,
            ),
          )
          .toList(growable: false);
      _stationSourceLabel = 'fare_table_entries';
      return;
    }

    _stationSource = StationRegistry.stations
        .map(
          (station) => _GpsStationSourceEntry(
            routeOrder: station.routeOrder,
            name: station.name,
            latitude: station.latitude,
            longitude: station.longitude,
          ),
        )
        .toList(growable: false);
    _stationSourceLabel = 'bundled';
  }

  String _stationNameForOrder(int order) {
    if (order >= 0 && order < _stationSource.length) {
      return _stationSource[order].name;
    }
    return StationRegistry.byOrder(order)?.name ?? 'Unknown';
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
