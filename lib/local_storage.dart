import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/app_state.dart';

/// LocalStorage: simple Hive-based offline store for user records (UID -> user map)
/// Schema (box 'employees') stores values as Map<String, dynamic>:
/// {
///   'uid': 'ABC123',
///   'name': 'Juan Dela Cruz',
///   'role': 'conductor',
///   'firebaseId': '...',
///   'lastUpdated': 1234567890,
///   'synced': true
/// }
class LocalStorage {
  static const _boxName = 'employees';
  static const _bookingsBox = 'bookings';
  static const _sessionBox = 'session';
  static const _inspectionsBox = 'inspections';
  static const _scannedTicketsBox = 'scanned_tickets';
  static const _walkinsBox = 'walkins';
  static const _tripsBox = 'trips';

  static Future<void> init() async {
    try {
      await Hive.initFlutter();
      debugPrint('[LocalStorage] Hive.initFlutter complete');
    } catch (e) {
      debugPrint('[LocalStorage] Hive.initFlutter already initialized: $e');
    }

    // Open boxes only if not already open
    if (!Hive.isBoxOpen(_boxName)) {
      try {
        await Hive.openBox<Map>(_boxName);
        debugPrint('[LocalStorage] Opened box $_boxName');
      } catch (e) {
        debugPrint('[LocalStorage] Error opening box $_boxName: $e');
      }
    } else {
      debugPrint('[LocalStorage] Box $_boxName already open');
    }

    if (!Hive.isBoxOpen(_bookingsBox)) {
      try {
        await Hive.openBox<List>(_bookingsBox);
        debugPrint('[LocalStorage] Opened box $_bookingsBox');
      } catch (e) {
        debugPrint('[LocalStorage] Error opening box $_bookingsBox: $e');
      }
    } else {
      debugPrint('[LocalStorage] Box $_bookingsBox already open');
    }

    if (!Hive.isBoxOpen(_sessionBox)) {
      try {
        await Hive.openBox<Map>(_sessionBox);
        debugPrint('[LocalStorage] Opened box $_sessionBox');
      } catch (e) {
        debugPrint('[LocalStorage] Error opening box $_sessionBox: $e');
      }
    } else {
      debugPrint('[LocalStorage] Box $_sessionBox already open');
    }

    if (!Hive.isBoxOpen(_inspectionsBox)) {
      try {
        await Hive.openBox<List>(_inspectionsBox);
        debugPrint('[LocalStorage] Opened box $_inspectionsBox');
      } catch (e) {
        debugPrint('[LocalStorage] Error opening box $_inspectionsBox: $e');
      }
    } else {
      debugPrint('[LocalStorage] Box $_inspectionsBox already open');
    }

    if (!Hive.isBoxOpen(_scannedTicketsBox)) {
      try {
        await Hive.openBox<List>(_scannedTicketsBox);
        debugPrint('[LocalStorage] Opened box $_scannedTicketsBox');
      } catch (e) {
        debugPrint('[LocalStorage] Error opening box $_scannedTicketsBox: $e');
      }
    } else {
      debugPrint('[LocalStorage] Box $_scannedTicketsBox already open');
    }
    if (!Hive.isBoxOpen(_walkinsBox)) {
      try {
        await Hive.openBox<List>(_walkinsBox);
        debugPrint('[LocalStorage] Opened box $_walkinsBox');
      } catch (e) {
        debugPrint('[LocalStorage] Error opening box $_walkinsBox: $e');
      }
    } else {
      debugPrint('[LocalStorage] Box $_walkinsBox already open');
    }
    if (!Hive.isBoxOpen(_tripsBox)) {
      try {
        await Hive.openBox<List>(_tripsBox);
        debugPrint('[LocalStorage] Opened box $_tripsBox');
      } catch (e) {
        debugPrint('[LocalStorage] Error opening box $_tripsBox: $e');
      }
    } else {
      debugPrint('[LocalStorage] Box $_tripsBox already open');
    }
    // Migrate any legacy keys (e.g. colon-separated UIDs) to normalized keys
    final box = Hive.box<Map>(_boxName);
    final keys = List.of(box.keys);
    for (final k in keys) {
      try {
        final keyStr = k.toString();
        final norm = _normalizeUid(keyStr);
        if (norm != keyStr) {
          final existing = box.get(norm);
          if (existing == null) {
            final val = box.get(k);
            if (val != null) {
              final migrated =
                  Map<String, dynamic>.from(val.cast<String, dynamic>());
              migrated['uid'] = norm;
              await box.put(norm, migrated);
            }
          }
          await box.delete(k);
        }
      } catch (_) {
        // ignore bad keys
      }
    }

    // Seed known authorized UIDs (admin-provisioned). These are canonicalized
    // and only added if missing. Update names/roles here as needed.
    final seeds = [
      {'uid': '43:56:3F:06', 'name': 'Perky Malabanan', 'role': 'conductor'},
      {'uid': '6D:ED:43:06', 'name': 'Juan Dela Cruz', 'role': 'conductor'},
      {'uid': '4E:22:43:06', 'name': 'Pepsi Paloma', 'role': 'driver'},
      {'uid': 'EC:D5:41:06', 'name': 'Ricardo Dalisay', 'role': 'driver'},
      {'uid': '47:29:42:06', 'name': 'John Earl', 'role': 'dispatcher'},
      {'uid': '69:64:3F:06', 'name': 'David Dimaguiba', 'role': 'dispatcher'},
      {'uid': '05:91:41:06', 'name': 'Inspector Card', 'role': 'inspector'},
    ];

    for (final s in seeds) {
      try {
        final key = _normalizeUid(s['uid'] as String);
        if (box.get(key) == null) {
          await upsertEmployee({
            'uid': s['uid'],
            'name': s['name'],
            'role': s['role'],
            'synced': false
          });
        }
      } catch (_) {}
    }

    // Restore session conductor and driver into AppState if present
    try {
      final currentConductor = loadCurrentConductor();
      if (currentConductor != null) {
        AppState.instance.setConductor(currentConductor);
      }
      final currentDriver = loadCurrentDriver();
      if (currentDriver != null) {
        AppState.instance.setDriver(currentDriver);
      }
    } catch (_) {}

    // Auto-clear scannedTickets if > 24 hours since last clear
    try {
      final sessionBox = Hive.box(_sessionBox);
      final lastClearTimeStr =
          sessionBox.get('lastScannedTicketsClearTime')?.toString();

      bool shouldClear = true;
      if (lastClearTimeStr != null && lastClearTimeStr.isNotEmpty) {
        final lastClearTime = DateTime.tryParse(lastClearTimeStr);
        if (lastClearTime != null) {
          final hoursSinceLastClear =
              DateTime.now().difference(lastClearTime).inHours;
          shouldClear = hoursSinceLastClear >= 24;
          debugPrint(
              '[LocalStorage] Last scannedTickets clear: $hoursSinceLastClear hours ago');
        }
      }

      if (shouldClear) {
        await _clearScannedTicketsInternal();
        await sessionBox.put(
            'lastScannedTicketsClearTime', DateTime.now().toIso8601String());
        debugPrint(
            '[LocalStorage] ✅ Cleared scannedTickets (24+ hours since last clear)');
      }
    } catch (e) {
      debugPrint('[LocalStorage] Error during scannedTickets auto-clear: $e');
    }
  }

