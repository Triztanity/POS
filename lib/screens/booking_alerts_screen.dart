import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_config_service.dart';
import '../services/sms_booking_alert_service.dart';

class BookingAlertsScreen extends StatefulWidget {
  const BookingAlertsScreen({super.key});

  @override
  State<BookingAlertsScreen> createState() => _BookingAlertsScreenState();
}

class _BookingAlertsScreenState extends State<BookingAlertsScreen> {
  final SmsBookingAlertService _service = SmsBookingAlertService();
  List<Map<String, dynamic>> _alerts = [];
  StreamSubscription<Map<String, dynamic>>? _sub;
  String _assignedBus = '';

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _service.alertsStream.listen((alert) {
      if (!mounted) return;
      setState(() {
        final bus = (alert['busNumber'] ?? '').toString().trim().toUpperCase();
        if (_assignedBus.isEmpty || bus.isEmpty || bus == _assignedBus) {
          _alerts.insert(0, alert);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final assigned =
        (await DeviceConfigService.getAssignedBus() ?? '').trim().toUpperCase();
    await _service.startListening();
    final alerts = await _service.getStoredAlerts();
    final filtered = assigned.isEmpty
        ? alerts
        : alerts.where((a) {
            final bus = (a['busNumber'] ?? '').toString().trim().toUpperCase();
            return bus.isEmpty || bus == assigned;
          }).toList();
    if (!mounted) return;
    setState(() {
      _assignedBus = assigned;
      _alerts = filtered;
    });
  }

  Future<void> _clear() async {
    await _service.clearAll();
    if (!mounted) return;
    setState(() {
      _alerts = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Alerts'),
        backgroundColor: Colors.green[700],
        actions: [
          IconButton(
            onPressed: _clear,
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear alerts',
          ),
        ],
      ),
      body: _alerts.isEmpty
          ? const Center(
              child: Text(
                'No booking alerts yet.',
                style: TextStyle(fontSize: 16),
              ),
            )
          : ListView.separated(
              itemCount: _alerts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _alerts[index];
                final bookingId = item['bookingId']?.toString() ?? '';
                final origin = item['origin']?.toString() ?? 'Unknown';
                final seats = item['seats']?.toString() ?? '0';
                final sender = item['sender']?.toString() ?? '';
                final receivedAt = item['receivedAtIso']?.toString() ?? '';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green[100],
                    child: const Icon(Icons.sms, color: Colors.green),
                  ),
                  title: Text('Origin: $origin'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Seats: $seats'),
                      if (bookingId.isNotEmpty) Text('Booking ID: $bookingId'),
                      if (sender.isNotEmpty) Text('Sender: $sender'),
                      if (receivedAt.isNotEmpty) Text('Received: $receivedAt'),
                    ],
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}
