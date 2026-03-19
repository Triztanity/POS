import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/material.dart';

import '../services/device_config_service.dart';
import '../services/qr_validation_service.dart';
import '../services/sms_booking_alert_service.dart';
import '../utils/route_validator.dart' as route_validator;

class BookingAlertsScreen extends StatefulWidget {
  final String? routeDirection;

  const BookingAlertsScreen({super.key, this.routeDirection});

  @override
  State<BookingAlertsScreen> createState() => _BookingAlertsScreenState();
}

class _BookingAlertsScreenState extends State<BookingAlertsScreen> {
  final SmsBookingAlertService _service = SmsBookingAlertService();
  List<Map<String, dynamic>> _alerts = [];
  StreamSubscription<Map<String, dynamic>>? _sub;
  String _assignedBus = '';
  String _activeScheduleTimeKey = '';
  String _activeRouteDirectionKey = '';

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _service.alertsStream.listen((_) async {
      if (_assignedBus.isNotEmpty) {
        await _loadActiveScheduleKeys(_assignedBus);
      } else {
        _activeScheduleTimeKey = '';
        _activeRouteDirectionKey = '';
      }
      final latest = await _service.getStoredAlerts();
      if (!mounted) return;
      setState(() {
        _alerts = _normalizeForViewAll(latest, _assignedBus);
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
    if (assigned.isNotEmpty) {
      await _loadActiveScheduleKeys(assigned);
    }
    await _service.startListening();
    final alerts = await _service.getStoredAlerts();
    if (!mounted) return;
    setState(() {
      _assignedBus = assigned;
      _alerts = _normalizeForViewAll(alerts, assigned);
    });
  }

  Future<void> _loadActiveScheduleKeys(String assignedBus) async {
    if (assignedBus.trim().isEmpty) {
      _activeScheduleTimeKey = '';
      _activeRouteDirectionKey = '';
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('schedules')
          .where('busNumber', isEqualTo: assignedBus)
          .where('status', isEqualTo: 'departed')
          .orderBy('dispatchTime', descending: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _activeScheduleTimeKey = '';
        _activeRouteDirectionKey = '';
        return;
      }

      final data = query.docs.first.data();
      _activeScheduleTimeKey = _normalizeScheduleKey(
        (data['ScheduledTimeStr'] ??
            data['scheduledTimeStr'] ??
            data['ScheduleTime'] ??
            data['scheduleTime'] ??
            data['scheduledTime'] ??
            data['scheduledTimeSTR']),
      );
      _activeRouteDirectionKey = _deriveRouteDirectionFromText(
        (data['route'] ?? data['routeName'] ?? data['busRoute'] ?? '')
            .toString(),
      );
    } catch (_) {
      _activeScheduleTimeKey = '';
      _activeRouteDirectionKey = '';
    }
  }

  List<Map<String, dynamic>> _normalizeForViewAll(
    List<Map<String, dynamic>> alerts,
    String assignedBus,
  ) {
    const trackedBookingIds = {
      '0OhBkgEAYh35UgwtMXU3',
      'q1MWmuqcMNKKns4wtFwl',
    };

    final sorted = List<Map<String, dynamic>>.from(alerts)
      ..sort((a, b) => ((b['receivedAtMs'] as int?) ?? 0)
          .compareTo((a['receivedAtMs'] as int?) ?? 0));

    final latestByBooking = <String, Map<String, dynamic>>{};
    final withoutBookingId = <Map<String, dynamic>>[];

    for (final item in sorted) {
      final bookingId = (item['bookingId'] ?? '').toString().trim();
      if (bookingId.isNotEmpty) {
        latestByBooking.putIfAbsent(bookingId, () => item);
      } else {
        withoutBookingId.add(item);
      }
    }

    final result = <Map<String, dynamic>>[];

    bool shouldLogBooking(Map<String, dynamic> item) {
      final bookingId = (item['bookingId'] ?? '').toString().trim();
      return trackedBookingIds.contains(bookingId);
    }

    void logBookingDecision(Map<String, dynamic> item, String decision,
        {String details = ''}) {
      if (!shouldLogBooking(item)) return;
      final bookingId = (item['bookingId'] ?? '').toString().trim();
      final status = (item['status'] ?? '').toString().trim().toLowerCase();
      final origin = (item['origin'] ?? '').toString().trim();
      final destination = (item['destination'] ?? '').toString().trim();
      final itemScheduleKey = _extractAlertScheduleKey(item);
      final activeScheduleKey = _activeScheduleTimeKey;
      final activeDirection = (_activeRouteDirectionKey.isNotEmpty
              ? _activeRouteDirectionKey
              : (widget.routeDirection ?? ''))
          .trim()
          .toLowerCase();
      debugPrint(
        '[BookingFilter][ViewAll] bookingId=$bookingId decision=$decision '
        'status=$status activeDir=$activeDirection origin="$origin" '
        'destination="$destination" activeSchedule="$activeScheduleKey" '
        'itemSchedule="$itemScheduleKey" $details',
      );
    }

    String? routeRejectReason(Map<String, dynamic> item) {
      final activeDirection = (_activeRouteDirectionKey.isNotEmpty
              ? _activeRouteDirectionKey
              : (widget.routeDirection ?? ''))
          .trim()
          .toLowerCase();
      if (activeDirection.isEmpty) return 'missing_active_direction';

      final originRaw =
          (item['origin'] ?? item['from'] ?? item['fromLocation'] ?? '')
              .toString()
              .trim();
      final destinationRaw =
          (item['destination'] ?? item['to'] ?? item['toLocation'] ?? '')
              .toString()
              .trim();

      if (originRaw.isNotEmpty && destinationRaw.isNotEmpty) {
        final stationList =
            route_validator.RouteValidator.getStationListForDirection(
                activeDirection);
        final origin = QRValidationService.resolveStationName(originRaw);
        final destination =
            QRValidationService.resolveStationName(destinationRaw);
        final originIndex = route_validator.RouteValidator.findStationIndex(
            origin, stationList);
        final destinationIndex =
            route_validator.RouteValidator.findStationIndex(
                destination, stationList);

        if (originIndex >= 0 && destinationIndex >= 0) {
          if (originIndex < destinationIndex) return null;
          return 'route_station_order_mismatch';
        }
      }

      final itemDirection = _deriveRouteDirectionFromText(
        (item['busRoute'] ?? item['routeName'] ?? item['route'] ?? '')
            .toString(),
      );
      if (itemDirection.isNotEmpty) {
        if (itemDirection == activeDirection) return null;
        return 'route_direction_mismatch';
      }

      return 'route_unresolved';
    }

    bool activeStatus(Map<String, dynamic> item) {
      final status = (item['status'] ?? '').toString().trim().toLowerCase();
      return status == 'waiting' || status == 'on-board';
    }

    for (final item in latestByBooking.values) {
      if (!activeStatus(item)) {
        logBookingDecision(item, 'reject', details: 'reason=not_active_status');
        continue;
      }
      final routeReason = routeRejectReason(item);
      if (routeReason != null) {
        logBookingDecision(item, 'reject', details: 'reason=$routeReason');
        continue;
      }
      logBookingDecision(item, 'accept');
      result.add(item);
    }

    for (final item in withoutBookingId) {
      if (!activeStatus(item)) {
        logBookingDecision(item, 'reject', details: 'reason=not_active_status');
        continue;
      }
      final routeReason = routeRejectReason(item);
      if (routeReason != null) {
        logBookingDecision(item, 'reject', details: 'reason=$routeReason');
        continue;
      }
      logBookingDecision(item, 'accept');
      result.add(item);
    }

    int statusOrder(Map<String, dynamic> item) {
      final status = (item['status'] ?? '').toString().trim().toLowerCase();
      return status == 'waiting' ? 0 : 1;
    }

    result.sort((a, b) {
      final cmp = statusOrder(a).compareTo(statusOrder(b));
      if (cmp != 0) return cmp;
      return ((b['receivedAtMs'] as int?) ?? 0)
          .compareTo((a['receivedAtMs'] as int?) ?? 0);
    });

    return result;
  }

  String _extractAlertScheduleKey(Map<String, dynamic> item) {
    return _normalizeScheduleKey(
      (item['ScheduledTimeStr'] ??
          item['scheduledTimeStr'] ??
          item['ScheduleTime'] ??
          item['ScheduleTIme'] ??
          item['scheduleTime'] ??
          item['scheduledTime'] ??
          item['scheduledTimeSTR']),
    );
  }

  String _deriveRouteDirectionFromText(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return '';

    if (text.contains('nasugbu') && text.contains('batangas')) {
      final nasugbuIdx = text.indexOf('nasugbu');
      final batangasIdx = text.indexOf('batangas');
      if (nasugbuIdx < batangasIdx) return 'north_to_south';
      if (batangasIdx < nasugbuIdx) return 'south_to_north';
    }

    if (text.contains('north_to_south') || text.contains('north to south')) {
      return 'north_to_south';
    }
    if (text.contains('south_to_north') || text.contains('south to north')) {
      return 'south_to_north';
    }

    return '';
  }

  String _normalizeScheduleKey(dynamic raw) {
    if (raw == null) return '';

    if (raw is Timestamp) {
      return _formatScheduleMinuteKey(raw.toDate());
    }

    if (raw is DateTime) {
      return _formatScheduleMinuteKey(raw);
    }

    final text = raw.toString().trim();
    if (text.isEmpty) return '';

    final asDate = DateTime.tryParse(text) ??
        DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (asDate != null) {
      return _formatScheduleMinuteKey(asDate);
    }

    return text.toLowerCase();
  }

  String _formatScheduleMinuteKey(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Alerts'),
        backgroundColor: Colors.green[700],
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
                final status =
                    (item['status'] ?? 'waiting').toString().toLowerCase();
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
                      Text('Status: $status'),
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
