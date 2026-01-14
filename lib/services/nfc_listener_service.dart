import 'dart:async';

import 'package:flutter/foundation.dart';
import 'nfc_auth_service.dart';
import '../local_storage.dart';

/// NFCListenerService continuously polls the NFC reader while running and
/// emits user records when known tags are detected. Intended for foreground
/// use only (app must be open).
class NFCListenerService {
  NFCListenerService._internal();

  static final NFCListenerService instance = NFCListenerService._internal();

  final NFCAuthService _nfc = NFCAuthService();
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onTag => _controller.stream;

  bool _running = false;
  String? _lastEmittedUid;
    Future<void>? _loopFuture;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) {
      debugPrint('[NFC-LISTENER] already running, skipping start');
      return;
    }
    debugPrint('[NFC-LISTENER] starting listener...');
    // Ensure previous loop finished if any
    if (_loopFuture != null) {
      debugPrint('[NFC-LISTENER] waiting for previous loop to finish');
      await _loopFuture;
    }
    _running = true;
    _lastEmittedUid = null; // Reset debounce on start
    debugPrint('[NFC-LISTENER] debounce cleared, starting poll loop');
    _loopFuture = _pollLoop();
  }

  Future<void> stop() async {
    if (!_running) {
      debugPrint('[NFC-LISTENER] not running, skipping stop');
      return;
    }
    debugPrint('[NFC-LISTENER] stopping listener...');
    _running = false;
    // Clear debounce so the same tag can be read again after stop/start
    _lastEmittedUid = null;
    // Wait for loop to finish
    if (_loopFuture != null) {
      debugPrint('[NFC-LISTENER] waiting for loop to finish');
      await _loopFuture;
    }
    _loopFuture = null;
    debugPrint('[NFC-LISTENER] stopped');
  }

  Future<void> _pollLoop() async {
    int pollCount = 0;
    while (_running) {
      pollCount++;
      try {
        // Short timeout for fast failure and recovery
        debugPrint('[NFC-LISTENER] poll #$pollCount (running=$_running)');
        final uid = await _nfc.pollUid(timeoutSeconds: 3, attempts: 1);
        if (!_running) break;

        if (uid != null && uid.isNotEmpty) {
          debugPrint('[NFC-LISTENER] read uid=$uid, lastEmitted=$_lastEmittedUid');
          // Avoid flooding with repeated reads of the SAME tag
          if (_lastEmittedUid != uid) {
            final user = LocalStorage.getEmployee(uid);
            if (user != null) {
              final role = user['role'].toString();
              debugPrint('[NFC-LISTENER] emit user ${user['name']} role=$role');
              _controller.add(user);
              _lastEmittedUid = uid;
              // Debounce: 3-second wait before accepting the same tag again
              await Future.delayed(const Duration(seconds: 3));
            } else {
              debugPrint('[NFC-LISTENER] uid $uid not in LocalStorage');
            }
          } else {
            debugPrint('[NFC-LISTENER] uid $uid already emitted recently, skipping');
          }
        }
      } catch (e) {
        debugPrint('[NFC-LISTENER] poll error: $e');
        // On timeout/error, clear debounce to allow quick recovery on next tap
        if (e.toString().contains('408') || e.toString().contains('timeout')) {
          _lastEmittedUid = null;
          debugPrint('[NFC-LISTENER] cleared debounce on timeout');
        }
      }

      // Brief idle to avoid tight loop
      if (_running) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    debugPrint('[NFC-LISTENER] stopped polling after $pollCount attempts');
  }
}
