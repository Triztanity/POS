import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/qr_data.dart';
import '../models/booking.dart';
import '../models/scanned_ticket.dart';
import '../services/qr_validation_service.dart';
import '../services/ticket_printer.dart';
import '../services/trip_record_live_service.dart';
import '../local_storage.dart';
import '../utils/fare_calculator.dart';
import 'booking_confirmation_screen.dart';

/// QR Scanner Screen - Complete flow with validation and ticket printing
class QrScannerScreen extends StatefulWidget {
  final String routeDirection; // 'north_to_south' or 'south_to_north'
  final String conductorName;
  final String driverName;

  const QrScannerScreen({
    super.key,
    required this.routeDirection,
    required this.conductorName,
    required this.driverName,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController controller;
  bool _isProcessing = false;
  final TicketPrinter _printer = TicketPrinter();

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      facing: CameraFacing.back,
      torchEnabled: false,
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final weekday =
        ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1];
    return '$weekday ${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTime12(DateTime dt) {
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final h12 = ((dt.hour + 11) % 12 + 1).toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h12:$m $period';
  }

  String _calculateDistance(String origin, String destination) {
    final originEntry = FareTable.getEntryByPlace(origin);
    final destEntry = FareTable.getEntryByPlace(destination);
    if (originEntry == null || destEntry == null) return '0';
    return (originEntry.km - destEntry.km).abs().toString();
  }

