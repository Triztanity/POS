import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'device_identifier_service.dart';
import 'package:senraise_printer/senraise_printer.dart';

/// DeviceConfigService
/// - Holds a small registry mapping known device serials -> bus ids
/// - Attempts to auto-detect the current device serial via native identifiers
/// - Persists assigned bus and device serial into a Hive box named 'device_config'
class DeviceConfigService {
  static const _boxName = 'device_config';
  static const _deviceSerialKey = 'deviceSerial';
  static const _assignedBusKey = 'assignedBus';

  // Maintain the registry here. Map device identifiers to bus assignments.
  // Key can be: full serial (preferred), model prefix, or androidId
  static final Map<String, String> _deviceRegistry = {
    // Full serial numbers (preferred - most specific)
    'H10P746259A0982': 'BUS-002',
    'H10P74625AU0044': 'BUS-001',
    // Android IDs (strong identifier for these devices)
    'e9fb9c8908a3cb9f': 'BUS-002', // androidId for H10P746259A0982
    '2590ecaf10bb2b56': 'BUS-001', // androidId for BUS-001 device
  };

  /// Open config box if not open
  static Future<Box> _openBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  static Future<String?> getAssignedBus() async {
    try {
      final box = await _openBox();
      return box.get(_assignedBusKey) as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getDeviceSerial() async {
    try {
      final box = await _openBox();
      return box.get(_deviceSerialKey) as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setDeviceSerialAndBus(String serial, String bus) async {
    final box = await _openBox();
    await box.put(_deviceSerialKey, serial);
    await box.put(_assignedBusKey, bus);
  }

  /// Clear cached bus assignment (used before re-detection)
  static Future<void> clearAssignment() async {
    try {
      final box = await _openBox();
      await box.delete(_assignedBusKey);
      await box.delete(_deviceSerialKey);
    } catch (_) {}
  }

  /// Returns true if the serial exists in registry
  static bool isRegisteredSerial(String serial) {
    return _deviceRegistry.containsKey(serial);
  }

  /// Lookup bus for a known serial
  static String? lookupBusForSerial(String serial) {
    return _deviceRegistry[serial];
  }

  /// Attempt to auto-detect the device and persist its assigned bus.
  /// Logs identifiers received from native/printer APIs for debugging.
  /// Returns the assigned bus if found, null otherwise.
  static Future<String?> autoDetectAndSaveAssignedBus() async {
    debugPrint('[DeviceConfig] Starting auto-detect...');
    
    // 1) Try native identifiers
    try {
      final ids = await DeviceIdentifierService.getDeviceIdentifiers();
      if (ids != null) {
        debugPrint('[DeviceConfig] Native identifiers: $ids');

        // Priority 1: Exact serial match
        final serial = ids['serial'];
        if (serial != null && serial.isNotEmpty) {
          debugPrint('[DeviceConfig] Trying exact serial: "$serial"');
          if (_deviceRegistry.containsKey(serial)) {
            final bus = _deviceRegistry[serial]!;
            debugPrint('[DeviceConfig] ✓ Exact serial match: "$serial" → "$bus"');
            await setDeviceSerialAndBus(serial, bus);
            return bus;
          }
        }

        // Priority 2: Exact androidId match
        final androidId = ids['androidId'];
        if (androidId != null && androidId.isNotEmpty) {
          debugPrint('[DeviceConfig] Trying exact androidId: "$androidId"');
          if (_deviceRegistry.containsKey(androidId)) {
            final bus = _deviceRegistry[androidId]!;
            debugPrint('[DeviceConfig] ✓ Exact androidId match: "$androidId" → "$bus"');
            await setDeviceSerialAndBus(androidId, bus);
            return bus;
          }
        }

        debugPrint('[DeviceConfig] No match for native identifiers');
      } else {
        debugPrint('[DeviceConfig] Native identifiers returned null');
      }
    } catch (e) {
      debugPrint('[DeviceConfig] Native identifier error: $e');
    }

    // 2) Try printer service version (best-effort)
    try {
      final ver = await SenraisePrinter().getServiceVersion();
      debugPrint('[DeviceConfig] Printer service version: $ver');
      if (ver != null && ver.isNotEmpty) {
        final verNorm = _normalize(ver);
        for (final key in _deviceRegistry.keys) {
          if (ver.contains(key) || verNorm.contains(_normalize(key))) {
            final bus = _deviceRegistry[key]!;
            debugPrint('[DeviceConfig] ✓ Match found (printer): $key → $bus');
            await setDeviceSerialAndBus(key, bus);
            return bus;
          }
        }
      }
    } catch (e) {
      debugPrint('[DeviceConfig] Printer service error: $e');
    }

    debugPrint('[DeviceConfig] ✗ No match found. Available devices: ${_deviceRegistry.keys.toList()}');
    return null;
  }

  static String _normalize(String s) {
    return s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  /// Expose registry for debug/testing
  static Map<String, String> listRegisteredDevices() => Map.from(_deviceRegistry);
}
