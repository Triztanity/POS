// realtime_count_service.dart
// Phase 4: Realtime on-board count engine (read-only).
//
// Reuses the same counting formula from PassengersScreen.getPassengersOnBoard():
//   count booking when: status == 'on-board' AND fromIdx <= currentIdx < toIdx
//
// Key rules (from Plan.md):
//   1. status must be 'on-board'
//   2. fromIdx <= currentIdx < toIdx
//   3. Includes both bookings and walk-ins
//   4. Does NOT mutate any status or record — purely reads and computes

import 'package:flutter/foundation.dart';
import '../local_storage.dart';
import '../models/booking.dart';
import '../utils/fare_calculator.dart';
import 'station_registry.dart';

class RealtimeCountService {
  RealtimeCountService._();

  /// Compute on-board passenger count for the given station (routeOrder, north-to-south).
  /// [routeDirection] is either 'north_to_south' or 'south_to_north'.
  ///
  /// This mirrors PassengersScreen.getPassengersOnBoard() exactly.
  static int computeOnBoardCount({
    required int currentStationOrder,
    required String routeDirection,
  }) {
    final bookings = _getAllRecords();
    if (bookings.isEmpty) return 0;

    // Build the ordered stops list matching PassengersScreen
    final forwardStops = FareTable.placeNamesWithKm;
    final stops = routeDirection == 'north_to_south'
        ? List<String>.from(forwardStops)
        : List<String>.from(forwardStops.reversed);

    // Map currentStationOrder (from StationRegistry) to a stop index in the fare table
    // We translate via station name → fare table stop name fuzzy match
    final currentStationName = StationRegistry.byOrder(currentStationOrder)?.name ?? '';
    final currentIdx = _resolveStopIndex(currentStationName, stops);

    if (currentIdx == -1) {
      debugPrint('[RealtimeCount] Cannot resolve currentStation "$currentStationName" in fare table stops.');
      return 0;
    }

    int count = 0;
    for (final booking in bookings) {
      if (booking.status != 'on-board') continue;

      final fromIdx = _resolveStopIndex(booking.fromLocation, stops);
      final toIdx = _resolveStopIndex(booking.toLocation, stops);

      if (fromIdx == -1 || toIdx == -1) continue;

      // Core formula: fromIdx <= currentIdx < toIdx
      if (fromIdx <= currentIdx && currentIdx < toIdx) {
        count += booking.passengers;
      }
    }

    return count;
  }

  // ─── Internal helpers ───

  /// Load all bookings + walk-ins for the current trip, same as PassengersScreen.
  static List<Booking> _getAllRecords() {
    try {
      final manager = BookingManager();
      var bookings = manager.getBookings().toList();

      final walkins = LocalStorage.loadWalkinsForTrip(LocalStorage.getCurrentTripId()).toList();
      for (final walkin in walkins) {
        final b = Booking(
          id: walkin['id'] ?? '',
          passengerName: walkin['passengerName'] ?? 'Walk-in',
          route: walkin['route'] ?? '',
          date: walkin['date'] ?? '',
          time: walkin['time'] ?? '',
          passengers: walkin['passengers'] ?? 1,
          fromLocation: walkin['fromLocation'] ?? '',
          toLocation: walkin['toLocation'] ?? '',
          passengerType: walkin['passengerType'] ?? 'REGULAR',
          amount: walkin['amount'] ?? 0.0,
          status: 'on-board',
          passengerUid: null,
        );
        if (!bookings.any((x) => x.id == b.id)) bookings.add(b);
      }

      return bookings;
    } catch (e) {
      debugPrint('[RealtimeCount] Error loading records: $e');
      return [];
    }
  }

  /// Token-based fuzzy matching of location name to stop index in the fare table stops list.
  /// Also handles punctuation variants (slashes, hyphens) and uses km-based fast path.
  static int _resolveStopIndex(String locationName, List<String> stops) {
    if (locationName.isEmpty) return -1;

    // ── Fast path: use FareTable.getEntryByPlace which already handles fuzzy matching ──
    // This resolves things like "Robinsons Calaca Bayan" → CALACA/BAYAN entry (km: 32)
    final fareEntry = FareTable.getEntryByPlace(locationName);
    if (fareEntry != null) {
      final targetKm = fareEntry.km;
      // Find the stop in the list whose km prefix matches
      for (int i = 0; i < stops.length; i++) {
        final parts = stops[i].split('|');
        if (parts.isNotEmpty) {
          final km = int.tryParse(parts[0]);
          if (km == targetKm) return i;
        }
      }
    }

    // ── Fallback: token-based fuzzy match with punctuation normalization ──
    final inputNorm = _normalizeFull(locationName);
    final inputWords = inputNorm.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (inputWords.isEmpty) return -1;

    for (int i = 0; i < stops.length; i++) {
      final stopNorm = _normalizeFull(stops[i]);
      final stopWords = stopNorm.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      // All stop words must appear in the location words
      if (stopWords.isNotEmpty && stopWords.every((sw) => inputWords.contains(sw))) {
        return i;
      }
    }

    debugPrint('[RealtimeCount] Could not resolve station: "$locationName"');
    return -1;
  }

  /// Normalize a place name for token matching:
  /// strips km prefix, converts slashes/hyphens/dots to spaces, uppercases.
  static String _normalizeFull(String s) {
    // Strip leading km|prefix (e.g. "32|CALACA BAYAN" → "CALACA BAYAN")
    final stripped = s.contains('|') ? s.split('|').skip(1).join(' ') : s;
    return stripped
        .replaceAll('/', ' ')   // "CALACA/BAYAN" → "CALACA BAYAN"
        .replaceAll('-', ' ')   // "7-11" → "7 11"
        .replaceAll('.', ' ')   // "Brgy." → "Brgy "
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }
}

