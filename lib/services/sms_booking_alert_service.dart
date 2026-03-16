import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsBookingAlertService {
  SmsBookingAlertService._internal();

  static final SmsBookingAlertService _instance =
      SmsBookingAlertService._internal();

  factory SmsBookingAlertService() => _instance;

  static const _channel = EventChannel('com.example.untitled/sms_alerts');
  static const _boxName = 'sms_booking_alerts';
  static const _alertsKey = 'items';

  StreamSubscription<dynamic>? _subscription;
  final StreamController<Map<String, dynamic>> _alertsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get alertsStream => _alertsController.stream;

  Future<Box<List>> _openBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return Hive.openBox<List>(_boxName);
    }
    return Hive.box<List>(_boxName);
  }

  Future<void> startListening() async {
    if (_subscription != null) return;

    final status = await Permission.sms.request();
    if (!status.isGranted) {
      debugPrint('[SMS ALERT] SMS permission denied');
      return;
    }

    _subscription = _channel.receiveBroadcastStream().listen(
      (raw) async => _handleIncoming(raw),
      onError: (e) {
        debugPrint('[SMS ALERT] stream error: $e');
      },
      cancelOnError: false,
    );
  }

  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handleIncoming(dynamic raw) async {
    try {
      if (raw is! Map) return;

      final sms = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      final sender = sms['sender']?.toString() ?? '';
      final body = sms['body']?.toString() ?? '';
      final timestampRaw = sms['timestamp'];
      final timestamp = timestampRaw is int
          ? timestampRaw
          : int.tryParse(timestampRaw?.toString() ?? '') ??
              DateTime.now().millisecondsSinceEpoch;

      final parsed = _parseBookingAlert(body);
      if (parsed == null) {
        return;
      }

      final alert = {
        ...parsed,
        'sender': sender,
        'body': body,
        'receivedAtMs': timestamp,
        'receivedAtIso':
            DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String(),
      };

      await _saveAlert(alert);
      _alertsController.add(alert);
    } catch (e) {
      debugPrint('[SMS ALERT] parse/store error: $e');
    }
  }

  Map<String, dynamic>? _parseBookingAlert(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;

    final jsonParsed = _tryParseJson(trimmed);
    if (jsonParsed != null) {
      return jsonParsed;
    }

    final kvParsed = _tryParseKeyValue(trimmed);
    if (kvParsed != null) {
      return kvParsed;
    }

    return _tryParseRegexFallback(trimmed);
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      if (!(body.startsWith('{') && body.endsWith('}'))) {
        return null;
      }
      final dynamic decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded.cast<String, dynamic>());

      final type = (map['type'] ?? '').toString().trim().toLowerCase();
      final status = (map['status'] ?? '').toString().trim().toLowerCase();

      final bookingId =
          (map['bookingId'] ?? map['booking_id'] ?? map['id'] ?? '').toString();
      final origin = (map['origin'] ?? map['from'] ?? map['fromLocation'] ?? '')
          .toString();
      final seatsRaw = (map['seats'] ??
              map['qty'] ??
              map['numberOfPassengers'] ??
              map['passengers'])
          ?.toString();
      final seats = int.tryParse(seatsRaw ?? '');

      // booking.status messages may omit origin/seats; still ingest to allow
      // downstream UI to remove waiting entries for the same booking.
      final isStatusMessage = type == 'booking.status';

      if (!isStatusMessage && (origin.isEmpty || seats == null)) return null;
      if (isStatusMessage && bookingId.isEmpty) return null;

      return {
        'type': type,
        'status': status,
        'bookingId': bookingId,
        'origin': origin,
        'seats': seats ?? 0,
        'station': (map['station'] ?? '').toString(),
        'busNumber': (map['busNumber'] ?? '').toString(),
        'tripId': (map['tripId'] ?? '').toString(),
        'eventId': (map['eventId'] ?? '').toString(),
        'updatedAt': (map['updatedAt'] ?? '').toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _tryParseKeyValue(String body) {
    final normalized = body.replaceAll('\n', '|').replaceAll(';', '|');
    final parts = normalized.split('|').map((e) => e.trim()).toList();
    if (parts.isEmpty) return null;

    if (!parts.first.toUpperCase().contains('BOOKING')) {
      return null;
    }

    final values = <String, String>{};
    for (final p in parts) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      final key = p.substring(0, idx).trim().toLowerCase();
      final value = p.substring(idx + 1).trim();
      values[key] = value;
    }

    final bookingId =
        values['bookingid'] ?? values['booking_id'] ?? values['id'] ?? '';
    final origin =
        values['origin'] ?? values['from'] ?? values['fromlocation'] ?? '';
    final seats = int.tryParse(
      values['seats'] ?? values['qty'] ?? values['passengers'] ?? '',
    );

    if (origin.isEmpty || seats == null) return null;

    return {
      'bookingId': bookingId,
      'origin': origin,
      'seats': seats,
    };
  }

  Map<String, dynamic>? _tryParseRegexFallback(String body) {
    final originMatch =
        RegExp(r'(?:origin|from)\s*[:=]\s*([^,|;]+)', caseSensitive: false)
            .firstMatch(body);
    final seatsMatch = RegExp(
      r'(?:seats|qty|passengers|numberOfPassengers)\s*[:=]\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(body);
    final bookingMatch = RegExp(
            r'(?:bookingId|booking_id|id)\s*[:=]\s*([A-Za-z0-9_-]+)',
            caseSensitive: false)
        .firstMatch(body);

    final origin = originMatch?.group(1)?.trim() ?? '';
    final seats = int.tryParse(seatsMatch?.group(1) ?? '');
    final bookingId = bookingMatch?.group(1)?.trim() ?? '';

    if (origin.isEmpty || seats == null) return null;

    return {
      'bookingId': bookingId,
      'origin': origin,
      'seats': seats,
    };
  }

  Future<void> _saveAlert(Map<String, dynamic> alert) async {
    final box = await _openBox();
    final existingRaw = box.get(_alertsKey) ?? [];
    final existing = existingRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();

    final dedupeKey =
        '${alert['bookingId']}-${alert['origin']}-${alert['seats']}-${alert['receivedAtMs']}';
    final alreadyExists = existing.any((a) {
      final key =
          '${a['bookingId']}-${a['origin']}-${a['seats']}-${a['receivedAtMs']}';
      return key == dedupeKey;
    });
    if (alreadyExists) return;

    existing.add(alert);
    existing.sort((a, b) =>
        (b['receivedAtMs'] as int).compareTo((a['receivedAtMs'] as int)));

    await box.put(_alertsKey, existing);
  }

  Future<List<Map<String, dynamic>>> getStoredAlerts() async {
    final box = await _openBox();
    final raw = box.get(_alertsKey) ?? [];
    final items = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();
    items.sort((a, b) =>
        (b['receivedAtMs'] as int).compareTo((a['receivedAtMs'] as int)));
    return items;
  }

  Future<void> clearAll() async {
    final box = await _openBox();
    await box.put(_alertsKey, <Map<String, dynamic>>[]);
  }
}
