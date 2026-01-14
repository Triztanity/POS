import 'dart:convert';
import '../utils/fare_calculator.dart';
import 'package:untitled/utils/route_validator.dart' as route_validator;
import 'scan_storage.dart';

/// Result object returned by the offline QR processor
class OfflineQrResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  OfflineQrResult({required this.success, required this.message, this.data});
}

/// Offline QR parsing and validation service
class OfflineQrService {
  /// Attempt to parse a QR payload. Supports raw JSON or base64-encoded JSON.
  static Map<String, dynamic>? _tryParsePayload(String raw) {
    try {
      // First try raw JSON
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return Map<String, dynamic>.from(m.cast<String, dynamic>());
    } catch (_) {}

    try {
      // Try base64 decode then JSON
      final decoded = utf8.decode(base64.decode(raw));
      final m = jsonDecode(decoded);
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return Map<String, dynamic>.from(m.cast<String, dynamic>());
    } catch (_) {}

    return null;
  }

  /// Validate booking payload against offline rules.
  /// - Enforces bus number match
  /// - Validates origin/destination against station list
  /// - Checks route direction (North vs South)
  /// - Prevents duplicate scans
  /// - Saves scan locally for offline audit
  /// 
  /// Parameters:
  ///   rawQr: QR payload (JSON or base64-encoded JSON)
  ///   currentBusNumber: Device's assigned bus (e.g., 'BUS-002')
  ///   currentRoute: Conductor-selected route ('North' or 'South')
  ///   availableDestinations: List of valid destination stops from home_screen dropdown
  static Future<OfflineQrResult> validateAndProcess({
    required String rawQr,
    String? currentBusNumber,
    String? currentRoute,
    List<String>? availableDestinations,
  }) async {
    // Parse QR payload
    final payload = _tryParsePayload(rawQr);
    if (payload == null) return OfflineQrResult(success: false, message: 'Invalid QR payload');

    // Normalize keys to a canonical form
    Map<String, dynamic> normalized = {};
    payload.forEach((k, v) {
      final key = k.toString().trim().toLowerCase().replaceAll(RegExp(r"[_\s]"), '');
      normalized[key] = v;
    });

    // Map aliases to canonical field names
    final Map<String, dynamic> p = {
      'transactionId': normalized['transactionid'] ?? normalized['txn'] ?? normalized['txnid'],
      'busNumber': normalized['busnumber'] ?? normalized['vehicleno'] ?? normalized['vehiclenumber'],
      'busRoute': normalized['busroute'] ?? normalized['route'],
      'origin': normalized['origin'] ?? normalized['from'] ?? normalized['fromplace'] ?? normalized['originplace'],
      'destination': normalized['destination'] ?? normalized['to'] ?? normalized['toplace'] ?? normalized['destinationplace'],
      'fare': normalized['fare'] ?? normalized['amount'] ?? normalized['price'] ?? normalized['fareamount'],
      'paymentMethod': normalized['paymentmethod'] ?? normalized['method'] ?? normalized['payment'] ?? normalized['paymenttype'] ?? normalized['paymethod'] ?? normalized['pmethod'] ?? normalized['pay_method'],
      'paymentStatus': normalized['paymentstatus'] ?? normalized['status'],
      'createdAt': normalized['createdat'] ?? normalized['createdatiso'] ?? normalized['created'] ?? normalized['timestamp'] ?? normalized['time'] ?? normalized['ts'] ?? normalized['date'],
    };

    // Check required fields
    final required = ['transactionId', 'origin', 'destination', 'fare'];
    for (var k in required) {
      if (p[k] == null) {
        return OfflineQrResult(
          success: false,
          message: 'Missing field: $k',
          data: {
            'debug': {
              'receivedKeys': payload.keys.toList(),
              'normalizedKeys': normalized.keys.toList(),
            }
          },
        );
      }
    }

    // Default paymentMethod to 'GCash' if missing
    p['paymentMethod'] = p['paymentMethod'] ?? 'GCash';

    // Validate payment method
    if (p['paymentMethod']?.toString().toLowerCase() != 'gcash') {
      return OfflineQrResult(
        success: false,
        message: 'Payment method not GCash',
        data: {'actual': p['paymentMethod']},
      );
    }

    // Validate bus number matches device assignment
    if (p['busNumber'] != null) {
      final expectedBus = (currentBusNumber ?? 'BUS-002').toString();
      // Normalize both for comparison
      String normalizeForCompare(String s) => s.toString().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '');
      final expected = normalizeForCompare(expectedBus);
      final actual = normalizeForCompare(p['busNumber']?.toString() ?? '');
      if (!(actual == expected || actual.contains(expected) || expected.contains(actual))) {
        return OfflineQrResult(
          success: false,
          message: 'Passenger boarded the wrong bus',
          data: {
            'expectedBus': expectedBus,
            'actualBus': p['busNumber'],
          },
        );
      }
    }

    // Validate origin exists in master station list
    final originIndex = route_validator.RouteValidator.findStationIndex(
      p['origin']?.toString() ?? '',
      route_validator.RouteValidator.getStationListForDirection('north'),
    );
    if (originIndex < 0) {
      return OfflineQrResult(
        success: false,
        message: 'System could not determine the origin or destination',
        data: {'attemptedOrigin': p['origin']},
      );
    }

    // Validate destination exists in provided destination list (home_screen dropdown)
    final destList = availableDestinations ?? _getDefaultDestinations();
    final normalizedDest = route_validator.RouteValidator.normalizeStationName(p['destination']?.toString() ?? '');
    final destExists = destList.any((d) => route_validator.RouteValidator.normalizeStationName(d) == normalizedDest);
    if (!destExists) {
      return OfflineQrResult(
        success: false,
        message: 'System could not determine the origin or destination',
        data: {'attemptedDestination': p['destination']},
      );
    }

    // Find destination index in master station list
    final destinationIndex = route_validator.RouteValidator.findStationIndex(
      p['destination']?.toString() ?? '',
      route_validator.RouteValidator.getStationListForDirection('north'),
    );
    if (destinationIndex < 0) {
      return OfflineQrResult(
        success: false,
        message: 'System could not determine the origin or destination',
        data: {'attemptedDestination': p['destination']},
      );
    }

    // Validate route direction (if route info available)
    if (currentRoute != null) {
      final routeValidation = route_validator.RouteValidator.validateRoute(
        p['origin']?.toString() ?? '',
        p['destination']?.toString() ?? '',
        currentRoute,
      );
      if (!routeValidation.isValid) {
        return OfflineQrResult(
          success: false,
          message: routeValidation.message,
          data: {
            'originIndex': originIndex,
            'destinationIndex': destinationIndex,
            'expectedRoute': currentRoute,
          },
        );
      }
    }

    // Duplicate check
    final tx = p['transactionId'].toString();
    await ScanStorage.init();
    if (ScanStorage.hasScanned(tx)) {
      return OfflineQrResult(success: false, message: 'Ticket already used');
    }

    // Save scan record
    final scannedAt = DateTime.now().toIso8601String();
    final record = Map<String, dynamic>.from(p);
    record['scannedAt'] = scannedAt;
    record['rawPayload'] = payload;
    await ScanStorage.saveScan(record);

    return OfflineQrResult(success: true, message: 'OK', data: record);
  }

  /// Default list of destinations. Uses FareTable places from home_screen dropdown.
  static List<String> _getDefaultDestinations() {
    return FareTable.placeNames;
  }
}
