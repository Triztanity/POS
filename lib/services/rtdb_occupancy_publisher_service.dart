// rtdb_occupancy_publisher_service.dart
// Phase 5: Fixed 30-second timer that publishes bus occupancy to RTDB.
//
// Output RTDB path: /occupancy/{busRtdbId}
// Output payload (ONLY these 4 fields per Plan.md):
//   {
//     busNumber:    "BUS-001"
//     currentStation: "Tuy"
//     onBoardCount: 12
//     updatedAt:   "2026-03-31T14:30:00.000"
//   }
//
// Fallback: if GPS is stale or station unresolved, publishes last known station + fresh timestamp.

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'rtdb_gps_listener_service.dart';
import 'realtime_count_service.dart';
import 'app_state.dart';
import '../local_storage.dart';

const String _rtdbBaseUrl =
    'https://bus-fleet-management-default-rtdb.asia-southeast1.firebasedatabase.app/';

class RtdbOccupancyPublisherService {
  static final RtdbOccupancyPublisherService _instance =
      RtdbOccupancyPublisherService._internal();
  factory RtdbOccupancyPublisherService() => _instance;
  RtdbOccupancyPublisherService._internal();

  static const Duration _publishInterval = Duration(seconds: 10);

  Timer? _timer;
  String? _busNumber;
  String _routeDirection = 'north_to_south';
  bool _running = false;

  /// Last published payload for diagnostics.
  Map<String, dynamic>? lastPublished;

  bool get isRunning => _running;

  /// Start the GPS listener + 30-second publisher for the given bus.
  Future<void> start({
    required String busNumber,
    required String routeDirection,
  }) async {
    if (_running) {
      debugPrint(
          '[OccupancyPublisher] Already running — updating route direction.');
      _routeDirection = routeDirection;
      RtdbGpsListenerService().updateRouteDirection(routeDirection);
      return;
    }

    _busNumber = busNumber;
    _routeDirection = routeDirection;
    _running = true;

    // Start RTDB GPS listener (Phase 2)
    await RtdbGpsListenerService().startListening(
      busNumber: busNumber,
      routeDirection: routeDirection,
      rtdbBaseUrl: _rtdbBaseUrl,
    );

    // Clean up any legacy wrong-format occupancy nodes (e.g. BUS_1 from old bug)
    await _cleanLegacyOccupancyNodes(busNumber);

    // Publish immediately, then on 30-second schedule
    await _publishNow();
    _timer = Timer.periodic(_publishInterval, (_) => _publishNow());

    debugPrint(
        '[OccupancyPublisher] Started for bus $busNumber (${routeDirection}).');
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    await RtdbGpsListenerService().stopListening();
    debugPrint('[OccupancyPublisher] Stopped.');
  }

  /// Publish a final zero-count update on arrival, then fully stop the publisher.
  /// Call this from the arrival report flow before clearing sessions.
  Future<void> publishArrival() async {
    if (_busNumber == null) return;

    try {
      final gps = RtdbGpsListenerService();
      final stationName = gps.currentStationName;

      final payload = <String, dynamic>{
        'busNumber': _busNumber,
        'currentStation': stationName,
        'onBoardCount': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      final rtdbId = RtdbGpsListenerService.busNumberToRtdbId(_busNumber!);
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _rtdbBaseUrl,
      );
      final ref = db.ref('occupancy/$rtdbId');
      await ref.set(payload);

      debugPrint(
          '[OccupancyPublisher] Arrival published → station: $stationName, onBoard: 0');
    } catch (e) {
      debugPrint('[OccupancyPublisher] Arrival publish error (non-fatal): $e');
    }

    await stop();
  }

  // ─── Legacy node cleanup ───

