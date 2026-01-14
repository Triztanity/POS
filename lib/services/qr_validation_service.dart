import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:untitled/models/qr_data.dart';
import 'package:untitled/utils/booking_station_mapping.dart';
import 'package:untitled/utils/route_validator.dart' as route_validator;
import 'device_config_service.dart';

/// QR Validation Service - Validates QR data against device configuration
class QRValidationService {
  /// Validate QR data against device bus number (reads assigned bus from device config)
  static Future<route_validator.ValidationResult> validateBusNumber(QRData qrData) async {
    final ticketBus = _normalizeBusNumber(qrData.assignedBusNumber);
    final deviceBusRaw = await DeviceConfigService.getAssignedBus();
    if (deviceBusRaw == null || deviceBusRaw.isEmpty) {
      return route_validator.ValidationResult(
        isValid: false,
        message: 'Device not configured: unable to determine assigned bus. Please contact admin.',
        errorType: 'DEVICE_NOT_CONFIGURED',
      );
    }
    final deviceBus = _normalizeBusNumber(deviceBusRaw);
    if (ticketBus != deviceBus) {
      return route_validator.ValidationResult(
        isValid: false,
        message: 'Passenger boarded the wrong bus.\\n\\nTicket: ${qrData.assignedBusNumber}\\nDevice: $deviceBusRaw',
        errorType: 'WRONG_BUS',
      );
    }
    return route_validator.ValidationResult(
      isValid: true,
      message: 'Bus number validated.',
    );
  }

  /// Validate QR route against device route direction using direction-aware validation
  /// Supports both simple direction names and full route format
  static route_validator.ValidationResult validateRoute(
    QRData qrData,
    String deviceRouteDirection, // expected values: 'north_to_south' or 'south_to_north' (or 'north'/'south')
  ) {
    // Step 1: Resolve station names from QR (handles "Station 5" → actual place name mapping)
    final qrOrigin = resolveStationName(qrData.origin);
    final qrDestination = resolveStationName(qrData.destination);

    // Step 2: Resolve indices using the centralized RouteValidator
    final stationList = route_validator.RouteValidator.getStationListForDirection(deviceRouteDirection);
    final originIndex = route_validator.RouteValidator.findStationIndex(qrOrigin, stationList);
    final destIndex = route_validator.RouteValidator.findStationIndex(qrDestination, stationList);

    // Step 3: Determine outcome according to rules
    // Undetermined Location: either station not found
    if (originIndex == -1 || destIndex == -1) {
      return route_validator.ValidationResult(
        isValid: false,
        message: 'System could not determine the origin or destination',
        errorType: 'UNDETERMINED_LOCATION',
      );
    }

    // Correct sequencing: origin index must be less than destination index in the direction-specific list
    if (originIndex < destIndex) {
      return route_validator.ValidationResult(
        isValid: true,
        message: 'Valid',
      );
    }

    // Out of route / wrong direction
    return route_validator.ValidationResult(
      isValid: false,
      message: 'Passenger is out of route and going to the wrong direction',
      errorType: 'OUT_OF_ROUTE',
    );
  }

  /// Validate QR code expiration date
  static route_validator.ValidationResult validateExpiration(QRData qrData) {
    final now = DateTime.now();
    if (now.isAfter(qrData.expiresAt)) {
      return route_validator.ValidationResult(
        isValid: false,
        message: 'QR code has already expired',
        errorType: 'EXPIRED',
      );
    }
    return route_validator.ValidationResult(
      isValid: true,
      message: 'QR is still valid.',
    );
  }

  /// Check if booking has already been scanned (duplicate detection from confirmed bookings only)
  static route_validator.ValidationResult checkDuplicate(String bookingId) {
    try {
      final box = Hive.box<List>('scanned_tickets');
      final tickets = box.get('all') ?? [];
      
      // Check if any scanned ticket has this bookingId
      for (var ticketData in tickets) {
        if (ticketData is Map) {
          final ticket = Map<String, dynamic>.from(ticketData.cast<String, dynamic>());
          if (ticket['bookingId']?.toString() == bookingId) {
            return route_validator.ValidationResult(
              isValid: false,
              message: 'QR code has already been used',
              errorType: 'DUPLICATE_SCAN',
            );
          }
        }
      }
      
      return route_validator.ValidationResult(
        isValid: true,
        message: 'Booking not previously scanned.',
      );
    } catch (e) {
      // If error accessing box, log but allow (safer to proceed)
      debugPrint('[QRValidationService] Error checking duplicate: $e');
      return route_validator.ValidationResult(
        isValid: true,
        message: 'Booking not previously scanned.',
      );
    }
  }

  /// Calculate discount based on passenger type
  static double calculateDiscount(double originalFare, String passengerType) {
    if (passengerType == 'REGULAR') {
      return 0.0; // No discount
    }
    // Apply 20% discount for non-regular passengers
    return originalFare * 0.20;
  }

  static String _normalizeBusNumber(String raw) {
    var s = raw.trim().toUpperCase();
    s = s.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    return s;
  }

  /// Resolve a station name from the booking system to the RouteValidationService station name
  /// Handles various formats like "11. TUY", "TUY", index-based names, formatting differences, etc.
  static String resolveStationName(String bookingStation) {
    // Strip numeric prefixes like "11. " first
    var cleaned = bookingStation.replaceAll(RegExp(r'^\d+\.\s*'), '').trim();
    
    // Try the booking station mapping first (exact matches)
    var resolved = BookingStationMapping.resolveStation(cleaned);
    
    // If the mapping returned the uppercase version, try to use it directly
    // The fuzzy matching in RouteValidationService.getStationIndex will handle variations
    return resolved;
  }
}
