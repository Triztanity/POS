import 'package:hive_flutter/hive_flutter.dart';

/// Simple offline storage for scanned transactions using Hive.
/// Box: 'scans' stores Map<String, dynamic> entries keyed by transactionId
class ScanStorage {
  static const _boxName = 'scans';

  /// Initialize Hive box (call once at app startup)
  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<Map>(_boxName);
    }
  }

  static Box<Map> _box() => Hive.box<Map>(_boxName);

  /// Check whether a transactionId has already been scanned
  static bool hasScanned(String transactionId) {
    try {
      final existing = _box().get(transactionId);
      return existing != null;
    } catch (_) {
      return false;
    }
  }

  /// Check whether a bookingId has already been scanned (used for duplicate detection)
  static bool hasScannedByBookingId(String bookingId) {
    try {
      for (var entry in _box().values) {
        final map = Map<String, dynamic>.from(entry.cast<String, dynamic>());
        if (map['bookingId']?.toString() == bookingId) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Save a scan record. The payload map should contain at least transactionId and bookingId
  static Future<void> saveScan(Map<String, dynamic> record) async {
    final tx = record['transactionId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    await _box().put(tx, Map<String, dynamic>.from(record));
  }

  /// Retrieve a saved scan record by transactionId
  static Map<String, dynamic>? getScan(String transactionId) {
    final v = _box().get(transactionId);
    if (v == null) return null;
    return Map<String, dynamic>.from(v.cast<String, dynamic>());
  }

  /// Clear all saved scan records
  static Future<void> clearAll() async {
    try {
      await _box().clear();
    } catch (_) {}
  }
}
