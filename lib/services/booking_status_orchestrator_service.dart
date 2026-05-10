import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'sms_status_sender_service.dart';

class BookingStatusOrchestratorService {
  BookingStatusOrchestratorService._internal();

  static final BookingStatusOrchestratorService _instance =
      BookingStatusOrchestratorService._internal();

  factory BookingStatusOrchestratorService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();
  final SmsStatusSenderService _smsSender = SmsStatusSenderService();

  static const String _queueBoxName = 'booking_status_pending';
  static const String _queueKey = 'items';
  static const int _smsFallbackDelayMs =
      15000; // faster fallback for offline signal

  StreamSubscription<ConnectivityResult>? _connectivitySub;
  Timer? _flushTimer;
  bool _initialized = false;
  bool _isFlushing = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _openQueueBox();

    _connectivitySub = _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        flushPending();
      }
    });

    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      flushPending();
    });

    unawaited(flushPending());
  }

  void dispose() {
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _initialized = false;
  }

  Future<Map<String, dynamic>> updateStatus({
    required String bookingId,
    required String tripId,
    required String status,
    String? passengerUid,
    String? dropoffTimestamp,
  }) async {
    await initialize();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final eventId = 'bs-$bookingId-$status-$nowMs';

    final payload = <String, dynamic>{
      'eventId': eventId,
      'bookingId': bookingId,
      'tripId': tripId,
      'status': status,
      'passengerUid': passengerUid ?? '',
      'dropoffTimestamp': dropoffTimestamp ?? '',
      'createdAtMs': nowMs,
    };

    final online = await _isOnline();
    if (online) {
      final ok = await _applyFirestoreUpdate(payload);
      if (ok) {
        return {
          'success': true,
          'channel': 'firebase',
          'queued': false,
          'eventId': eventId,
        };
      }
    }

    await _enqueuePending(payload);
    return {
      'success': true,
      'channel': 'queued',
      'queued': true,
      'eventId': eventId,
      'message': 'Queued for retry; SMS fallback after timeout if needed.',
    };
  }

  Future<void> flushPending() async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      final items = await _loadQueue();
      if (items.isEmpty) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final kept = <Map<String, dynamic>>[];

      for (final item in items) {
        final payload = Map<String, dynamic>.from(
          (item['payload'] as Map).cast<String, dynamic>(),
        );

        bool done = false;
        final online = await _isOnline();

        if (online) {
          final ok = await _applyFirestoreUpdate(payload);
          if (ok) {
            done = true;
            debugPrint(
                '[BookingStatus] Synced queued event ${payload['eventId']} via Firebase');
          }
        }

        if (!done) {
          final queuedAt = (item['queuedAtMs'] as int?) ?? now;
          final smsSent = item['smsSent'] == true;
          final canFallback = now - queuedAt >= _smsFallbackDelayMs;

          if (canFallback && !smsSent) {
            final smsResult = await _smsSender.sendBookingStatusSms(
              bookingId: (payload['bookingId'] ?? '').toString(),
              tripId: (payload['tripId'] ?? '').toString(),
              status: (payload['status'] ?? '').toString(),
              passengerUid: _emptyToNull(payload['passengerUid']),
              dropoffTimestamp: _emptyToNull(payload['dropoffTimestamp']),
              eventId: (payload['eventId'] ?? '').toString(),
            );

            if (smsResult['success'] == true) {
              done = true;
              debugPrint(
                  '[BookingStatus] Sent SMS fallback for ${payload['eventId']}');
            } else {
              item['smsSent'] = true;
              item['lastError'] =
                  'SMS fallback failed: ${smsResult['message'] ?? 'unknown'}';
            }
          }
        }

        if (!done) {
          item['attempts'] = ((item['attempts'] ?? 0) as int) + 1;
          kept.add(item);
        }
      }

      await _saveQueue(kept);
    } catch (e) {
      debugPrint('[BookingStatus] flushPending error: $e');
    } finally {
      _isFlushing = false;
    }
  }

  Future<bool> _applyFirestoreUpdate(Map<String, dynamic> payload) async {
    try {
      final bookingId = (payload['bookingId'] ?? '').toString().trim();
      final status = (payload['status'] ?? '').toString().trim().toLowerCase();
      final tripId = (payload['tripId'] ?? '').toString().trim();
      final passengerUid = (payload['passengerUid'] ?? '').toString().trim();
      final dropoffTimestamp =
          (payload['dropoffTimestamp'] ?? '').toString().trim();
      final eventId = (payload['eventId'] ?? '').toString().trim();

      if (bookingId.isEmpty || status.isEmpty) return false;

      final updates = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        // Keep booking schema aligned with SMS path by removing legacy metadata keys.
        'lastStatusEventId': FieldValue.delete(),
        'lastUpdateSource': FieldValue.delete(),
        if (tripId.isNotEmpty) 'tripId': tripId,
        if (passengerUid.isNotEmpty) 'userId': passengerUid,
        if (dropoffTimestamp.isNotEmpty) 'dropoffTimestamp': dropoffTimestamp,
      };

      final collections = status == 'dropped-off'
          ? ['bookings', 'bookings_new']
          : ['bookings_new', 'bookings'];

      final updated = await _updateInFirstFound(
        bookingId,
        collections,
        updates,
        eventId,
      );
      if (updated) return true;

      return _statusAlreadyArchived(bookingId, status);
    } catch (e) {
      debugPrint('[BookingStatus] Firestore update error: $e');
      return false;
    }
  }

  Future<bool> _updateInFirstFound(
    String bookingId,
    List<String> collections,
    Map<String, dynamic> updates,
    String eventId,
  ) async {
    for (final name in collections) {
      final ref = _firestore.collection(name).doc(bookingId);
      final snap = await ref.get();
      if (!snap.exists) continue;

      final current = snap.data() ?? <String, dynamic>{};
      if (_isDuplicateEvent(current, eventId)) {
        return true;
      }

      await ref.set(updates, SetOptions(merge: true));
      return true;
    }

    return false;
  }

  Future<bool> _statusAlreadyArchived(String bookingId, String status) async {
    try {
      final snap =
          await _firestore.collection('bookings_archive').doc(bookingId).get();
      if (!snap.exists) return false;
      final archivedStatus =
          (snap.data()?['status'] ?? '').toString().trim().toLowerCase();
      return archivedStatus == status;
    } catch (_) {
      return false;
    }
  }

  bool _isDuplicateEvent(Map<String, dynamic> current, String eventId) {
    if (eventId.isEmpty) return false;
    final currentEventId = (current['lastStatusEventId'] ?? '').toString();
    return currentEventId.isNotEmpty && currentEventId == eventId;
  }

  Future<bool> _isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (result == ConnectivityResult.none) return false;

      // On flaky networks, confirm Firestore connectivity quickly.
      try {
        await _firestore.collection('bookings_new').limit(1).get();
        return true;
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<Box<List>> _openQueueBox() async {
    if (!Hive.isBoxOpen(_queueBoxName)) {
      return Hive.openBox<List>(_queueBoxName);
    }
    return Hive.box<List>(_queueBoxName);
  }

  Future<List<Map<String, dynamic>>> _loadQueue() async {
    final box = await _openQueueBox();
    final raw = box.get(_queueKey) ?? [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> items) async {
    final box = await _openQueueBox();
    await box.put(_queueKey, items);
  }

  Future<void> _enqueuePending(Map<String, dynamic> payload) async {
    final items = await _loadQueue();
    final eventId = (payload['eventId'] ?? '').toString();
    final exists = items.any((e) {
      final p = Map<String, dynamic>.from(
          (e['payload'] as Map).cast<String, dynamic>());
      return (p['eventId'] ?? '').toString() == eventId;
    });
    if (exists) return;

    items.add({
      'payload': payload,
      'queuedAtMs': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'smsSent': false,
      'lastError': '',
    });
    await _saveQueue(items);
  }

  String? _emptyToNull(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }
}
