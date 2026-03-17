import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_config_service.dart';

class SmsBookingAlertService {
  SmsBookingAlertService._internal();

  static final SmsBookingAlertService _instance =
      SmsBookingAlertService._internal();

  factory SmsBookingAlertService() => _instance;

  static const _channel = EventChannel('com.example.untitled/sms_alerts');
  static const _boxName = 'sms_booking_alerts';
  static const _alertsKey = 'items';

  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bookingsNewSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bookingsSub;
  final StreamController<Map<String, dynamic>> _alertsController =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _firebaseStarted = false;

  Stream<Map<String, dynamic>> get alertsStream => _alertsController.stream;

  Future<Box<List>> _openBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return Hive.openBox<List>(_boxName);
    }
    return Hive.box<List>(_boxName);
  }

  Future<void> startListening() async {
    if (_subscription == null) {
      final status = await Permission.sms.request();
      if (!status.isGranted) {
        debugPrint('[SMS ALERT] SMS permission denied');
      } else {
        _subscription = _channel.receiveBroadcastStream().listen(
          (raw) async => _handleIncoming(raw),
          onError: (e) {
            debugPrint('[SMS ALERT] stream error: $e');
          },
          cancelOnError: false,
        );
      }
    }

    await _startFirebaseBookingSync();
  }

  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    await _bookingsNewSub?.cancel();
    _bookingsNewSub = null;
    await _bookingsSub?.cancel();
    _bookingsSub = null;
    _firebaseStarted = false;
  }

  Future<void> _startFirebaseBookingSync() async {
    if (_firebaseStarted) return;
    _firebaseStarted = true;

    try {
      final assignedBus = (await DeviceConfigService.getAssignedBus() ?? '')
          .trim()
          .toUpperCase();
      if (assignedBus.isEmpty) {
        debugPrint(
            '[SMS ALERT] Firebase booking sync skipped: no assigned bus');
        return;
      }

      final fs = FirebaseFirestore.instance;

      _bookingsNewSub = fs
          .collection('bookings_new')
          .where('busNumber', isEqualTo: assignedBus)
          .snapshots()
          .listen(
        (snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.removed) continue;
            await _ingestFirebaseDoc(change.doc,
                sourceCollection: 'bookings_new');
          }
        },
        onError: (e) {
          debugPrint('[SMS ALERT] bookings_new stream error: $e');
        },
      );

      _bookingsSub = fs
          .collection('bookings')
          .where('busNumber', isEqualTo: assignedBus)
          .snapshots()
          .listen(
        (snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.removed) continue;
            await _ingestFirebaseDoc(change.doc, sourceCollection: 'bookings');
          }
        },
        onError: (e) {
          debugPrint('[SMS ALERT] bookings stream error: $e');
        },
      );
    } catch (e) {
      _firebaseStarted = false;
      debugPrint('[SMS ALERT] Firebase booking sync setup error: $e');
    }
  }

  Future<void> _ingestFirebaseDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String sourceCollection,
  }) async {
    try {
      final data = doc.data();
      if (data == null) return;
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      if (status.isEmpty) return;

      final origin =
          (data['origin'] ?? data['pickup'] ?? data['fromLocation'] ?? '')
              .toString()
              .trim();
      final seats = _parseSeats(data);
      final bookingId = doc.id;
      final receivedAtMs = _timestampToMs(
        data['updatedAt'] ?? data['createdAt'] ?? data['movedAt'],
      );

      final alert = <String, dynamic>{
        'type': status == 'waiting' ? 'booking.alert' : 'booking.status',
        'status': status,
        'bookingId': bookingId,
        'origin': origin,
        'seats': seats,
        'station': (data['station'] ?? '').toString(),
        'busNumber': (data['busNumber'] ?? '').toString(),
        'tripId': (data['tripId'] ?? '').toString(),
        'eventId':
            (data['lastStatusEventId'] ?? data['gatewayLastAlertEventId'] ?? '')
                .toString(),
        'updatedAt': _timestampToIso(
          data['updatedAt'] ?? data['createdAt'] ?? data['movedAt'],
        ),
        'sender': 'firebase:$sourceCollection',
        'body': '',
        'source': 'firebase',
        'sourceCollection': sourceCollection,
        'receivedAtMs': receivedAtMs,
        'receivedAtIso':
            DateTime.fromMillisecondsSinceEpoch(receivedAtMs).toIso8601String(),
      };

      if (status != 'waiting' && bookingId.isEmpty) return;
      if (status == 'waiting' && (origin.isEmpty || seats <= 0)) return;

      await _saveAlert(alert);
      _alertsController.add(alert);
    } catch (e) {
      debugPrint('[SMS ALERT] Firebase ingest error: $e');
    }
  }

  int _parseSeats(Map<String, dynamic> data) {
    final raw = data['seats'] ??
        data['qty'] ??
        data['numberOfPassengers'] ??
        data['passengers'];
    if (raw is int) return raw;
    if (raw is List) return raw.length;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  int _timestampToMs(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return asInt;
      final dt = DateTime.tryParse(value);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  String _timestampToIso(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toIso8601String();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return DateTime.now().toIso8601String();
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

      debugPrint('[SMS ALERT] received from=$sender body="$body"');

      final parsed = _parseBookingAlert(body);
      if (parsed == null) {
        debugPrint(
            '[SMS ALERT] ignored: unable to parse booking alert payload');
        return;
      }

      final alert = {
        ...parsed,
        'sender': sender,
        'body': body,
        'source': 'sms',
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
      final normalized =
          body.replaceAll('“', '"').replaceAll('”', '"').replaceAll('’', "'");

      final start = normalized.indexOf('{');
      final end = normalized.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) {
        return null;
      }

      final jsonText = normalized.substring(start, end + 1);
      final dynamic decoded = jsonDecode(jsonText);
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

    final dedupeId = _buildDedupeId(alert);
    final semanticId = _buildSemanticId(alert);
    final receivedAt = (alert['receivedAtMs'] as int?) ?? 0;

    final idx = existing.indexWhere((a) {
      final sameDedupe = _buildDedupeId(a) == dedupeId;
      final sameSemantic = _buildSemanticId(a) == semanticId;
      return sameDedupe || sameSemantic;
    });

    if (idx >= 0) {
      final prevMs = (existing[idx]['receivedAtMs'] as int?) ?? 0;
      if (receivedAt >= prevMs) {
        existing[idx] = {
          ...existing[idx],
          ...alert,
        };
      }
    } else {
      existing.add(alert);
    }

    existing.sort((a, b) =>
        (b['receivedAtMs'] as int).compareTo((a['receivedAtMs'] as int)));

    await box.put(_alertsKey, existing);
  }

  String _buildDedupeId(Map<String, dynamic> alert) {
    final eventId = (alert['eventId'] ?? '').toString().trim();
    final bookingId = (alert['bookingId'] ?? '').toString().trim();
    if (eventId.isNotEmpty) {
      return 'event:$eventId|booking:$bookingId';
    }
    return _buildSemanticId(alert);
  }

  String _buildSemanticId(Map<String, dynamic> alert) {
    final bookingId = (alert['bookingId'] ?? '').toString().trim();
    final status = (alert['status'] ?? '').toString().trim().toLowerCase();
    final tripId = (alert['tripId'] ?? '').toString().trim();
    final origin = (alert['origin'] ?? '').toString().trim().toLowerCase();
    final seats = (alert['seats'] ?? '').toString().trim();

    if (bookingId.isNotEmpty) {
      return 'booking:$bookingId|status:$status|trip:$tripId';
    }

    return 'origin:$origin|seats:$seats|status:$status';
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
