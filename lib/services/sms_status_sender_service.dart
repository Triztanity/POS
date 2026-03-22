import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/inspection.dart';

class SmsStatusSenderService {
  SmsStatusSenderService._internal();

  static final SmsStatusSenderService _instance =
      SmsStatusSenderService._internal();

  factory SmsStatusSenderService() => _instance;

  static const MethodChannel _channel =
      MethodChannel('com.example.untitled/sms_sender');

  // Raspberry Pi modem number.
  static const String _gatewayNumber = '09556751976';

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+63')) return digits;
    if (digits.startsWith('09') && digits.length == 11) {
      return '+63${digits.substring(1)}';
    }
    return digits;
  }

  String _eventId(String prefix) {
    final now = DateTime.now();
    return '$prefix-${now.microsecondsSinceEpoch}';
  }

  Future<Map<String, dynamic>> _sendRaw(String message) async {
    final permission = await Permission.sms.request();
    if (!permission.isGranted) {
      return {'success': false, 'message': 'SMS permission denied'};
    }
    final phone = _normalizePhone(_gatewayNumber);
    try {
      await _channel.invokeMethod('sendSms', {
        'phoneNumber': phone,
        'message': message,
      });
      return {'success': true, 'message': 'SMS sent'};
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'SMS send failed',
        'code': e.code,
      };
    }
  }

  // ---------------------------------------------------------------------------
  // Booking-status update  →  BS|{...}
  // Keep payload compact to reduce multipart-SMS risk on weak signal.
  // Gateway parser: parse_booking_status_and_update()
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> sendBookingStatusSms({
    required String bookingId,
    required String tripId,
    required String status,
    String? passengerUid,
    String? dropoffTimestamp,
    String? eventId,
  }) async {
    final payload = <String, dynamic>{
      't': 'bs', // type: booking status
      'e': (eventId != null && eventId.isNotEmpty) ? eventId : _eventId('bs'),
      'b': bookingId,
      'trip': tripId,
      's': status,
      if (passengerUid != null && passengerUid.isNotEmpty) 'u': passengerUid,
      if (dropoffTimestamp != null && dropoffTimestamp.isNotEmpty)
        'd': dropoffTimestamp,
    };

    final message = 'BS|${jsonEncode(payload)}';
    return _sendRaw(message);
  }

  // ---------------------------------------------------------------------------
  // Inspection submission  →  INS|{...}
  // Only essential fields are included to keep the SMS under 160 chars.
  // Gateway parser: parse_inspection_and_upload()
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> sendInspectionSms(Inspection inspection) async {
    final payload = <String, dynamic>{
      'id': inspection.id,
      'timestamp': inspection.timestamp,
      'busNumber': inspection.busNumber,
      if (inspection.tripId != null && inspection.tripId!.isNotEmpty)
        'tripId': inspection.tripId,
      'inspectorUid': inspection.inspectorUid ?? '',
      'conductorUid': inspection.conductorUid,
      'driverUid': inspection.driverUid,
      'manualPassengerCount': inspection.manualPassengerCount,
      'systemPassengerCount': inspection.systemPassengerCount,
      'isCleared': inspection.isCleared,
      if (inspection.comments != null && inspection.comments!.isNotEmpty)
        'comments': inspection.comments,
    };

    final message = 'INS|${jsonEncode(payload)}';
    return _sendRaw(message);
  }
}
