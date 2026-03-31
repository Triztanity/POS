import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:untitled/models/qr_data.dart';
import 'package:untitled/utils/booking_station_mapping.dart';
import 'package:untitled/utils/route_validator.dart' as route_validator;
import 'device_config_service.dart';
import '../local_storage.dart';

/// QR Validation Service - Validates QR data against device configuration
/// Implements phased anti-replay security model per Plan.md
class QRValidationService {
  /// Validate QR data against device bus number (reads assigned bus from device config)
  static Future<route_validator.ValidationResult> validateBusNumber(
      QRData qrData) async {
    final ticketBus = _normalizeBusNumber(qrData.assignedBusNumber);
    final deviceBusRaw = await DeviceConfigService.getAssignedBus();
    if (deviceBusRaw == null || deviceBusRaw.isEmpty) {
      return route_validator.ValidationResult(
        isValid: false,
        message:
            'Device not configured: unable to determine assigned bus. Please contact admin.',
        errorType: 'DEVICE_NOT_CONFIGURED',
      );
    }
    final deviceBus = _normalizeBusNumber(deviceBusRaw);
    if (ticketBus != deviceBus) {
      return route_validator.ValidationResult(
        isValid: false,
        message:
            'Passenger boarded the wrong bus.\\n\\nTicket: ${qrData.assignedBusNumber}\\nDevice: $deviceBusRaw',
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
    String
        deviceRouteDirection, // expected values: 'north_to_south' or 'south_to_north' (or 'north'/'south')
  ) {
    // Step 1: Resolve station names from QR (handles "Station 5" → actual place name mapping)
    final qrOrigin = resolveStationName(qrData.origin);
    final qrDestination = resolveStationName(qrData.destination);

    // Step 2: Resolve indices using the centralized RouteValidator
    final stationList =
        route_validator.RouteValidator.getStationListForDirection(
            deviceRouteDirection);
    final originIndex =
        route_validator.RouteValidator.findStationIndex(qrOrigin, stationList);
    final destIndex = route_validator.RouteValidator.findStationIndex(
        qrDestination, stationList);

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

  // ─── Phase 1: Expiration Validation ───

  /// Validate QR code expiration date
  static route_validator.ValidationResult validateExpiration(QRData qrData) {
    final now = DateTime.now();
    if (now.isAfter(qrData.expiresAt)) {
      return route_validator.ValidationResult(
        isValid: false,
        message: 'This booking QR code has expired.',
        errorType: 'EXPIRED_QR',
      );
    }
    return route_validator.ValidationResult(
      isValid: true,
      message: 'QR is still valid.',
    );
  }

  // ─── Phase 1: Duplicate Check (Fail-Closed) ───

  /// Check if booking has already been scanned (from local trip-scoped scanned_tickets).
  /// Phase 1: Changed from fail-open to fail-closed on storage error.
  static route_validator.ValidationResult checkDuplicate(String bookingId) {
    try {
      final box = Hive.box<List>('scanned_tickets');
      final tickets = box.get('all') ?? [];

      // Check if any scanned ticket has this bookingId
      for (var ticketData in tickets) {
        if (ticketData is Map) {
          final ticket =
              Map<String, dynamic>.from(ticketData.cast<String, dynamic>());
          if (ticket['bookingId']?.toString() == bookingId) {
            return route_validator.ValidationResult(
              isValid: false,
              message: 'This booking QR has already been used.',
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
      // Phase 1: Fail-CLOSED on storage error (not fail-open)
      debugPrint('[QRValidationService] Error checking duplicate: $e');
      return route_validator.ValidationResult(
        isValid: false,
        message: 'Unable to verify booking status. Please try again.',
        errorType: 'DUPLICATE_CHECK_ERROR',
      );
    }
  }

  // ─── Phase 2+3: Schedule Metadata Validation ───

  /// Validate that QR contains required schedule metadata.
  /// Rejects legacy payloads missing scheduleTime per policy decision.
  static route_validator.ValidationResult validateScheduleMetadata(
      QRData qrData) {
    final scheduleTime = qrData.scheduleTime.trim();
    if (scheduleTime.isEmpty) {
      return route_validator.ValidationResult(
        isValid: false,
        message:
            'Booking QR is missing required schedule information. Please rebook with the latest app.',
        errorType: 'MISSING_SCHEDULE_METADATA',
      );
    }
    return route_validator.ValidationResult(
      isValid: true,
      message: 'Schedule metadata present.',
    );
  }

  /// Validate that QR schedule time matches the active POS schedule.
  /// Uses the same normalization as home_screen schedule detection.
  static route_validator.ValidationResult validateScheduleMatch(
    QRData qrData,
    String activeScheduleTimeKey,
  ) {
    final qrScheduleKey = _normalizeScheduleKey(qrData.scheduleTime);
    final activeKey = _normalizeScheduleKey(activeScheduleTimeKey);

    if (activeKey.isEmpty) {
      // POS has no active schedule context — fail-closed per Phase 6
      return route_validator.ValidationResult(
        isValid: false,
        message:
            'No active schedule detected on POS. Cannot verify booking schedule.',
        errorType: 'NO_ACTIVE_SCHEDULE',
      );
    }

    if (qrScheduleKey.isEmpty) {
      return route_validator.ValidationResult(
        isValid: false,
        message: 'Booking QR is missing schedule time.',
        errorType: 'MISSING_SCHEDULE_METADATA',
      );
    }

    if (qrScheduleKey != activeKey) {
      return route_validator.ValidationResult(
        isValid: false,
        message:
            'This booking is for a different schedule.\n\nBooking: $qrScheduleKey\nActive: $activeKey',
        errorType: 'SCHEDULE_MISMATCH',
      );
    }

    return route_validator.ValidationResult(
      isValid: true,
      message: 'Schedule matches.',
    );
  }

  // ─── Phase 4: Durable Anti-Replay (Consumed Booking Check) ───

  /// Check if booking has been permanently consumed across all trips.
  /// This is the durable check that survives trip resets and restarts.
  /// Phase 6: Fail-closed on storage error.
  static route_validator.ValidationResult checkConsumed(String bookingId) {
    try {
      if (LocalStorage.isBookingConsumed(bookingId)) {
        final info = LocalStorage.getConsumedBookingInfo(bookingId);
        final consumedTripId = info?['tripId']?.toString() ?? 'unknown';
        return route_validator.ValidationResult(
          isValid: false,
          message:
              'This booking has already been used (Trip: $consumedTripId).',
          errorType: 'ALREADY_CONSUMED',
        );
      }
      return route_validator.ValidationResult(
        isValid: true,
        message: 'Booking not yet consumed.',
      );
    } catch (e) {
      // Phase 6: Fail-closed
      debugPrint('[QRValidationService] Error checking consumed booking: $e');
      return route_validator.ValidationResult(
        isValid: false,
        message: 'Unable to verify booking replay status. Please try again.',
        errorType: 'CONSUMED_CHECK_ERROR',
      );
    }
  }

  /// Check consumed status against Firestore (online verification).
  /// Returns true if booking is confirmed consumed in Firestore.
  static Future<route_validator.ValidationResult> checkConsumedOnline(
      String bookingId) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        // Offline — rely on local check only (already done by checkConsumed)
        return route_validator.ValidationResult(
          isValid: true,
          message: 'Offline - using local anti-replay only.',
        );
      }

      final firestore = FirebaseFirestore.instance;

      // Check bookings_archive first (dropped-off bookings)
      final archiveDoc =
          await firestore.collection('bookings_archive').doc(bookingId).get();
      if (archiveDoc.exists) {
        final data = archiveDoc.data();
        final status =
            (data?['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'on-board' || status == 'dropped-off') {
          // Mark locally too for future offline checks
          await LocalStorage.markBookingConsumed(bookingId,
              tripId: data?['tripId']?.toString());
          return route_validator.ValidationResult(
            isValid: false,
            message:
                'This booking was already boarded (archived). Status: $status',
            errorType: 'ALREADY_CONSUMED',
          );
        }
      }

      // Check active bookings
      final bookingDoc =
          await firestore.collection('bookings').doc(bookingId).get();
      if (bookingDoc.exists) {
        final data = bookingDoc.data();
        final status =
            (data?['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'on-board' || status == 'dropped-off') {
          await LocalStorage.markBookingConsumed(bookingId,
              tripId: data?['tripId']?.toString());
          return route_validator.ValidationResult(
            isValid: false,
            message:
                'This booking was already boarded. Status: $status',
            errorType: 'ALREADY_CONSUMED',
          );
        }
      }

      return route_validator.ValidationResult(
        isValid: true,
        message: 'Booking not consumed in Firestore.',
      );
    } catch (e) {
      debugPrint(
          '[QRValidationService] Error checking consumed online: $e');
      // Online check failure is non-fatal — local check is primary
      return route_validator.ValidationResult(
        isValid: true,
        message: 'Online check failed, relying on local anti-replay.',
      );
    }
  }

  // ─── Utilities ───

  /// Calculate discount based on passenger type
  static double calculateDiscount(double originalFare, String passengerType) {
    final normalizedType = passengerType.trim().toUpperCase();
    if (normalizedType == 'REGULAR') {
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

  /// Normalize schedule key: handles Timestamps, DateTimes, and ISO strings
  /// producing a yyyy-MM-dd HH:mm format for comparison.
  static String _normalizeScheduleKey(dynamic raw) {
    if (raw == null) return '';

    final text = raw.toString().trim();
    if (text.isEmpty) return '';

    final asDate = DateTime.tryParse(text) ??
        DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (asDate != null) {
      final local = asDate.toLocal();
      final y = local.year.toString().padLeft(4, '0');
      final m = local.month.toString().padLeft(2, '0');
      final d = local.day.toString().padLeft(2, '0');
      final h = local.hour.toString().padLeft(2, '0');
      final min = local.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $h:$min';
    }

    return text.toLowerCase();
  }
}
