import 'dart:async';
import 'package:flutter/foundation.dart';
import '../local_storage.dart';
import 'nfc_reader_mode_service.dart';

/// AppState: global app state that persists across screen navigation.
/// Holds the current session info (conductor and driver).
class AppState {
  AppState._internal();

  static final AppState instance = AppState._internal();

  Map<String, dynamic>? _conductor;
  Map<String, dynamic>? _driver;

  Map<String, dynamic>? get conductor => _conductor;
  Map<String, dynamic>? get driver => _driver;
  Map<String, dynamic>? _pendingDriver;

  Map<String, dynamic>? get pendingDriver => _pendingDriver;

  StreamSubscription<Map<String, dynamic>>? _nfcSub;
  bool _inspectorModalActive = false;

  bool get inspectorModalActive => _inspectorModalActive;

  void setInspectorModalActive(bool v) {
    _inspectorModalActive = v;
  }

  void setConductor(Map<String, dynamic>? conductor) {
    debugPrint('[APP-STATE] setConductor: ${conductor?['name']}');
    _conductor = conductor;
  }

  void setDriver(Map<String, dynamic>? driver) {
    debugPrint('[APP-STATE] setDriver: ${driver?['name']}');
    _driver = driver;
    // Persist to local storage so driver remains until logout or dispatcher change
    if (driver != null) {
      LocalStorage.saveCurrentDriver(driver);
    } else {
      LocalStorage.clearCurrentDriver();
    }
  }

  /// Start a global NFC listener that will register driver card taps application-wide.
  /// Behavior:
  /// - If no driver currently set and a driver card is tapped, register it immediately.
  /// - If a driver is already set and a different driver taps, set _pendingDriver
  ///   (dispatcher approval flow remains handled by ProfileScreen when active).
  void startNfcListener() {
    if (_nfcSub != null) return; // already started
    _nfcSub = NFCReaderModeService.instance.onTag.listen((user) {
      try {
        final role = (user['role'] ?? '').toString().toLowerCase();
        final uid = user['uid']?.toString();
        if (role == 'driver') {
          final currentUid = _driver?['uid']?.toString();
          if (_driver == null) {
            debugPrint(
                '[APP-STATE] global NFC: registering driver ${user['name']}');
            setDriver(user);
          } else if (currentUid != uid) {
            debugPrint(
                '[APP-STATE] global NFC: different driver tapped, setting pendingDriver');
            _pendingDriver = user;
          } else {
            // same driver tapped again - ignore
          }
        } else if (role == 'dispatcher') {
          // If there's a pending driver change and dispatcher tapped, approve it here
          if (_pendingDriver != null) {
            debugPrint(
                '[APP-STATE] dispatcher tapped, approving pending driver change');
            setDriver(_pendingDriver);
            _pendingDriver = null;
          }
        }
      } catch (e) {
        debugPrint('[APP-STATE] error in global NFC handler: $e');
      }
    });
  }

  void stopNfcListener() {
    _nfcSub?.cancel();
    _nfcSub = null;
  }

  void clearSession() {
    debugPrint('[APP-STATE] clearSession');
    _conductor = null;
    _driver = null;
  }
}
