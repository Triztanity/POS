import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

/// ESP32GatewayService
/// Sends booking drop-off data to ESP32 device via local HTTP
/// ESP32 acts as gateway and forwards data to Firebase using its GSM connection
class ESP32GatewayService {
  static final ESP32GatewayService _instance = ESP32GatewayService._internal();

  factory ESP32GatewayService() {
    return _instance;
  }

  ESP32GatewayService._internal();

  // ESP32 configuration - fixed gateway IP when connected to ESP32 hotspot
  static const String esp32Ip = '192.168.4.1';
  static const String esp32Port = '80';
  static const String dropoffEndpoint = '/api/dropoff';
  static const Duration requestTimeout = Duration(seconds: 10);

  /// Get full ESP32 URL
  String get esp32Url => 'http://$esp32Ip:$esp32Port$dropoffEndpoint';

  /// Check if ESP32 is reachable
  Future<bool> isESP32Reachable() async {
    try {
      debugPrint('[ESP32 Gateway] Checking ESP32 reachability at $esp32Ip...');

      final response = await http
          .get(Uri.parse('http://$esp32Ip:$esp32Port/'))
          .timeout(const Duration(seconds: 3));

      final reachable =
          response.statusCode == 200 || response.statusCode == 404;
      debugPrint('[ESP32 Gateway] ESP32 reachable: $reachable');
      return reachable;
    } catch (e) {
      debugPrint('[ESP32 Gateway] ESP32 not reachable: $e');
      return false;
    }
  }

  /// Send drop-off data to ESP32
  Future<Map<String, dynamic>> sendDropoffToESP32({
    required String bookingId,
    required String status,
    required String dropoffTimestamp,
  }) async {
    try {
      debugPrint('[ESP32 Gateway] Sending drop-off to ESP32...');
      debugPrint('[ESP32 Gateway] Booking ID: $bookingId');
      debugPrint('[ESP32 Gateway] URL: $esp32Url');

      // Prepare JSON payload matching ESP32 expected format
      final payload = {
        'action': 'booking_dropoff',
        'bookingId': bookingId,
        'status': status,
        'dropoffTimestamp': dropoffTimestamp,
      };

      debugPrint('[ESP32 Gateway] Payload: ${jsonEncode(payload)}');

      // Send HTTP POST request to ESP32
      final response = await http
          .post(
            Uri.parse(esp32Url),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(requestTimeout);

      debugPrint('[ESP32 Gateway] Response status: ${response.statusCode}');
      debugPrint('[ESP32 Gateway] Response body: ${response.body}');

      // Parse response
      if (response.statusCode == 200) {
        try {
          final responseData = jsonDecode(response.body);
          debugPrint('[ESP32 Gateway] ✅ Success: $responseData');

          return {
            'success': true,
            'message': responseData['message'] ?? 'Data sent successfully',
            'data': responseData,
          };
        } catch (e) {
          // ESP32 sent 200 but invalid JSON
          debugPrint('[ESP32 Gateway] ✅ Success (non-JSON response)');
          return {
            'success': true,
            'message': 'Data sent successfully',
            'data': null,
          };
        }
      } else {
        // ESP32 returned error status
        String errorMessage = 'Upload failed';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['message'] ?? errorMessage;
        } catch (e) {
          // Could not parse error response
        }

        debugPrint('[ESP32 Gateway] ❌ Error: $errorMessage');
        return {
          'success': false,
          'message': errorMessage,
          'statusCode': response.statusCode,
        };
      }
    } on TimeoutException catch (e) {
      debugPrint('[ESP32 Gateway] ❌ Timeout: $e');
      return {
        'success': false,
        'message': 'Request timeout. ESP32 not responding.',
        'error': 'timeout',
      };
    } catch (e) {
      debugPrint('[ESP32 Gateway] ❌ Error: $e');
      return {
        'success': false,
        'message': 'Failed to connect to ESP32: $e',
        'error': e.toString(),
      };
    }
  }

  /// Convenience method for marking booking as dropped off
  Future<bool> markBookingAsDroppedOff(String bookingId) async {
    final timestamp = DateTime.now().toIso8601String();

    final result = await sendDropoffToESP32(
      bookingId: bookingId,
      status: 'dropped-off',
      dropoffTimestamp: timestamp,
    );

    return result['success'] == true;
  }
}