  Future<void> _processQr(String rawQrData) async {
    if (LocalStorage.isManualMode()) {
      await _showError('Manual Mode',
          'Device is in manual ticketing mode. Scanning is disabled.');
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    try {
      QRData qrData;
      try {
        qrData = QRData.fromJson(rawQrData);
      } catch (e) {
        await _showError('Invalid QR Code', 'Failed to decode QR data: $e');
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // ── Phase 4: Durable anti-replay check (consumed bookings, survives restarts) ──
      final consumedValidation =
          QRValidationService.checkConsumed(qrData.bookingId);
      if (!consumedValidation.isValid) {
        await _handleValidationFailure(consumedValidation);
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // ── Phase 1: Duplicate check within current trip scanned tickets (fail-closed) ──
      final duplicateValidation =
          QRValidationService.checkDuplicate(qrData.bookingId);
      if (!duplicateValidation.isValid) {
        await _handleValidationFailure(duplicateValidation);
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // ── Phase 1: Expiration validation ──
      final expirationValidation =
          QRValidationService.validateExpiration(qrData);
      if (!expirationValidation.isValid) {
        await _handleValidationFailure(expirationValidation);
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // ── Phase 1: Bus validation ──
      final busValidation = await QRValidationService.validateBusNumber(qrData);
      if (!busValidation.isValid) {
        await _handleValidationFailure(busValidation);
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // ── Phase 1: Route validation ──
      final routeValidation =
          QRValidationService.validateRoute(qrData, widget.routeDirection);
      if (!routeValidation.isValid) {
        await _handleValidationFailure(routeValidation);
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // ── Phase 2: Schedule metadata check (WARN-ONLY during transition) ──
      // TODO: Re-enable blocking once QR producer includes scheduleTime in payload
      final scheduleMetaValidation =
          QRValidationService.validateScheduleMetadata(qrData);
      if (!scheduleMetaValidation.isValid) {
        debugPrint(
            '[Scanner] WARN: ${scheduleMetaValidation.errorType} - ${scheduleMetaValidation.message}');
        // Non-blocking: log but continue during QR producer transition period
      }

      // ── Phase 3: Schedule match check (WARN-ONLY during transition) ──
      // TODO: Re-enable blocking once field name confirmed in Firestore + QR has scheduleTime
      // Primary source: locally saved accepted schedule (saved at dispatch, no network needed)
      final activeScheduleKey = LocalStorage.getAcceptedScheduleTimeKey();
      debugPrint(
          '[Scanner] activeScheduleKey from local accepted schedule: "$activeScheduleKey"');
      debugPrint('[Scanner] QR scheduleTime: "${qrData.scheduleTime}"');
      final scheduleMatchValidation =
          QRValidationService.validateScheduleMatch(qrData, activeScheduleKey);
      if (!scheduleMatchValidation.isValid) {
        debugPrint(
            '[Scanner] WARN: ${scheduleMatchValidation.errorType} - ${scheduleMatchValidation.message}');
        // Non-blocking: log but continue during QR producer transition period
      }

      // ── Phase 4: Online consumed check (async, best-effort) ──
      final onlineConsumedValidation =
          await QRValidationService.checkConsumedOnline(qrData.bookingId);
      if (!onlineConsumedValidation.isValid) {
        await _handleValidationFailure(onlineConsumedValidation);
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // Passenger type selection
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => BookingConfirmationScreen(
            qrData: qrData,
            routeDirection: widget.routeDirection,
            conductorName: widget.conductorName,
            driverName: widget.driverName,
          ),
        ),
      );

      if (result == null) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // Step 5: Extract fare data from passenger type selection
      final passengerType = result['passengerType'] as String;
      final passengerTypes = (result['passengerTypes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [passengerType];
      final perSeatFares = (result['perSeatFares'] as List<dynamic>?)
              ?.map((e) => double.tryParse(e.toString()) ?? 0.0)
              .toList() ??
          [result['finalFare'] as double];
      final perSeatTotal = perSeatFares.fold(0.0, (sum, fare) => sum + fare);
      final originalFare = result['originalFare'] as double;
      final discountAmount = result['discountAmount'] as double;
      final finalFare =
          perSeatTotal > 0 ? perSeatTotal : result['finalFare'] as double;

      // Build readable passenger type display: unique ordered types joined by '/'
      String formatPassengerType(String type) {
        final normalized = type.trim().toUpperCase();
        switch (normalized) {
          case 'REGULAR':
            return 'Regular';
          case 'STUDENT':
            return 'Student';
          case 'SENIOR':
            return 'Senior';
          case 'PWD':
            return 'PWD';
          case 'CHILD':
            return 'Child';
          default:
            return type.trim();
        }
      }

      final displayedPassengerTypes = <String>[];
      for (var type in passengerTypes) {
        final formatted = formatPassengerType(type);
        if (formatted.isEmpty) continue;
        if (!displayedPassengerTypes.contains(formatted)) {
          displayedPassengerTypes.add(formatted);
        }
      }
      final displayPassengerType = displayedPassengerTypes.isNotEmpty
          ? displayedPassengerTypes.join('/')
          : formatPassengerType(passengerType);

      // Step 6: Create scanned ticket record
      final scannedTicket = ScannedTicket(
        id: 'ST-${DateTime.now().millisecondsSinceEpoch}',
        bookingId: qrData.bookingId,
        transactionId: qrData.transactionId,
        passengerName: qrData.passengerName,
        numberOfPassengers: qrData.numberOfPassengers,
        origin: qrData.origin,
        destination: qrData.destination,
        busNumber: qrData.assignedBusNumber,
        routeDirection: widget.routeDirection,
        passengerType: passengerTypes.length > 1 ? 'MULTI' : passengerType,
        originalFare: originalFare,
        discountAmount: discountAmount,
        finalFare: finalFare,
        scannedAt: DateTime.now(),
        conductorName: widget.conductorName,
        driverName: widget.driverName,
        printed: false,
      );

      // Step 7: Prepare ticket data for printing
      final ticketRouteValue =
          widget.routeDirection == 'north_to_south' ? 'north' : 'south';

      final nowDate = DateTime.now();
      final ticketDate = _formatDate(nowDate);
      final ticketTime = _formatTime12(nowDate);
      final originPlace = FareTable.extractPlaceName(qrData.origin);
      final destPlace = FareTable.extractPlaceName(qrData.destination);
      final ticketDistance = _calculateDistance(originPlace, destPlace);

      final ticketData = {
        'bookingId': qrData.bookingId,
        'transactionId': qrData.transactionId,
        'timestamp': nowDate.toIso8601String(),
        'date': ticketDate,
        'time': ticketTime,
        'busNumber': qrData.assignedBusNumber,
        'from': originPlace,
        'to': destPlace,
        'route': ticketRouteValue,
        'driverName': widget.driverName,
        'conductorName': widget.conductorName,
        'passengerName': qrData.passengerName,
        'numberOfPassengers': qrData.numberOfPassengers,
        'quantity': qrData.numberOfPassengers.toString(),
        'passengerType': displayPassengerType,
        'distance': ticketDistance,
        'originalFare': originalFare.toStringAsFixed(2),
        'discountAmount': discountAmount.toStringAsFixed(2),
        'finalFare': finalFare.toStringAsFixed(2),
        'payment': 'CASH',
        'ticketTitle': 'BOOKING TICKET',
      };

      // Step 8: Print ticket
      try {
        await _printer.printTicket(ticketData);
        scannedTicket.printed = true;
      } catch (e) {
        debugPrint('Printing failed: $e');
        // Continue even if printing fails - ticket is still saved
      }

      // Step 9: Save scanned ticket to local storage (persistent historical record)
      await LocalStorage.saveScannedTicket(scannedTicket.toMap());

      // Step 9b: Mark booking as durably consumed (Phase 4 - anti-replay)
      await LocalStorage.markBookingConsumed(qrData.bookingId);

      // Step 10: Create a single booking record for Firebase sync (POS will split for internal right-side calculations)
      final booking = Booking(
        id: qrData.bookingId,
        passengerName: qrData.passengerName,
        route: widget.routeDirection == 'north_to_south'
            ? 'North → South'
            : 'South → North',
        date: DateTime.now().toString().split(' ')[0],
        time:
            '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        passengers: qrData.numberOfPassengers,
        fromLocation: qrData.origin,
        toLocation: qrData.destination,
        passengerUid: qrData.userId,
        passengerType:
            passengerTypes.isNotEmpty ? passengerTypes.first : passengerType,
        passengerTypes: passengerTypes,
        amount: finalFare,
        status: 'on-board',
      );

      // Step 11: Save booking to LocalStorage (will be synced to Firebase and deleted per trip)
      final bookingRecord = {
        'id': booking.id,
        'passengerName': booking.passengerName,
        'route': booking.route,
        'date': booking.date,
        'time': booking.time,
        'passengers': booking.passengers,
        'fromLocation': booking.fromLocation,
        'toLocation': booking.toLocation,
        'passengerUid': booking.passengerUid,
        'passengerType': booking.passengerType,
        'passengerTypes': booking.passengerTypes,
        'amount': booking.amount,
        'status': booking.status,
        'tripId': LocalStorage.getCurrentTripId(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      };
      await LocalStorage.saveBookingForTrip(bookingRecord);

      // Step 12: Add booking to BookingManager for display on bookings_screen
      BookingManager().addBooking(booking);
      await TripRecordLiveService().publishNow(reason: 'qr-booking');

      // Step 13: Show success and return
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('✓ Boarding Confirmed'),
          content: Text(
            'Ticket printed and transaction saved.\n\n'
            'Passenger: ${qrData.passengerName}\n'
            'Final Fare: ₱${finalFare.toStringAsFixed(2)}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context,
                    scannedTicket.transactionId); // return to home screen
              },
              child: const Text('OK'),
            )
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await _showError('Error', 'An unexpected error occurred: $e');
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  Future<void> _handleValidationFailure(dynamic validationResult) async {
    final message =
        (validationResult?.message as String?) ?? 'Validation failed';
    final errorType = (validationResult?.errorType as String?) ?? '';

    if (!mounted) return;

    switch (errorType) {
      case 'UNDETERMINED_LOCATION':
        await _showError('Undetermined Location',
            'System could not determine the origin or destination');
        return;
      case 'OUT_OF_ROUTE':
        await _showError('Out of Route',
            'Passenger is out of route and going to the wrong direction');
        return;
      case 'WRONG_BUS':
        await _showError('Wrong Bus', message);
        return;
      case 'DUPLICATE_SCAN':
        await _showError('Already Used',
            'This booking QR has already been used on this trip.');
        return;
      case 'ALREADY_CONSUMED':
        await _showError('Already Used', message);
        return;
      case 'EXPIRED_QR':
        await _showError('Expired QR', 'This booking QR code has expired.');
        return;
      case 'MISSING_SCHEDULE_METADATA':
        await _showError('Invalid Booking QR',
            'Booking QR is missing required schedule information. Please rebook with the latest app.');
        return;
      case 'SCHEDULE_MISMATCH':
        await _showError('Schedule Mismatch', message);
        return;
      case 'NO_ACTIVE_SCHEDULE':
        await _showError('No Active Schedule',
            'No active schedule detected on this POS device. Cannot verify booking.');
        return;
      case 'DUPLICATE_CHECK_ERROR':
      case 'CONSUMED_CHECK_ERROR':
        await _showError('Verification Error',
            'Unable to verify booking status. Please try again.');
        return;
      case 'DEVICE_NOT_CONFIGURED':
        await _showError('Device Error', message);
        return;
      default:
        await _showError('Validation Failed', message);
    }
  }

  Future<void> _showError(String title, String message) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Passenger QR'),
        backgroundColor: Colors.green[700],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? code = barcodes.first.rawValue;
                if (code != null && !_isProcessing) {
                  _isProcessing = true;
                  if (mounted) setState(() {});
                  _processQr(code);
                }
              }
            },
          ),
          if (_isProcessing)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'Processing QR...',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
