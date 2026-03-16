import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'device_config_service.dart';

class PiGatewayService {
  static final PiGatewayService _instance = PiGatewayService._internal();

  factory PiGatewayService() => _instance;

  PiGatewayService._internal();

  static const _boxName = 'pi_gateway_outbox';
  static const _eventsKey = 'events';
  static const _defaultBaseUrl = 'http://192.168.4.2:5000';
  static const _eventsEndpoint = '/api/pos/events';

  Future<Box<List>> _openBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return Hive.openBox<List>(_boxName);
    }
    return Hive.box<List>(_boxName);
  }

  Future<List<Map<String, dynamic>>> _loadEvents() async {
    final box = await _openBox();
    final raw = box.get(_eventsKey) ?? [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> _saveEvents(List<Map<String, dynamic>> events) async {
    final box = await _openBox();
    await box.put(
      _eventsKey,
      events.map((e) => Map<String, dynamic>.from(e)).toList(),
    );
  }

  Future<String> _getBaseUrl() async {
    final configured = await DeviceConfigService.getPiGatewayBaseUrl();
    final trimmed = configured?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed.endsWith('/')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
    }
    return _defaultBaseUrl;
  }

  String _eventId(String prefix) {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$ms-$micros';
  }

  Future<void> _enqueue(Map<String, dynamic> event) async {
    final events = await _loadEvents();
    events.add(event);
    await _saveEvents(events);
  }

  Future<Map<String, dynamic>> _deliverEvent(Map<String, dynamic> event) async {
    final baseUrl = await _getBaseUrl();
    final uri = Uri.parse('$baseUrl$_eventsEndpoint');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(event),
        )
        .timeout(const Duration(seconds: 8));

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    return {
      'ok': ok,
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }

  Future<Map<String, dynamic>> queueAndSend({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final event = <String, dynamic>{
      'eventId': _eventId(type),
      'type': type,
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
      'retries': 0,
    };
    await _enqueue(event);
    return flushPending(maxItems: 25);
  }

  Future<Map<String, dynamic>> sendDispatchStatus({
    required String tripId,
    required String busNumber,
    required String dispatcherUid,
    required String status,
    String? routeId,
    String? routeName,
  }) async {
    return queueAndSend(
      type: 'dispatch.status',
      payload: {
        'tripId': tripId,
        'busNumber': busNumber,
        'dispatcherUid': dispatcherUid,
        'status': status,
        'routeId': routeId,
        'routeName': routeName,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> sendBookingStatus({
    required String bookingId,
    required String tripId,
    required String status,
    String? passengerUid,
    String? dropoffTimestamp,
  }) async {
    return queueAndSend(
      type: 'booking.status',
      payload: {
        'bookingId': bookingId,
        'tripId': tripId,
        'status': status,
        'passengerUid': passengerUid,
        'dropoffTimestamp': dropoffTimestamp,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> flushPending({int maxItems = 50}) async {
    final events = await _loadEvents();
    if (events.isEmpty) {
      return {'attempted': 0, 'sent': 0, 'remaining': 0};
    }

    final updated = List<Map<String, dynamic>>.from(events);
    var attempted = 0;
    var sent = 0;

    for (var i = 0; i < updated.length && attempted < maxItems; i++) {
      final event = Map<String, dynamic>.from(updated[i]);
      attempted++;
      try {
        final result = await _deliverEvent(event);
        if (result['ok'] == true) {
          updated[i]['_delete'] = true;
          sent++;
          continue;
        }
        updated[i]['retries'] = ((event['retries'] ?? 0) as int) + 1;
        updated[i]['lastError'] =
            'HTTP ${result['statusCode']}: ${result['body'] ?? ''}';
      } catch (e) {
        updated[i]['retries'] = ((event['retries'] ?? 0) as int) + 1;
        updated[i]['lastError'] = e.toString();
      }
    }

    final remainingEvents = updated.where((e) => e['_delete'] != true).map((e) {
      final cleaned = Map<String, dynamic>.from(e);
      cleaned.remove('_delete');
      return cleaned;
    }).toList();

    await _saveEvents(remainingEvents);

    debugPrint(
      '[PiGateway] flush attempted=$attempted sent=$sent remaining=${remainingEvents.length}',
    );

    return {
      'attempted': attempted,
      'sent': sent,
      'remaining': remainingEvents.length,
    };
  }
}