  static Future<void> upsertEmployee(Map<String, dynamic> data) async {
    final box = Hive.box<Map>(_boxName);
    final rawUid = data['uid'] as String?;
    if (rawUid == null) return;
    final uid = _normalizeUid(rawUid);
    final record = Map<String, dynamic>.from(data);
    record['uid'] = uid; // store normalized uid
    record['lastUpdated'] = DateTime.now().millisecondsSinceEpoch;
    record['synced'] = record['synced'] ?? false;
    await box.put(uid, record);
  }

  static Map<String, dynamic>? getEmployee(String uid) {
    final box = Hive.box<Map>(_boxName);
    final key = _normalizeUid(uid);
    final val = box.get(key);
    if (val == null) return null;
    return Map<String, dynamic>.from(val.cast<String, dynamic>());
  }

  static List<Map<String, dynamic>> getAllEmployees() {
    final box = Hive.box<Map>(_boxName);
    return box.values
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();
  }

  static Future<void> deleteEmployee(String uid) async {
    final box = Hive.box<Map>(_boxName);
    await box.delete(_normalizeUid(uid));
  }

  static Future<void> clearAll() async {
    final box = Hive.box<Map>(_boxName);
    await box.clear();
  }

  /// Bookings persistence per trip (saved to local storage for Firebase sync)
  static Future<void> saveBookingForTrip(Map<String, dynamic> booking) async {
    try {
      final box = Hive.box<List>(_bookingsBox);
      final tripId = booking['tripId']?.toString() ?? getCurrentTripId();
      final key = 'trip_$tripId';
      final bookings = box.get(key) ?? [];
      final record = Map<String, dynamic>.from(booking);
      record['tripId'] = tripId;
      record['createdAt'] =
          record['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;
      record['syncStatus'] = record['syncStatus'] ?? 'pending';
      bookings.add(record);
      await box.put(key, bookings);
    } catch (_) {}
  }

  /// Bookings persistence per conductor UID
  static Future<void> saveBookingsForConductor(
      String conductorUid, List<Map<String, dynamic>> bookings) async {
    try {
      final box = Hive.box<List>(_bookingsBox);
      await box.put(conductorUid, bookings);
    } catch (_) {}
  }

  static List<Map<String, dynamic>>? loadBookingsForConductor(
      String conductorUid) {
    try {
      final box = Hive.box<List>(_bookingsBox);
      final raw = box.get(conductorUid);
      if (raw == null) return null;
      return (raw.cast<Map>())
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteBookingsForConductor(String conductorUid) async {
    try {
      final box = Hive.box<List>(_bookingsBox);
      await box.delete(conductorUid);
    } catch (_) {}
  }

  /// Delete bookings for a specific trip (after Firebase sync succeeds)
  static Future<void> deleteBookingsForTrip(String tripId) async {
    try {
      final box = Hive.box<List>(_bookingsBox);
      final key = 'trip_$tripId';
      await box.delete(key);
      debugPrint('[LocalStorage] Deleted bookings for trip $tripId');
    } catch (e) {
      debugPrint('[LocalStorage] ERROR deleting bookings for trip $tripId: $e');
    }
  }

  /// Session helpers
  static Future<void> saveCurrentConductor(
      Map<String, dynamic> conductor) async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      await box.put('conductor', conductor);
      debugPrint(
          '[LocalStorage] Saved conductor: ${conductor['name']} (uid: ${conductor['uid']})');
    } catch (e) {
      debugPrint('[LocalStorage] ERROR saving conductor: $e');
    }
  }

  static Map<String, dynamic>? loadCurrentConductor() {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final raw = box.get('conductor');
      if (raw == null) {
        debugPrint('[LocalStorage] No saved conductor found');
        return null;
      }
      final result = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      debugPrint(
          '[LocalStorage] Loaded conductor: ${result['name']} (uid: ${result['uid']})');
      return result;
    } catch (e) {
      debugPrint('[LocalStorage] ERROR loading conductor: $e');
      return null;
    }
  }

