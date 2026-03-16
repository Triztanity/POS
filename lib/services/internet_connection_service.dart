import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

/// InternetConnectionService
/// Monitors WiFi and internet connectivity status
class InternetConnectionService {
  static final InternetConnectionService _instance =
      InternetConnectionService._internal();

  factory InternetConnectionService() {
    return _instance;
  }

  InternetConnectionService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;

  // Stream controller for connectivity changes
  final _connectionStatusController = StreamController<bool>.broadcast();

  bool _isConnected = false;

  /// Get current connection status
  bool get isConnected => _isConnected;

  /// Get stream of connection status changes
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    try {
      debugPrint('[Internet] Initializing connectivity monitoring...');

      // Check initial state
      final result = await _connectivity.checkConnectivity();
      _isConnected = result != ConnectivityResult.none;
      debugPrint('[Internet] Initial state: $_isConnected');

      // Listen for changes
      _subscription = _connectivity.onConnectivityChanged.listen((result) {
        final newState = result != ConnectivityResult.none;
        if (_isConnected != newState) {
          _isConnected = newState;
          debugPrint('[Internet] Connection status changed: $_isConnected');
          if (!_connectionStatusController.isClosed) {
            _connectionStatusController.add(_isConnected);
          }
        }
      });

      debugPrint('[Internet] Connectivity monitoring initialized');
    } catch (e) {
      debugPrint('[Internet] Error initializing connectivity: $e');
    }
  }

  /// Check current internet connection
  Future<bool> checkConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isConnected = result != ConnectivityResult.none;
      return _isConnected;
    } catch (e) {
      debugPrint('[Internet] Error checking connection: $e');
      return false;
    }
  }

  /// Check if connected to WiFi
  Future<bool> isConnectedToWiFi() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result == ConnectivityResult.wifi;
    } catch (e) {
      debugPrint('[Internet] Error checking WiFi: $e');
      return false;
    }
  }

  /// Check if connected to mobile data
  Future<bool> isConnectedToMobileData() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result == ConnectivityResult.mobile;
    } catch (e) {
      debugPrint('[Internet] Error checking mobile data: $e');
      return false;
    }
  }

  /// Backward-compatible method name used by existing dialogs.
  /// Returns true when any network is available.
  Future<bool> isConnectedToGateway() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      debugPrint('[Internet] Error checking gateway: $e');
      return false;
    }
  }

  /// Dispose and cleanup
  void dispose() {
    _subscription?.cancel();
    _connectionStatusController.close();
    debugPrint('[Internet] Connectivity monitoring disposed');
  }
}
