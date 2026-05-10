import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'employee_account_service.dart';

/// NFCReaderModeService bridges Android's native NFC ReaderMode to Flutter.
/// ReaderMode is more reliable than polling and provides immediate tag detection
/// while the activity is in the foreground.
class NFCReaderModeService {
  NFCReaderModeService._internal();

  static final NFCReaderModeService instance = NFCReaderModeService._internal();

  static const platform = MethodChannel('com.example.untitled/nfc');
  static const eventChannel = EventChannel('com.example.untitled/nfc_tags');

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onTag => _controller.stream;

  bool _running = false;
  String? _lastEmittedUid;
  StreamSubscription? _methodSub;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) {
      debugPrint('[NFC-READER-MODE] already running');
      return;
    }
    debugPrint('[NFC-READER-MODE] starting...');
    _running = true;
    _lastEmittedUid = null;

    // Listen for native tag detection events via EventChannel
    _methodSub = eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        debugPrint(
            '[NFC-READER-MODE] raw event received: ${event.runtimeType} -> $event');

        // Accept several event shapes from native side:
        // - Map with 'uid' key
        // - String uid
        // - List<int> bytes (convert to hex)
        try {
          if (event is Map) {
            final uid = event['uid']?.toString();
            if (uid != null && uid.isNotEmpty) {
              unawaited(_handleTagDetected(uid));
              return;
            }
            // maybe the map itself contains normalized fields
            final raw = event['raw']?.toString();
            if (raw != null && raw.isNotEmpty) {
              unawaited(_handleTagDetected(raw));
              return;
            }
          } else if (event is String) {
            unawaited(_handleTagDetected(event));
            return;
          } else if (event is List<int>) {
            final hex = event
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join()
                .toUpperCase();
            unawaited(_handleTagDetected(hex));
            return;
          }
        } catch (e) {
          debugPrint('[NFC-READER-MODE] error processing event: $e');
        }
        // Unknown event shape
        debugPrint('[NFC-READER-MODE] unknown event shape, ignoring');
      },
      onError: (error) {
        debugPrint('[NFC-READER-MODE] stream error: $error');
      },
    );

    try {
      await platform.invokeMethod('enableReaderMode');
      debugPrint('[NFC-READER-MODE] reader mode enabled');
    } catch (e) {
      debugPrint('[NFC-READER-MODE] error enabling reader mode: $e');
    }
  }

  Future<void> stop() async {
    if (!_running) {
      debugPrint('[NFC-READER-MODE] not running');
      return;
    }
    debugPrint('[NFC-READER-MODE] stopping...');
    _running = false;
    _lastEmittedUid = null;

    try {
      await platform.invokeMethod('disableReaderMode');
      debugPrint('[NFC-READER-MODE] reader mode disabled');
    } catch (e) {
      debugPrint('[NFC-READER-MODE] error disabling reader mode: $e');
    }

    await _methodSub?.cancel();
    _methodSub = null;
  }

  Future<void> _handleTagDetected(String uid) async {
    final normalizedUid = EmployeeAccountService.normalizeUid(uid);
    if (normalizedUid.isEmpty) {
      debugPrint('[NFC-READER-MODE] ignored empty uid: $uid');
      return;
    }

    debugPrint(
        '[NFC-READER-MODE] tag detected: $normalizedUid, lastEmitted=$_lastEmittedUid');

    // Debounce: avoid rapid re-reads of the same tag
    if (_lastEmittedUid == normalizedUid) {
      debugPrint('[NFC-READER-MODE] same uid, debounce skipping');
      return;
    }
    _lastEmittedUid = normalizedUid;

    final user = await EmployeeAccountService().resolveCard(uid);
    if (user != null) {
      final role = user['role']?.toString() ?? '';
      final name = user['name']?.toString() ?? '';
      final source =
          user['resolvedFromFirebase'] == true ? 'firebase' : 'local';
      debugPrint(
          '[NFC-READER-MODE] emit user name=$name role=$role uid=$normalizedUid source=$source');
      debugPrint('[NFC-READER-MODE] user map: $user');
      _controller.add(user);
    } else {
      final unknown = EmployeeAccountService().unknownCardPayload(uid);
      debugPrint('[NFC-READER-MODE] uid $normalizedUid not recognized');
      _controller.add(unknown);
    }

    // Debounce for 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (_lastEmittedUid == normalizedUid) {
        _lastEmittedUid = null;
        debugPrint('[NFC-READER-MODE] debounce cleared for uid=$normalizedUid');
      }
    });
  }

  /// Clear debounce so the same UID can be read again immediately.
  void resetDebounce() {
    debugPrint(
        '[NFC-READER-MODE] resetDebounce called (last=$_lastEmittedUid)');
    _lastEmittedUid = null;
  }
}
