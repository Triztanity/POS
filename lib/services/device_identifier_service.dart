import 'package:flutter/services.dart';

class DeviceIdentifierService {
  static const MethodChannel _channel = MethodChannel('com.example.untitled/device');

  /// Returns a best-effort map of identifiers from the native platform.
  /// Keys: androidId, serial, manufacturer, model
  static Future<Map<String, String>?> getDeviceIdentifiers() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('getDeviceIdentifiers');
      if (result == null) return null;
      return Map<String, String>.from((result as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')));
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
