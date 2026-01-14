import 'package:flutter/foundation.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import '../local_storage.dart';

class NFCAuthService {
  /// Polls the NFC reader for a single tag and returns the UID string (or null).
  /// Uses `flutter_nfc_kit` which reliably returns `tag.id` on Android devices.
  /// Polls the NFC reader with retries. Returns normalized UID or null.
  Future<String?> pollUid({int timeoutSeconds = 10, int attempts = 2}) async {
    for (var attempt = 1; attempt <= attempts; attempt++) {
      debugPrint('[NFC] poll attempt $attempt/$attempts (timeout=${timeoutSeconds}s)');
      try {
        final tag = await FlutterNfcKit.poll(timeout: Duration(seconds: timeoutSeconds));
        final raw = tag.id;
        try {
          await FlutterNfcKit.finish();
        } catch (_) {}
        if (raw.isEmpty) {
          debugPrint('[NFC] empty tag id');
          return null;
        }
        final uid = raw.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();
        debugPrint('[NFC] detected uid=$uid');
        return uid.isEmpty ? null : uid;
      } catch (e) {
        debugPrint('[NFC] poll error (attempt $attempt): $e');
        try {
          await FlutterNfcKit.finish();
        } catch (_) {}
        if (attempt < attempts) await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    debugPrint('[NFC] pollUid: no tag after $attempts attempts');
    return null;
  }

  /// Polls and attempts to login by UID from local storage. Returns matched user map or null.
  Future<Map<String, dynamic>?> scanAndAuthenticate() async {
    final uid = await pollUid();
    if (uid == null) return null;
    final user = LocalStorage.getEmployee(uid);
    return user;
  }
}
