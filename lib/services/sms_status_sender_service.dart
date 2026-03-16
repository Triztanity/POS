import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsStatusSenderService {
  SmsStatusSenderService._internal();

  static final SmsStatusSenderService _instance =
      SmsStatusSenderService._internal();

  factory SmsStatusSenderService() => _instance;

  static const MethodChannel _channel =
      MethodChannel('com.example.untitled/sms_sender');

  // Raspberry Pi modem number provided by the user.
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

  Future<Map<String, dynamic>> sendBookingStatusSms({
    required String bookingId,
    required String tripId,
    required String status,
    String? passengerUid,
    String? dropoffTimestamp,
  }) async {
    final permission = await Permission.sms.request();
    if (!permission.isGranted) {
      return {
        'success': false,
        'message': 'SMS permission denied',
      };
    }

    final payload = <String, dynamic>{
      'type': 'booking.status',
      'eventId': _eventId('booking-status'),
      'bookingId': bookingId,
      'tripId': tripId,
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
      if (passengerUid != null && passengerUid.isNotEmpty)
        'passengerUid': passengerUid,
      if (dropoffTimestamp != null && dropoffTimestamp.isNotEmpty)
        'dropoffTimestamp': dropoffTimestamp,
    };

    final message = jsonEncode(payload);
    final phone = _normalizePhone(_gatewayNumber);

    try {
      await _channel.invokeMethod('sendSms', {
        'phoneNumber': phone,
        'message': message,
      });
      return {
        'success': true,
        'message': 'SMS sent',
      };
    } on PlatformException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'SMS send failed',
        'code': e.code,
      };
    }
  }
}
