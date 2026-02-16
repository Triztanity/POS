import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import '../utils/dialogs.dart';

class InternetConnectivityDialog extends StatefulWidget {
  const InternetConnectivityDialog({super.key});

  @override
  State<InternetConnectivityDialog> createState() =>
      _InternetConnectivityDialogState();
}

class _InternetConnectivityDialogState
    extends State<InternetConnectivityDialog> {
  final Connectivity _connectivity = Connectivity();
  bool _isConnected = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    setState(() => _isChecking = true);
    try {
      final result = await _connectivity.checkConnectivity();
      setState(() {
        _isConnected = result != ConnectivityResult.none;
        _isChecking = false;
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isChecking = false;
      });
    }
  }

  Future<void> _openWiFiSettings() async {
    if (Platform.isAndroid) {
      final intent = AndroidIntent(action: 'android.settings.WIFI_SETTINGS');
      await intent.launch();
    } else {
      // For non-Android platforms we can't programmatically open WiFi settings reliably;
      // just show a brief message to the user.
      if (!mounted) return;
      await Dialogs.showMessage(
          context, 'Notice', 'Please open Wi-Fi settings on your device.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              const Text(
                'Internet Connection',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Status indicator
              if (_isChecking)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Checking connection...',
                          style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? Colors.green.withAlpha(30)
                        : Colors.red.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isConnected ? Colors.green : Colors.red,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _isConnected ? Icons.wifi : Icons.wifi_off,
                        size: 48,
                        color: _isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isConnected
                            ? 'Connected to Internet'
                            : 'Not Connected',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isConnected ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isConnected
                            ? 'Your device is connected to the internet.'
                            : 'Please connect to WiFi to proceed.',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Refresh and open settings buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _checkConnectivity,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check Again'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openWiFiSettings,
                      icon: const Icon(Icons.wifi),
                      label: const Text('Wi‑Fi Settings'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Done button (only enabled if connected)
              ElevatedButton(
                onPressed:
                    _isConnected ? () => Navigator.pop(context, true) : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: _isConnected ? Colors.green : Colors.grey,
                  disabledBackgroundColor: Colors.grey,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
