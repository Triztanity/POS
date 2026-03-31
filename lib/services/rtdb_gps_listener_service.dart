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

class RtdbGpsListenerService {
  static final RtdbGpsListenerService _instance = RtdbGpsListenerService._internal();
  factory RtdbGpsListenerService() => _instance;
  RtdbGpsListenerService._internal();

  // ─── Configuration ───

  /// Max seconds before a GPS coordinate is considered stale.
  static const int _staleThresholdSeconds = 90;

  // ─── State ───
  StreamSubscription<DatabaseEvent>? _rtdbSubscription;
  BusCoordinate? _lastCoordinate;

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
  String get currentStationName =>
      StationRegistry.byOrder(_currentStationOrder)?.name ?? 'Unknown';

  bool get hasValidCoordinate {
    if (_lastCoordinate == null) return false;
    final age = DateTime.now().difference(_lastCoordinate!.receivedAt).inSeconds;
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

    final rtdbId = busNumberToRtdbId(busNumber);
    final path = 'buses/$rtdbId';

    debugPrint('[RtdbGps] Listening at RTDB path "$path" (bus: $busNumber → $rtdbId)');

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
    _hasInitialFix = false; // Reset so next startListening does a fresh global search
    _currentStationOrder = 0;
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

  void _resolveNearestStation(double lat, double lng) {
    // ── Always do a full global search across all 56 stations ──
    // The RTDB GPS tracker already smooths raw GPS noise. We trust each incoming
    // coordinate update and resolve immediately — no stability window needed.
    int nearestOrder = 0;
    double nearestDist = double.infinity;

    for (int i = 0; i < StationRegistry.count; i++) {
      final station = StationRegistry.stations[i];
      final dist = StationRegistry.haversineMetres(
          lat, lng, station.latitude, station.longitude);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestOrder = i;
      }
    }

    if (!_hasInitialFix) {
      // First fix: accept any station regardless of direction
      _currentStationOrder = nearestOrder;
      _hasInitialFix = true;
      debugPrint(
        '[RtdbGps] Initial station fix: '
        '${StationRegistry.byOrder(nearestOrder)?.name} '
        '(order: $nearestOrder, dist: ${nearestDist.toStringAsFixed(0)}m)',
      );
      return;
    }

    if (nearestOrder == _currentStationOrder) {
      // Already at the correct station — no-op
      return;
    }

    // Route-order enforcement: for forward routes, don't allow going backward.
    // (Only meaningful on real trips; skip for south_to_north where order reverses.)
    final isForward = _routeDirection != 'south_to_north';
    if (isForward && nearestOrder < _currentStationOrder) {
      // GPS put us behind current station — could be a brief GPS bounce.
      // Accept only if it's a large jump (> 3 stations back) which may indicate
      // the bus truly reversed or we had a bad initial fix.
      if (_currentStationOrder - nearestOrder <= 3) {
        debugPrint(
          '[RtdbGps] Minor backward drift ignored '
          '(${StationRegistry.byOrder(_currentStationOrder)?.name} → '
          '${StationRegistry.byOrder(nearestOrder)?.name})',
        );
        return;
      }
    }

    final prev = _currentStationOrder;
    _currentStationOrder = nearestOrder;
    debugPrint(
      '[RtdbGps] Station → ${StationRegistry.byOrder(nearestOrder)?.name} '
      '(was: ${StationRegistry.byOrder(prev)?.name}, '
      'dist: ${nearestDist.toStringAsFixed(0)}m)',
    );
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
