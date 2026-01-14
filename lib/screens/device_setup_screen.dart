import 'package:flutter/material.dart';
import '../services/device_config_service.dart';

/// Device Setup Screen - Manual fallback when auto-detect fails
/// Allows user to select from registered devices or enter serial manually
class DeviceSetupScreen extends StatefulWidget {
  final VoidCallback onConfigured; // Called when device is successfully configured

  const DeviceSetupScreen({
    super.key,
    required this.onConfigured,
  });

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  String? _selectedSerial;
  final _manualSerialController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _manualSerialController.dispose();
    super.dispose();
  }

  Future<void> _configureDevice(String serial) async {
    setState(() => _isProcessing = true);
    try {
      final bus = DeviceConfigService.lookupBusForSerial(serial);
      if (bus != null) {
        await DeviceConfigService.setDeviceSerialAndBus(serial, bus);
        debugPrint('[DeviceSetup] Device configured: $serial → $bus');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Device configured: $serial → $bus')),
          );
          widget.onConfigured();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Serial not found in registry')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final registeredDevices = DeviceConfigService.listRegisteredDevices();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Configuration'),
        backgroundColor: Colors.blue[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select or Enter Device Serial',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Registered devices list
            const Text('Registered Devices:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...registeredDevices.entries.map((e) {
              final serial = e.key;
              final bus = e.value;
              return ListTile(
                title: Text(serial),
                subtitle: Text('Bus: $bus'),
                trailing: _selectedSerial == serial
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() => _selectedSerial = serial);
                  _manualSerialController.clear();
                },
              );
            }),
            const SizedBox(height: 24),
            // Manual entry fallback
            const Text('Or Enter Serial Manually:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _manualSerialController,
              decoration: InputDecoration(
                hintText: 'Enter device serial (e.g., H10P746259A0982)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (val) {
                setState(() => _selectedSerial = val.isNotEmpty ? val : null);
              },
            ),
            const SizedBox(height: 24),
            // Configure button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing || _selectedSerial == null || _selectedSerial!.isEmpty
                    ? null
                    : () => _configureDevice(_selectedSerial!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Configure Device', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            // Debug info
            ExpansionTile(
              title: const Text('Debug Info'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available serials:'),
                      ...registeredDevices.keys.map((s) => Text('  • $s')),
                      const SizedBox(height: 8),
                      Text('Selected: ${_selectedSerial ?? "none"}'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
