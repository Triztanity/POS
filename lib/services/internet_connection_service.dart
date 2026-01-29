import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

/// InternetConnectionService
/// Monitors WiFi and internet connectivity status
/// Also checks for ESP32 gateway reachability
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

  /// Check if ESP32 gateway is reachable (local network check)
  /// This checks if device is connected to ESP32's hotspot
  Future<bool> isESP32Reachable() async {
    try {
      debugPrint('[Internet] Checking ESP32 gateway reachability...');

      // Try to reach ESP32 at its default gateway IP
      final response = await http
          .get(Uri.parse('http://192.168.4.1/'))
          .timeout(const Duration(seconds: 3));

      final reachable =
          response.statusCode == 200 || response.statusCode == 404;
      debugPrint('[Internet] ESP32 reachable: $reachable');
      return reachable;
    } catch (e) {
      debugPrint('[Internet] ESP32 not reachable: $e');
      return false;
    }
  }

  /// Check if connected to ESP32 gateway (ONLY checks ESP32, no fallback)
  Future<bool> isConnectedToGateway() async {
    try {
      // First check if we have WiFi connection
      final result = await _connectivity.checkConnectivity();
      if (result == ConnectivityResult.none) {
        debugPrint('[Internet] No WiFi/network connection');
        return false;
      }

      // Check if ESP32 is reachable (local gateway)
      final esp32Available = await isESP32Reachable();
      debugPrint('[Internet] ESP32 gateway status: $esp32Available');
      return esp32Available;
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
