import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../services/esp32_bluetooth_service.dart';

/// BluetoothConnectionDialog
/// Modal dialog shown when Bluetooth is required but unavailable.
/// Allows user to open Bluetooth settings and check connection status.
class BluetoothConnectionDialog extends StatefulWidget {
  final ESP32BluetoothService bluetoothService;
  final VoidCallback onConnected;

  const BluetoothConnectionDialog({
    super.key,
    required this.bluetoothService,
    required this.onConnected,
  });

  @override
  State<BluetoothConnectionDialog> createState() => _BluetoothConnectionDialogState();
}

class _BluetoothConnectionDialogState extends State<BluetoothConnectionDialog> {
  bool _isChecking = false;
  String? _statusMessage;
  bool _bluetoothEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBluetoothStatus();
  }

  /// Check current Bluetooth status
  Future<void> _checkBluetoothStatus() async {
    setState(() => _isChecking = true);
    
    try {
      final enabled = await widget.bluetoothService.isBluetoothEnabled();
      
      if (!mounted) return;
      
      setState(() {
        _bluetoothEnabled = enabled;
        if (enabled) {
          _statusMessage = 'Checking connection to ESP32...';
        } else {
          _statusMessage = 'Bluetooth is OFF. Please enable it.';
        }
      });

      if (enabled) {
        // Try to connect if Bluetooth is enabled
        await _checkESP32Connection();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Error checking Bluetooth: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  /// Check if connected to ESP32
  Future<void> _checkESP32Connection() async {
    try {
      final connected = await widget.bluetoothService.checkESP32ConnectionStatus();
      
      if (!mounted) return;
      
      if (connected == true) {
        _statusMessage = '✓ Connected to ESP32';
        // Auto-close dialog on successful connection
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            widget.onConnected();
            Navigator.of(context).pop();
          }
        });
      } else {
        _statusMessage = '✗ ESP32 device not found. Make sure it\'s powered on and nearby.';
      }
      
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Error connecting: $e');
      }
    }
  }

  /// Open device Bluetooth settings
  Future<void> _openBluetoothSettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.BLUETOOTH_SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening Bluetooth settings: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(horizontal: screenW * 0.1),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon and title
            Icon(
              Icons.bluetooth,
              size: 48,
              color: _bluetoothEnabled ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 16),
            const Text(
              'Bluetooth Connection Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Status message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bluetoothEnabled ? Colors.green[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _bluetoothEnabled ? Colors.green[300]! : Colors.orange[300]!,
                ),
              ),
              child: Text(
                _statusMessage ?? 'Checking Bluetooth status...',
                style: TextStyle(
                  fontSize: 14,
                  color: _bluetoothEnabled ? Colors.green[800] : Colors.orange[800],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // Description
            const Text(
              'Your device\'s Bluetooth needs to be ON and connected to the ESP32 bus system to use the booking features.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Buttons
            SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  // Check/Retry button
                  ElevatedButton.icon(
                    onPressed: _isChecking ? null : _checkBluetoothStatus,
                    icon: _isChecking
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_isChecking ? 'Checking...' : 'Check Connection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Bluetooth Settings button
                  ElevatedButton.icon(
                    onPressed: _isChecking ? null : _openBluetoothSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Bluetooth Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Continue anyway button
                  TextButton(
                    onPressed: _isChecking ? null : () => Navigator.of(context).pop(),
                    child: const Text(
                      'Continue Without Checking',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
