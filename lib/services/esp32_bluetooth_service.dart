import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';
import '../models/booking.dart';
import 'bluetooth_message_queue_service.dart';

/// ESP32BluetoothService
/// Handles Bluetooth Low Energy communication with the ESP32 device.
/// Manages connection, disconnection, and sending booking dropoff updates.
class ESP32BluetoothService {
  static final ESP32BluetoothService _instance = ESP32BluetoothService._internal();

  factory ESP32BluetoothService() {
    return _instance;
  }

  ESP32BluetoothService._internal();

  // Bluetooth configuration
  static const String _esp32ServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String _esp32CharacteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const String _esp32DeviceName = 'ESP32_BUS'; // Adjust based on your ESP32 name

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription? _connectionSubscription;
  bool _isInitialized = false;
  bool _isConnecting = false;

  // Getters
  bool get isConnected => _connectedDevice?.isConnected ?? false;
  bool get isConnecting => _isConnecting;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// Check if Bluetooth is supported on this device
  Future<bool> isBluetoothSupported() async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (e) {
      debugPrint('[ESP32 BT] Error checking Bluetooth support: $e');
      return false;
    }
  }

  /// Check if Bluetooth adapter state stream indicates it's ON
  /// Returns true if Bluetooth appears to be enabled
  Future<bool> isBluetoothEnabled() async {
    try {
      // Try to get current adapter state
      final adapterState = await FlutterBluePlus.adapterState.first;
      debugPrint('[ESP32 BT] Adapter state: $adapterState');
      
      // If state is on, it's enabled
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('[ESP32 BT] Error checking Bluetooth enabled state: $e');
      // If we can't determine, assume it might be off to be safe
      return false;
    }
  }

  /// Check connection status to ESP32
  /// Returns null if not checked, true if connected, false if not connected
  Future<bool?> checkESP32ConnectionStatus() async {
    if (_connectedDevice?.isConnected == true) {
      return true;
    }
    
    // Try to reconnect
    debugPrint('[ESP32 BT] Checking ESP32 connection status...');
    return await _connectToESP32();
  }

  /// Initialize Bluetooth and attempt connection to ESP32
  Future<bool> initializeBluetoothConnection() async {
    try {
      debugPrint('[ESP32 BT] Initializing Bluetooth connection...');
      
      // Check if Bluetooth is available
      if (!await FlutterBluePlus.isSupported) {
        debugPrint('[ESP32 BT] Bluetooth is not available on this device');
        return false;
      }

      // For newer versions of flutter_blue_plus, check if it's turned on
      // Note: isOff was removed, we just try to scan and handle errors
      debugPrint('[ESP32 BT] Checking Bluetooth state...');

      _isInitialized = true;
      debugPrint('[ESP32 BT] Bluetooth initialized successfully');
      
      // Attempt to connect
      return await _connectToESP32();
    } catch (e) {
      debugPrint('[ESP32 BT] Error initializing Bluetooth: $e');
      return false;
    }
  }

  /// Connect to ESP32 device
  Future<bool> _connectToESP32() async {
    if (_isConnecting) {
      debugPrint('[ESP32 BT] Already attempting to connect');
      return false;
    }

    try {
      _isConnecting = true;
      debugPrint('[ESP32 BT] Scanning for ESP32 device...');

      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
      );

      // Listen for scan results
      var found = false;
      var subscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.contains(_esp32DeviceName)) {
            debugPrint('[ESP32 BT] Found ESP32 device: ${r.device.platformName}');
            _connectedDevice = r.device;
            found = true;
            break;
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 5));
      await subscription.cancel();

      if (!found) {
        debugPrint('[ESP32 BT] ESP32 device not found. Check device name.');
        _isConnecting = false;
        return false;
      }

      // Connect to device
      if (_connectedDevice != null) {
        debugPrint('[ESP32 BT] Connecting to ${_connectedDevice!.platformName}...');
        await _connectedDevice!.connect(timeout: const Duration(seconds: 10));
        
        // Get service and characteristic
        final services = await _connectedDevice!.discoverServices();
        for (var service in services) {
          if (service.uuid.toString() == _esp32ServiceUuid) {
            for (var char in service.characteristics) {
              if (char.uuid.toString() == _esp32CharacteristicUuid) {
                _writeCharacteristic = char;
                debugPrint('[ESP32 BT] Write characteristic found');
              }
            }
          }
        }

        if (_writeCharacteristic == null) {
          debugPrint('[ESP32 BT] Write characteristic not found');
          await disconnect();
          _isConnecting = false;
          return false;
        }

        // Listen to connection state changes
        _connectionSubscription = _connectedDevice!.connectionState.listen((state) {
          debugPrint('[ESP32 BT] Connection state: $state');
          if (state == BluetoothConnectionState.disconnected) {
            _connectedDevice = null;
            _writeCharacteristic = null;
          }
        });

        _isConnecting = false;
        debugPrint('[ESP32 BT] Successfully connected to ESP32');
        return true;
      }

      _isConnecting = false;
      return false;
    } catch (e) {
      debugPrint('[ESP32 BT] Error connecting to ESP32: $e');
      _isConnecting = false;
      return false;
    }
  }

  /// Send booking dropoff update to ESP32
  Future<bool> sendBookingDropoffUpdate(Booking booking) async {
    try {
      // Ensure Bluetooth is initialized
      if (!_isInitialized) {
        await initializeBluetoothConnection();
      }

      // Prepare data
      final dropoffData = {
        'action': 'booking_dropoff',
        'bookingId': booking.id,
        'status': 'dropped-off',
        'dropoffTimestamp': DateTime.now().toIso8601String(),
        'passengerName': booking.passengerName,
        'fromLocation': booking.fromLocation,
        'toLocation': booking.toLocation,
        'passengers': booking.passengers,
      };

      debugPrint('[ESP32 BT] Preparing to send: ${jsonEncode(dropoffData)}');

      if (isConnected && _writeCharacteristic != null) {
        // Convert to JSON and then to bytes
        final jsonString = jsonEncode(dropoffData);
        final bytes = utf8.encode(jsonString);

        // Write to characteristic
        await _writeCharacteristic!.write(bytes, withoutResponse: false);
        
        debugPrint('[ESP32 BT] Successfully sent booking dropoff update for ${booking.id}');
        
        // Remove from queue if it was there
        await BluetoothMessageQueueService.removeByBookingId(booking.id);
        
        return true;
      } else {
        debugPrint('[ESP32 BT] Not connected to ESP32. Queueing message...');
        
        // Queue the message for later
        await BluetoothMessageQueueService.queueMessage(dropoffData);
        
        return false;
      }
    } catch (e) {
      debugPrint('[ESP32 BT] Error sending booking update: $e');
      
      // Queue the message on error
      try {
        final dropoffData = {
          'action': 'booking_dropoff',
          'bookingId': booking.id,
          'status': 'dropped-off',
          'dropoffTimestamp': DateTime.now().toIso8601String(),
          'passengerName': booking.passengerName,
          'fromLocation': booking.fromLocation,
          'toLocation': booking.toLocation,
          'passengers': booking.passengers,
        };
        await BluetoothMessageQueueService.queueMessage(dropoffData);
      } catch (queueError) {
        debugPrint('[ESP32 BT] Error queuing message: $queueError');
      }
      
      return false;
    }
  }

  /// Attempt to reconnect to ESP32
  Future<bool> reconnect() async {
    if (isConnected) {
      return true;
    }
    
    debugPrint('[ESP32 BT] Attempting to reconnect...');
    return await _connectToESP32();
  }

  /// Disconnect from ESP32
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        debugPrint('[ESP32 BT] Disconnected from ESP32');
      }
      _connectedDevice = null;
      _writeCharacteristic = null;
    } catch (e) {
      debugPrint('[ESP32 BT] Error disconnecting: $e');
    }
  }

  /// Cleanup resources
  Future<void> dispose() async {
    await _connectionSubscription?.cancel();
    await disconnect();
    _isInitialized = false;
  }

  /// Retry sending all queued messages
  Future<void> retryQueuedMessages() async {
    try {
      if (!isConnected) {
        debugPrint('[ESP32 BT] Not connected. Cannot retry queued messages.');
        return;
      }

      final messages = await BluetoothMessageQueueService.getQueuedMessages();
      debugPrint('[ESP32 BT] Retrying ${messages.length} queued messages...');

      for (final message in messages) {
        try {
          final jsonString = jsonEncode(message['data']);
          final bytes = utf8.encode(jsonString);
          
          if (_writeCharacteristic != null) {
            await _writeCharacteristic!.write(bytes, withoutResponse: false);
            await BluetoothMessageQueueService.removeMessageFromQueue(message['id']);
            debugPrint('[ESP32 BT] Retried message: ${message["id"]}');
          }
        } catch (e) {
          debugPrint('[ESP32 BT] Error retrying message ${message["id"]}: $e');
          await BluetoothMessageQueueService.incrementRetryCount(message['id']);
        }
      }
    } catch (e) {
      debugPrint('[ESP32 BT] Error retrying queued messages: $e');
    }
  }
}
