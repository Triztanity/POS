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
  Timer? _reconcileTimer;
  final StreamController<Map<String, dynamic>> _alertsController =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _firebaseStarted = false;
  String _assignedBus = '';

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
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
    _assignedBus = '';
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
      _assignedBus = assignedBus;

      final fs = FirebaseFirestore.instance;

      _bookingsNewSub = fs
          .collection('bookings_new')
          .where('busNumber', isEqualTo: assignedBus)
          .snapshots()
          .listen(
        (snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.removed) {
              await _removeBookingFromAlerts(change.doc.id);
              continue;
            }
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
            if (change.type == DocumentChangeType.removed) {
              await _removeBookingFromAlerts(change.doc.id);
              continue;
            }
            await _ingestFirebaseDoc(change.doc, sourceCollection: 'bookings');
          }
        },
        onError: (e) {
          debugPrint('[SMS ALERT] bookings stream error: $e');
        },
      );

      await _reconcileAgainstLiveBookings();
      _reconcileTimer?.cancel();
      _reconcileTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        await _reconcileAgainstLiveBookings();
      });
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
      final bookingId = doc.id.trim();
      if (bookingId.isEmpty) return;

      if (status == 'dropped-off' || status == 'expired') {
        await _removeBookingFromAlerts(bookingId);
        return;
      }

      if (status != 'waiting' && status != 'on-board') {
        return;
      }

      final origin =
          (data['origin'] ?? data['pickup'] ?? data['fromLocation'] ?? '')
              .toString()
              .trim();
      final destination =
          (data['destination'] ?? data['dropoff'] ?? data['toLocation'] ?? '')
              .toString()
              .trim();
      final seats = _parseSeats(data);
      final receivedAtMs = _timestampToMs(
        data['updatedAt'] ?? data['createdAt'] ?? data['movedAt'],
      );

      final alert = <String, dynamic>{
        'type': status == 'waiting' ? 'booking.alert' : 'booking.status',
        'status': status,
        'bookingId': bookingId,
        'origin': origin,
        'destination': destination,
        'seats': seats,
        'station': (data['station'] ?? '').toString(),
        'busNumber': (data['busNumber'] ?? '').toString(),
        'busRoute':
            (data['busRoute'] ?? data['route'] ?? data['routeName'] ?? '')
                .toString(),
        'tripId': (data['tripId'] ?? '').toString(),
        'scheduledTimeStr': _normalizeScheduleKey(
          data['scheduledTimeStr'] ??
              data['ScheduleTime'] ??
              data['scheduleTime'] ??
              data['scheduledTime'] ??
              data['scheduledTimeSTR'],
        ),
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

  Future<void> _removeBookingFromAlerts(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return;

    final box = await _openBox();
    final existingRaw = box.get(_alertsKey) ?? [];
    final existing = existingRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();

    final before = existing.length;
    existing.removeWhere((a) =>
        (a['bookingId'] ?? '').toString().trim().toLowerCase() ==
        id.toLowerCase());

    if (existing.length != before) {
      await box.put(_alertsKey, existing);
      _alertsController.add({
        'type': 'booking.removed',
        'bookingId': id,
        'source': 'firebase',
        'receivedAtMs': DateTime.now().millisecondsSinceEpoch,
        'receivedAtIso': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> _reconcileAgainstLiveBookings() async {
    if (_assignedBus.isEmpty) return;

    try {
      final fs = FirebaseFirestore.instance;
      final liveStatusByBookingId = <String, String>{};

      final newSnap = await fs
          .collection('bookings_new')
          .where('busNumber', isEqualTo: _assignedBus)
          .get();
      for (final d in newSnap.docs) {
        final status =
            (d.data()['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'waiting' || status == 'on-board') {
          liveStatusByBookingId[d.id.trim()] = status;
        }
      }

      final activeSnap = await fs
          .collection('bookings')
          .where('busNumber', isEqualTo: _assignedBus)
          .get();
      for (final d in activeSnap.docs) {
        final status =
            (d.data()['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'waiting' || status == 'on-board') {
          liveStatusByBookingId[d.id.trim()] = status;
        }
      }

      final box = await _openBox();
      final existingRaw = box.get(_alertsKey) ?? [];
      final existing = existingRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();

      final filtered = <Map<String, dynamic>>[];
      for (final item in existing) {
        final bookingId = (item['bookingId'] ?? '').toString().trim();
        if (bookingId.isEmpty) {
          // Keep legacy alerts without booking ids if they still look active.
          final status = (item['status'] ?? '').toString().trim().toLowerCase();
          if (status.isEmpty || status == 'waiting' || status == 'on-board') {
            filtered.add(item);
          }
          continue;
        }

        final liveStatus = liveStatusByBookingId[bookingId];
        if (liveStatus != null) {
          item['status'] = liveStatus;
          filtered.add(item);
          continue;
        }

        // Keep SMS-only bookings during fallback mode; they may not exist in
        // Firestore briefly until the live state arrives or sync updates.
        final source = (item['source'] ?? '').toString().toLowerCase();
        final status = (item['status'] ?? '').toString().trim().toLowerCase();
        if (source == 'sms' && (status == 'waiting' || status == 'on-board')) {
          filtered.add(item);
          continue;
        }
      }

      if (filtered.length != existing.length) {
        await box.put(_alertsKey, filtered);
        _alertsController.add({
          'type': 'booking.reconciled',
          'source': 'firebase',
          'receivedAtMs': DateTime.now().millisecondsSinceEpoch,
          'receivedAtIso': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('[SMS ALERT] reconcile error: $e');
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
      final destination =
          (map['destination'] ?? map['to'] ?? map['toLocation'] ?? '')
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
        'destination': destination,
        'seats': seats ?? 0,
        'station': (map['station'] ?? '').toString(),
        'busNumber': (map['busNumber'] ?? '').toString(),
        'busRoute': (map['busRoute'] ?? map['route'] ?? map['routeName'] ?? '')
            .toString(),
        'tripId': (map['tripId'] ?? '').toString(),
        'scheduledTimeStr': _normalizeScheduleKey(
          map['scheduledTimeStr'] ??
              map['ScheduleTime'] ??
              map['scheduleTime'] ??
              map['scheduledTime'] ??
              map['scheduledTimeSTR'],
        ),
        'eventId': (map['eventId'] ?? '').toString(),
        'updatedAt': (map['updatedAt'] ?? '').toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _tryParseKeyValue(String body) {
    var normalized = body
        .replaceAll('\r', ' ')
        .replaceAll('\n', '|')
        .replaceAll(';', '|')
        .replaceAll(',', '|')
        .replaceAll('[', '')
        .replaceAll(']', '');

    const bookingPrefix = 'BOOKING';
    if (normalized.toUpperCase().startsWith(bookingPrefix)) {
      final suffix = normalized.substring(bookingPrefix.length);
      if (suffix.isNotEmpty && !suffix.startsWith('|')) {
        normalized = '$bookingPrefix|$suffix';
      }
    }

    final parts = normalized.split('|').map((e) => e.trim()).toList();
    if (parts.isEmpty) return null;

    if (!parts.first.toUpperCase().contains('BOOKING')) {
      return null;
    }

    final values = <String, String>{};
    const keyAliases = {
      'i': 'bookingid',
      'o': 'origin',
      'd': 'destination',
      's': 'seats',
      'x': 'status',
      'b': 'busnumber',
      't': 'tripid',
      'r': 'busroute',
    };

    for (final p in parts) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      var key = p.substring(0, idx).trim().toLowerCase();
      final value = p.substring(idx + 1).trim();
      key = keyAliases[key] ?? key;
      values[key] = value;
    }

    final bookingId =
        values['bookingid'] ?? values['booking_id'] ?? values['id'] ?? '';
    final origin =
        values['origin'] ?? values['from'] ?? values['fromlocation'] ?? '';
    final destination =
        values['destination'] ?? values['to'] ?? values['tolocation'] ?? '';
    final seats = int.tryParse(
      values['seats'] ?? values['qty'] ?? values['passengers'] ?? '',
    );

    final type = (values['type'] ?? 'booking.alert').toString().toLowerCase();
    final status = (values['status'] ?? '').toString().toLowerCase();
    final isStatusMessage = type == 'booking.status' || status.isNotEmpty;

    if (bookingId.isEmpty) return null;
    if (!isStatusMessage && (origin.isEmpty || seats == null)) return null;

    return {
      'type': type,
      'status': status,
      'bookingId': bookingId,
      'origin': origin,
      'destination': destination,
      'seats': seats ?? 0,
      'station': values['station'] ?? '',
      'busNumber': values['busnumber'] ?? '',
      'busRoute':
          values['busroute'] ?? values['route'] ?? values['routename'] ?? '',
      'tripId': values['tripid'] ?? values['trip'] ?? '',
      'scheduledTimeStr': _normalizeScheduleKey(
        values['scheduledtimestr'] ??
            values['scheduletime'] ??
            values['scheduledtime'] ??
            values['scheduled_time'] ??
            '',
      ),
      'scheduleTime': _normalizeScheduleKey(
        values['scheduletime'] ??
            values['scheduledtime'] ??
            values['scheduled_time'] ??
            '',
      ),
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
    final destinationMatch =
        RegExp(r'(?:destination|to)\s*[:=]\s*([^,|;]+)', caseSensitive: false)
            .firstMatch(body);
    final destination = destinationMatch?.group(1)?.trim() ?? '';

    if (origin.isEmpty || seats == null) return null;

    return {
      'bookingId': bookingId,
      'origin': origin,
      'destination': destination,
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

    final bookingId = (alert['bookingId'] ?? '').toString().trim();
    if (bookingId.isNotEmpty) {
      // Keep one latest active alert per booking across status transitions.
      existing.removeWhere((a) =>
          (a['bookingId'] ?? '').toString().trim().toLowerCase() ==
          bookingId.toLowerCase());
      existing.add(alert);
      existing.sort((a, b) =>
          (b['receivedAtMs'] as int).compareTo((a['receivedAtMs'] as int)));
      await box.put(_alertsKey, existing);
      return;
    }

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
    final scheduledTimeKey = (alert['scheduledTimeStr'] ??
            alert['ScheduleTime'] ??
            alert['scheduleTime'] ??
            alert['scheduledTime'] ??
            alert['scheduledTimeSTR'] ??
            '')
        .toString()
        .trim();
    final origin = (alert['origin'] ?? '').toString().trim().toLowerCase();
    final seats = (alert['seats'] ?? '').toString().trim();

    if (bookingId.isNotEmpty) {
      return 'booking:$bookingId|status:$status|trip:$tripId|schedule:$scheduledTimeKey';
    }

    return 'origin:$origin|seats:$seats|status:$status|schedule:$scheduledTimeKey';
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

    final parsed = DateTime.tryParse(text) ??
        DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (parsed != null) {
      return _formatScheduleMinuteKey(parsed);
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
}
