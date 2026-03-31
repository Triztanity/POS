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
      debugPrint('[OccupancyPublisher] Already running — updating route direction.');
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

    // Publish immediately, then on 30-second schedule
    await _publishNow();
    _timer = Timer.periodic(_publishInterval, (_) => _publishNow());

    debugPrint('[OccupancyPublisher] Started for bus $busNumber (${routeDirection}).');
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    await RtdbGpsListenerService().stopListening();
    debugPrint('[OccupancyPublisher] Stopped.');
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
