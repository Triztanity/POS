import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/qr_data.dart';
import '../models/booking.dart';
import '../models/scanned_ticket.dart';
import '../services/qr_validation_service.dart';
import '../services/ticket_printer.dart';
import '../local_storage.dart';
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

  Future<void> _processQr(String rawQrData) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    if (LocalStorage.isManualMode()) {
      _showError('Manual Mode', 'Device is in manual ticketing mode. Scanning is disabled.');
      setState(() => _isProcessing = false);
      return;
    }

    try {
    QRData qrData;
    try {
      qrData = QRData.fromJson(rawQrData);
    } catch (e) {
      _showError('Invalid QR Code', 'Failed to decode QR data: $e');
      setState(() => _isProcessing = false);
      return;
    }

    // Check QR expiration (new validation)
    final expirationValidation = QRValidationService.validateExpiration(qrData);
    if (!expirationValidation.isValid) {
      _handleValidationFailure(expirationValidation);
      setState(() => _isProcessing = false);
      return;
    }

    // Check for duplicate scan (new validation)
    final duplicateValidation = QRValidationService.checkDuplicate(qrData.bookingId);
    if (!duplicateValidation.isValid) {
      _handleValidationFailure(duplicateValidation);
      setState(() => _isProcessing = false);
      return;
    }

    // Bus validation (kept as-is per constraints)
    final busValidation = await QRValidationService.validateBusNumber(qrData);
    if (!busValidation.isValid) {
      _handleValidationFailure(busValidation);
      setState(() => _isProcessing = false);
      return;
    }

    // Route validation (centralized and index-based)
    final routeValidation = QRValidationService.validateRoute(qrData, widget.routeDirection);
    if (!routeValidation.isValid) {
      _handleValidationFailure(routeValidation);
      setState(() => _isProcessing = false);
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
      setState(() => _isProcessing = false);
      return;
    }

      // Step 5: Extract fare data from passenger type selection
      final passengerType = result['passengerType'] as String;
      final originalFare = result['originalFare'] as double;
      final discountAmount = result['discountAmount'] as double;
      final finalFare = result['finalFare'] as double;

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
        passengerType: passengerType,
        originalFare: originalFare,
        discountAmount: discountAmount,
        finalFare: finalFare,
        scannedAt: DateTime.now(),
        conductorName: widget.conductorName,
        driverName: widget.driverName,
        printed: false,
      );

      // Step 7: Prepare ticket data for printing
      final ticketRouteValue = widget.routeDirection == 'north_to_south' ? 'north' : 'south';

      final ticketData = {
        'bookingId': qrData.bookingId,
        'transactionId': qrData.transactionId,
        'timestamp': DateTime.now().toString(),
        'busNumber': qrData.assignedBusNumber,
        'from': qrData.origin,
        'to': qrData.destination,
        'route': ticketRouteValue,
        'driverName': widget.driverName,
        'conductorName': widget.conductorName,
        'passengerName': qrData.passengerName,
        'numberOfPassengers': qrData.numberOfPassengers,
        'passengerType': passengerType,
        'originalFare': originalFare.toStringAsFixed(2),
        'discountAmount': discountAmount.toStringAsFixed(2),
        'finalFare': finalFare.toStringAsFixed(2),
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

      // Step 10: Create booking record for Firebase sync (trip-scoped, deleted per trip)
      final booking = Booking(
        id: qrData.bookingId,
        passengerName: qrData.passengerName,
        route: widget.routeDirection == 'north_to_south' ? 'North → South' : 'South → North',
        date: DateTime.now().toString().split(' ')[0], // YYYY-MM-DD
        time: '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        passengers: qrData.numberOfPassengers,
        fromLocation: qrData.origin,
        toLocation: qrData.destination,
        passengerUid: qrData.userId,
        passengerType: passengerType,
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
        'amount': booking.amount,
        'status': booking.status,
        'tripId': LocalStorage.getCurrentTripId(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'syncStatus': 'pending',
      };
      await LocalStorage.saveBookingForTrip(bookingRecord);
      
      // Step 12: Add booking to BookingManager for display on bookings_screen
      BookingManager().addBooking(booking);

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
                Navigator.pop(context, scannedTicket.transactionId); // return to home screen
              },
              child: const Text('OK'),
            )
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Error', 'An unexpected error occurred: $e');
    }

    setState(() => _isProcessing = false);
  }

  void _handleValidationFailure(dynamic validationResult) {
    final message = (validationResult?.message as String?) ?? 'Validation failed';
    final errorType = (validationResult?.errorType as String?) ?? '';

    if (!mounted) return;

    if (errorType == 'UNDETERMINED_LOCATION') {
      _showError('Undetermined Location', 'System could not determine the origin or destination');
      return;
    }

    if (errorType == 'OUT_OF_ROUTE') {
      _showError('Out of Route', 'Passenger is out of route and going to the wrong direction');
      return;
    }

    if (errorType == 'WRONG_BUS') {
      _showError('Wrong Bus', message);
      return;
    }

    _showError('Validation Failed', message);
  }

  void _showError(String title, String message) {
    showDialog(
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
