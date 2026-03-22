import 'package:flutter/material.dart';
import 'dart:async';
import 'nfc_reader_mode_service.dart';
import 'app_state.dart';

/// Global inspector NFC handler.
/// Intercepts cards with 'inspector' role from anywhere in the app
/// and navigates to the Inspector Screen.
class InspectorNFCHandler {
  InspectorNFCHandler._internal();
  static final InspectorNFCHandler instance = InspectorNFCHandler._internal();

  StreamSubscription? _nfcSub;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialized = false;

  /// Initialize the handler with the global navigator key
  void initialize(GlobalKey<NavigatorState> navigatorKey) {
    if (_initialized) {
      debugPrint('[INSPECTOR-HANDLER] Already initialized');
      return;
    }

    _navigatorKey = navigatorKey;
    _initialized = true;
    debugPrint('[INSPECTOR-HANDLER] Initialized with navigator key');

    _nfcSub = NFCReaderModeService.instance.onTag.listen(
      (user) {
        try {
          // If an inspector modal (signature dialog) is active, ignore global inspector NFC events
          if (AppState.instance.inspectorModalActive) return;
        } catch (_) {}

        debugPrint('[INSPECTOR-HANDLER] Received tag event: $user');
        final role = user['role']?.toString() ?? '';
        final name = user['name']?.toString() ?? '';

        // Only allow inspector navigation if logged in, on the home screen, AND it is the top-most active route
        final conductor = AppState.instance.conductor;
        final driver = AppState.instance.driver;
        final isLoggedIn = conductor != null && driver != null;
        final isOnHomeScreen = AppState.instance.currentScreen == 'home_screen';

        bool isTopRouteFirst = false;
        if (_navigatorKey != null && _navigatorKey!.currentState != null) {
          _navigatorKey!.currentState!.popUntil((route) {
            isTopRouteFirst = route.isFirst;
            return true; // We don't want to actually pop anything
          });
        }

        if (role.toLowerCase() == 'inspector' &&
            isLoggedIn &&
            isOnHomeScreen &&
            isTopRouteFirst) {
          debugPrint(
              '[INSPECTOR-HANDLER] Inspector card detected! Name=$name, attempting navigation');
          _navigateToInspector();
        } else if (role.toLowerCase() == 'inspector') {
          debugPrint(
              '[INSPECTOR-HANDLER] Inspector card ignored: logged_in=$isLoggedIn, screen=${AppState.instance.currentScreen}');
        } else {
          debugPrint('[INSPECTOR-HANDLER] Non-inspector card, role=$role');
        }
      },
      onError: (error) {
        debugPrint('[INSPECTOR-HANDLER] Stream error: $error');
      },
    );
  }

  void _navigateToInspector() {
    if (_navigatorKey == null) {
      debugPrint('[INSPECTOR-HANDLER] Navigator key not set');
      return;
    }

    final state = _navigatorKey!.currentState;
    if (state == null) {
      debugPrint('[INSPECTOR-HANDLER] Navigator state is null');
      return;
    }
    try {
      // Avoid pushing inspector route if it's already the current top route
      try {
        final currentRouteName = ModalRoute.of(state.context)?.settings.name;
        if (currentRouteName == '/inspector') {
          debugPrint(
              '[INSPECTOR-HANDLER] Already on /inspector, skipping navigation');
          return;
        }
      } catch (_) {
        // ignore
      }

      debugPrint('[INSPECTOR-HANDLER] Pushing /inspector route');
      state.pushNamed('/inspector');
      debugPrint('[INSPECTOR-HANDLER] Navigation successful');
    } catch (e) {
      debugPrint('[INSPECTOR-HANDLER] Error navigating: $e');
    }
  }

  void dispose() {
    debugPrint('[INSPECTOR-HANDLER] Disposing');
    _nfcSub?.cancel();
    _nfcSub = null;
    _initialized = false;
  }
}
