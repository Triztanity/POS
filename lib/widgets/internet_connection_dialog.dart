import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../services/internet_connection_service.dart';
import '../utils/dialogs.dart';

/// InternetConnectionDialog
/// Modal dialog shown when internet connection is required but unavailable
class InternetConnectionDialog extends StatefulWidget {
  final VoidCallback onConnected;

  const InternetConnectionDialog({
    super.key,
    required this.onConnected,
  });

  @override
  State<InternetConnectionDialog> createState() =>
      _InternetConnectionDialogState();
}

class _InternetConnectionDialogState extends State<InternetConnectionDialog> {
  bool _isChecking = false;
  String? _statusMessage;
  bool _isConnected = false;
  final _internetService = InternetConnectionService();

  @override
  void initState() {
    super.initState();
    _checkConnection();

    // Listen for connection changes
    _internetService.connectionStatusStream.listen((isConnected) {
      if (isConnected && mounted) {
        setState(() {
          _isConnected = true;
          _statusMessage = '✓ Connected to ESP32 gateway';
        });
      }
    });
  }

  /// Check current internet connection
  Future<void> _checkConnection() async {
    setState(() => _isChecking = true);

    try {
      final isConnected = await _internetService.isConnectedToGateway();

      if (!mounted) return;

      setState(() {
        _isConnected = isConnected;
        if (isConnected) {
          _statusMessage = '✓ Connected to ESP32 gateway';
        } else {
          _statusMessage = 'Not connected to ESP32 gateway';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _statusMessage = 'Error checking connection: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  /// Open device internet/WiFi settings
  Future<void> _openInternetSettings() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.WIFI_SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (e) {
      if (mounted) {
        await Dialogs.showMessage(
            context, 'Error', 'Error opening WiFi settings: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(horizontal: mq.size.width * 0.1),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon and title
            Icon(
              Icons.wifi_off,
              size: 48,
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            const Text(
              'ESP32 Gateway Required',
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
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage ?? 'Checking connection...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.orange[900],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Info text
            const Text(
              'To mark as dropped-off, connect to:',
              style: TextStyle(fontSize: 14, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Text(
                'ESP32 WiFi Hotspot',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Check button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: EdgeInsets.symmetric(vertical: screenH * 0.015),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isChecking ? null : _checkConnection,
                child: Text(
                  _isChecking ? 'Checking...' : 'Check Connection',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Conditional button: Open WiFi Settings OR Proceed
            if (!_isConnected) ...[
              // Open WiFi settings button (shown when NOT connected)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: screenH * 0.015),
                    side: BorderSide(color: Colors.orange[700]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _openInternetSettings,
                  child: Text(
                    'Open WiFi Settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[700],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Info message
              Text(
                'Connect to ESP32 hotspot via WiFi settings and return here.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              // Proceed button (shown when connected)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: EdgeInsets.symmetric(vertical: screenH * 0.015),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onConnected();
                  },
                  child: const Text(
                    'Proceed',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