  static Future<void> saveCurrentDriver(Map<String, dynamic> driver) async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      await box.put('driver', driver);
    } catch (_) {}
  }

  static Map<String, dynamic>? loadCurrentDriver() {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final raw = box.get('driver');
      if (raw == null) return null;
      return Map<String, dynamic>.from(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCurrentDriver() async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      await box.delete('driver');
    } catch (_) {}
  }

  /// Navigation state persistence (for resuming from recent apps)
  /// Saves the last screen the user was on
  static Future<void> saveLastScreen(
      String screenName, Map<String, dynamic> params) async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      await box.put('lastScreen', {'name': screenName, 'params': params});
    } catch (_) {}
  }

  /// Load the last screen the user was on
  static Map<String, dynamic>? loadLastScreen() {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final raw = box.get('lastScreen');
      if (raw == null) return null;
      return Map<String, dynamic>.from(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// Clear the last screen (call on logout)
  static Future<void> clearLastScreen() async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      await box.delete('lastScreen');
    } catch (_) {}
  }

  static Future<void> clearCurrentConductor() async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      await box.delete('conductor');
    } catch (_) {}
  }

  /// Inspection persistence
  static Future<void> saveInspection(Map<String, dynamic> inspection) async {
    try {
      final box = Hive.box<List>(_inspectionsBox);
      final inspections = box.get('all') ?? [];
      final record = Map<String, dynamic>.from(inspection);
      record['tripId'] = record['tripId'] ?? getCurrentTripId();
      record['createdAt'] =
          record['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;
      record['syncStatus'] = record['syncStatus'] ?? 'pending';
      inspections.add(record);
      await box.put('all', inspections);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> loadInspections() {
    try {
      final box = Hive.box<List>(_inspectionsBox);
      final inspections = box.get('all') ?? [];
      return inspections
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> loadInspectionsForTrip(String tripId) {
    try {
      final all = loadInspections();
      return all
          .where((i) => (i['tripId']?.toString() ?? '') == tripId)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> updateInspection(
      String id, Map<String, dynamic> inspection) async {
    try {
      final box = Hive.box<List>(_inspectionsBox);
      final inspections = box.get('all') ?? [];
      final index = inspections.indexWhere((e) {
        final m = Map<String, dynamic>.from(e.cast<String, dynamic>());
        return m['id'] == id;
      });
      if (index >= 0) {
        inspections[index] = inspection;
        await box.put('all', inspections);
      }
    } catch (_) {}
  }

  /// Scanned Tickets persistence
  static Future<void> saveScannedTicket(Map<String, dynamic> ticket) async {
    try {
      final box = Hive.box<List>(_scannedTicketsBox);
      final tickets = box.get('all') ?? [];
      final record = Map<String, dynamic>.from(ticket);
      record['tripId'] = record['tripId'] ?? getCurrentTripId();
      record['createdAt'] =
          record['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;
      record['syncStatus'] = record['syncStatus'] ?? 'pending';
      tickets.add(record);
      await box.put('all', tickets);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> loadScannedTickets() {
    try {
      final box = Hive.box<List>(_scannedTicketsBox);
      final tickets = box.get('all') ?? [];
      return tickets
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> loadScannedTicketsForTrip(String tripId) {
    try {
      final all = loadScannedTickets();
      return all
          .where((s) => (s['tripId']?.toString() ?? '') == tripId)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearScannedTickets() async {
    try {
      final box = Hive.box<List>(_scannedTicketsBox);
      await box.delete('all');
    } catch (_) {}
  }

  /// Internal method used by init() for auto-clearing (same as clearScannedTickets but without try-catch)
  static Future<void> _clearScannedTicketsInternal() async {
    try {
      final box = Hive.box<List>(_scannedTicketsBox);
      await box.delete('all');
    } catch (e) {
      debugPrint('[LocalStorage] Error clearing scannedTickets: $e');
    }
  }

  /// Walk-in tickets persistence (printed from HomeScreen)
  static Future<void> saveWalkin(Map<String, dynamic> walkin) async {
    try {
      final box = Hive.box<List>(_walkinsBox);
      final items = box.get('all') ?? [];
      // Ensure trip scoping and metadata
      final record = Map<String, dynamic>.from(walkin);
      record['tripId'] = record['tripId'] ?? getCurrentTripId();
      record['createdAt'] =
          record['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;
      record['syncStatus'] = record['syncStatus'] ?? 'pending';
      items.add(record);
      await box.put('all', items);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> loadWalkins() {
    try {
      final box = Hive.box<List>(_walkinsBox);
      final items = box.get('all') ?? [];
      return items
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> loadWalkinsForTrip(String tripId) {
    try {
      final all = loadWalkins();
      return all
          .where((w) => (w['tripId']?.toString() ?? '') == tripId)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearWalkins() async {
    try {
      final box = Hive.box<List>(_walkinsBox);
      await box.delete('all');
    } catch (_) {}
  }

  /// Trip/session management
  static String getCurrentTripId() {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final session = box.get('sessionData');
      if (session != null && session['currentTripId'] != null)
        return session['currentTripId'].toString();
      // Generate a default trip id if missing
      final id =
          'TRIP-${DateTime.now().toIso8601String().replaceAll(':', '').split('.').first}';
      final newSession =
          Map<String, dynamic>.from(session?.cast<String, dynamic>() ?? {});
      newSession['currentTripId'] = id;
      box.put('sessionData', newSession as Map);
      return id;
    } catch (_) {
      return 'TRIP-UNKNOWN';
    }
  }

  static Future<void> setCurrentTripId(String tripId) async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final session = box.get('sessionData');
      final newSession =
          Map<String, dynamic>.from(session?.cast<String, dynamic>() ?? {});
      newSession['currentTripId'] = tripId;
      box.put('sessionData', newSession as Map);
    } catch (_) {}
  }

  static Future<String> startNewTrip({String? vehicleNo}) async {
    final newId =
        'TRIP-${DateTime.now().toIso8601String().replaceAll(':', '').split('.').first}';
    try {
      final tb = Hive.box<List>(_tripsBox);
      final meta = {
        'tripId': newId,
        'vehicleNo': vehicleNo ?? 'Unknown',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'finalized': false,
        'syncStatus': 'pending',
      };
      final all = tb.get('all') ?? [];
      all.add(meta);
      await tb.put('all', all);
      await setCurrentTripId(newId);
      // Disable manual mode for new trip
      await setManualMode(false);
      // Clear trip-local state (walk-ins, inspections) but keep bookings/scanned tickets
      await resetTripState(newId);
    } catch (_) {}
    return newId;
  }

  static Future<void> finalizeTrip(String tripId) async {
    try {
      final tb = Hive.box<List>(_tripsBox);
      final all = (tb.get('all') ?? [])
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
      for (var m in all) {
        if ((m['tripId']?.toString() ?? '') == tripId) {
          m['finalized'] = true;
          m['finalizedAt'] = DateTime.now().millisecondsSinceEpoch;
        }
      }
      await tb.put('all', all);

      // Mark walkins of that trip as finalized
      final wbox = Hive.box<List>(_walkinsBox);
      final walks = (wbox.get('all') ?? [])
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
      for (var w in walks) {
        if ((w['tripId']?.toString() ?? '') == tripId) {
          w['finalized'] = true;
          w['syncStatus'] = w['syncStatus'] ?? 'pending';
        }
      }
      await wbox.put('all', walks);

      // Mark scanned tickets as finalized for trip
      final sbox = Hive.box<List>(_scannedTicketsBox);
      final scans = (sbox.get('all') ?? [])
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
      for (var s in scans) {
        if ((s['tripId']?.toString() ?? '') == tripId) {
          s['finalized'] = true;
          s['syncStatus'] = s['syncStatus'] ?? 'pending';
        }
      }
      await sbox.put('all', scans);

      // Mark inspections as finalized for trip (if trip-scoped)
      final inbox = Hive.box<List>(_inspectionsBox);
      final inspections = (inbox.get('all') ?? [])
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
      for (var i in inspections) {
        if ((i['tripId']?.toString() ?? '') == tripId) {
          i['finalized'] = true;
          i['syncStatus'] = i['syncStatus'] ?? 'pending';
        }
      }
      await inbox.put('all', inspections);

      // Disable manual mode (trip-scoped)
      await setManualMode(false);
    } catch (_) {}
  }

  /// Manual ticketing mode helpers (stored in session as a Map with metadata)
  static Future<void> setManualMode(bool enabled) async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final modeData = <String, dynamic>{
        'enabled': enabled,
        'timestamp': enabled ? DateTime.now().millisecondsSinceEpoch : null,
        'tripId': enabled ? getCurrentTripId() : null,
      };
      await box.put('manualModeState', modeData as Map);
    } catch (_) {}
  }

  static bool isManualMode() {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final data = box.get('manualModeState');
      if (data == null) return false;
      final modeData = Map<String, dynamic>.from(data.cast<String, dynamic>());
      if (modeData['enabled'] != true) return false;
      final tripId = modeData['tripId']?.toString();
      if (tripId == null) return false;
      return tripId == getCurrentTripId();
    } catch (_) {
      return false;
    }
  }

  static int? getManualModeTimestamp() {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final data = box.get('manualModeState');
      if (data == null) return null;
      final modeData = Map<String, dynamic>.from(data.cast<String, dynamic>());
      final tripId = modeData['tripId']?.toString();
      if (tripId == null || tripId != getCurrentTripId()) return null;
      final ts = modeData['timestamp'];
      if (ts == null) return null;
      return ts is int ? ts : int.tryParse(ts.toString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearManualMode() async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      await box.delete('manualModeState');
    } catch (_) {}
  }

  /// Store vehicle number (bus number) for current trip
  static Future<void> setCurrentVehicleNo(String vehicleNo) async {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final session = box.get('sessionData');
      final newSession =
          Map<String, dynamic>.from(session?.cast<String, dynamic>() ?? {});
      newSession['vehicleNo'] = vehicleNo;
      await box.put('sessionData', newSession as Map);
    } catch (_) {}
  }

  static String getCurrentVehicleNo() {
    try {
      final box = Hive.box<Map>(_sessionBox);
      final session = box.get('sessionData');
      if (session != null) {
        final s = Map<String, dynamic>.from(session.cast<String, dynamic>());
        return s['vehicleNo']?.toString() ?? 'Unknown';
      }
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  /// Reset trip-local state when deploying a new trip
  /// Deletes: walk-in tickets and inspections for the OLD trip
  /// Keeps: bookings and scanned tickets (grouped by tripId for future validation)
  static Future<void> resetTripState(String newTripId) async {
    try {
      // Clear walk-ins for the previous trip(s) - we only keep one active trip's walk-ins
      final wbox = Hive.box<List>(_walkinsBox);
      await wbox.delete('all');

      // Clear inspections for the previous trip(s) - same as walk-ins
      final inbox = Hive.box<List>(_inspectionsBox);
      await inbox.delete('all');

      debugPrint(
          '[LocalStorage] Trip state reset: walk-ins and inspections cleared for new trip $newTripId');
      debugPrint(
          '[LocalStorage] Bookings and scanned tickets preserved (grouped by tripId)');
    } catch (e) {
      debugPrint('[LocalStorage] ERROR resetting trip state: $e');
    }
  }

  /// Get records for a specific trip (tripId-filtered)
  /// Used for Firebase sync to only upload records for the completed trip
  static Map<String, dynamic> getRecordsForTrip(String tripId) {
    try {
      final walkins = loadWalkinsForTrip(tripId);
      final bookings = loadBookingsForTrip(tripId);
      final scannedTickets = loadScannedTicketsForTrip(tripId);
      final inspections = loadInspectionsForTrip(tripId);

      return {
        'tripId': tripId,
        'walkins': walkins,
        'bookings': bookings,
        'scannedTickets': scannedTickets,
        'inspections': inspections,
      };
    } catch (_) {
      return {
        'tripId': tripId,
        'walkins': [],
        'bookings': [],
        'scannedTickets': [],
        'inspections': [],
      };
    }
  }

  /// Load bookings for a specific trip
  static List<Map<String, dynamic>> loadBookingsForTrip(String tripId) {
    try {
      final box = Hive.box<List>(_bookingsBox);
      final key = 'trip_$tripId';
      final bookingsForTrip = box.get(key) ?? [];
      return bookingsForTrip
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Map Android ID to Bus Number
  static String getBusNumberFromAndroidId(String? androidId) {
    const androidIdToBusMap = {
      'ca04c9993ebc9f65': 'BUS-002', // H10P746259A0982
      'e48d8154b4dc3378': 'BUS-001', // H10P74625AU0044
    };
    return androidIdToBusMap[androidId?.toLowerCase()] ?? 'UNKNOWN';
  }

  static String _normalizeUid(String uid) {
    // Remove non-hex characters and uppercase for canonical lookups
    return uid.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();
  }

  /// Get storage statistics for all boxes
  static Future<Map<String, dynamic>> getStorageStats() async {
    try {
      final stats = <String, dynamic>{};
      int totalRecords = 0;

      // Check each box
      final boxes = [
        (_boxName, 'Employees'),
        (_bookingsBox, 'Bookings'),
        (_sessionBox, 'Session'),
        (_inspectionsBox, 'Inspections'),
        (_scannedTicketsBox, 'Scanned Tickets'),
        (_walkinsBox, 'Walk-ins'),
        (_tripsBox, 'Trips'),
      ];

      for (final (boxKey, boxName) in boxes) {
        try {
          final box = Hive.box(boxKey);
          final count = box.length;
          totalRecords += count;
          stats[boxName] = {
            'records': count,
            'isEmpty': box.isEmpty,
          };
          debugPrint('[StorageStats] $boxName: $count records');
        } catch (e) {
          debugPrint('[StorageStats] Error reading $boxName: $e');
          stats[boxName] = {'error': e.toString()};
        }
      }

      stats['totalRecords'] = totalRecords;
      return stats;
    } catch (e) {
      debugPrint('[StorageStats] Error getting storage stats: $e');
      return {'error': e.toString()};
    }
  }

  /// Get human-readable storage summary
  static Future<String> getStorageSummary() async {
    final stats = await getStorageStats();
    final buffer = StringBuffer();

    buffer.writeln('=== Local Storage Summary ===');
    buffer.writeln('Total Records: ${stats['totalRecords'] ?? 0}');
    buffer.writeln('');

    stats.forEach((key, value) {
      if (key != 'totalRecords' && key != 'error' && value is Map) {
        final records = value['records'] ?? 0;
        final isEmpty = value['isEmpty'] ?? true;
        buffer.writeln('$key: $records records ${isEmpty ? '(empty)' : ''}');
      }
    });

    if (stats.containsKey('error')) {
      buffer.writeln('\nError: ${stats['error']}');
    }

    return buffer.toString();
  }
}