  /// Delete any wrong-format occupancy RTDB nodes that were created before the
  /// bus-ID fix (e.g. BUS_1 instead of BUS_01). Runs silently once on start.
  Future<void> _cleanLegacyOccupancyNodes(String busNumber) async {
    try {
      final canonical = RtdbGpsListenerService.busNumberToRtdbId(busNumber);
      // Build all known wrong-format variants to check and delete
      final legacyCandidates =
          _legacyRtdbIds(busNumber).where((id) => id != canonical).toList();

      if (legacyCandidates.isEmpty) return;

      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _rtdbBaseUrl,
      );

      for (final legacyId in legacyCandidates) {
        final ref = db.ref('occupancy/$legacyId');
        final snap = await ref.get();
        if (snap.exists) {
          await ref.remove();
          debugPrint(
              '[OccupancyPublisher] Removed legacy node: occupancy/$legacyId');
        }
      }
    } catch (e) {
      debugPrint('[OccupancyPublisher] Legacy cleanup skipped: $e');
    }
  }

  /// Generate all known wrong-format RTDB IDs for a given bus number.
  static List<String> _legacyRtdbIds(String busNumber) {
    final normalized = busNumber.trim().toUpperCase().replaceAll('-', '_');
    final match = RegExp(r'^BUS_0*(\d+)$').firstMatch(normalized);
    if (match == null) return [];
    final num = int.tryParse(match.group(1) ?? '0') ?? 0;
    return [
      'BUS_$num', // BUS_1  (stripped zeros, old bug)
      'BUS_${num.toString().padLeft(3, '0')}', // BUS_001 (3-digit, over-padded)
      'BUS${num.toString().padLeft(2, '0')}', // BUS01  (no underscore)
      'BUS$num', // BUS1   (no underscore + stripped)
      normalized, // BUS_001 (raw before trimming)
    ];
  }

  void updateRouteDirection(String direction) {
    _routeDirection = direction;
    RtdbGpsListenerService().updateRouteDirection(direction);
  }

  // ─── Trip-active guard ───

  /// Returns true only when there is an active crew on an active trip.
  /// This is the canonical gate that prevents publishing after arrival,
  /// cancellation, logout, or before the first dispatch.
  bool get _isTripActive {
    // 1. Must have a dispatched trip ID
    final tripId = LocalStorage.getCurrentTripId();
    if (tripId.isEmpty) return false;

    // 2. Trip must not be cancelled/locked
    if (AppState.instance.tripCancelledLocked) return false;

    // 3. At least one crew member must be logged in
    final hasConductor = AppState.instance.conductor != null;
    final hasDriver = AppState.instance.driver != null;
    if (!hasConductor && !hasDriver) return false;

    return true;
  }

  // ─── Publish logic ───

  Future<void> _publishNow() async {
    if (_busNumber == null) return;

    // Gate: only publish while the trip is active
    if (!_isTripActive) {
      debugPrint('[OccupancyPublisher] Skipped — no active trip or crew.');
      return;
    }

    try {
      final gps = RtdbGpsListenerService();
      final stationOrder = gps.currentStationOrder;
      final stationName = gps.currentStationName;

      // Compute on-board count (Phase 4 — read-only)
      final onBoardCount = RealtimeCountService.computeOnBoardCount(
        currentStationOrder: stationOrder,
        currentStationName: stationName,
        routeDirection: _routeDirection,
      );

      final payload = <String, dynamic>{
        'busNumber': _busNumber,
        'currentStation': stationName,
        'onBoardCount': onBoardCount,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      lastPublished = payload;

      // Write to RTDB /occupancy/{busRtdbId}
      final rtdbId = RtdbGpsListenerService.busNumberToRtdbId(_busNumber!);
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _rtdbBaseUrl,
      );
      final ref = db.ref('occupancy/$rtdbId');
      await ref.set(payload);

      debugPrint(
        '[OccupancyPublisher] Published → station: $stationName, '
        'onBoard: $onBoardCount, GPS valid: ${gps.hasValidCoordinate}',
      );
    } catch (e) {
      debugPrint('[OccupancyPublisher] Publish error (non-fatal): $e');
    }
  }
}
