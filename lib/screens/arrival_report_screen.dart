import 'package:flutter/material.dart';
import 'package:senraise_printer/senraise_printer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/device_config_service.dart';
import '../services/device_identifier_service.dart';
import '../models/booking.dart';
import '../local_storage.dart';
import '../utils/fare_calculator.dart';
import 'dispatch_screen.dart';
import 'records_screen.dart';
import 'login_screen.dart';
import '../services/app_state.dart';

class ArrivalReportScreen extends StatefulWidget {
  final Map<String, String> tripInfo;
  final List<Booking> bookings;
  final List<Map<String, dynamic>> scannedTickets;
  final List<Map<String, dynamic>> inspections;

  const ArrivalReportScreen({super.key, required this.tripInfo, required this.bookings, required this.scannedTickets, required this.inspections});

  @override
  State<ArrivalReportScreen> createState() => _ArrivalReportScreenState();
}

class _ArrivalReportScreenState extends State<ArrivalReportScreen> {
  final SenraisePrinter _printer = SenraisePrinter();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final panelH = mq.size.height * 0.10;
    final now = DateTime.now();
    // Determine route label
    // Normalize route stored in tripInfo (expecting 'north' or 'south')
    final routeValue = (widget.tripInfo['route'] ?? '').toString().toLowerCase();
    final routeLabel = (routeValue == 'north')
      ? 'BATANGAS GRAND - NASUGBU'
      : 'NASUGBU - BATANGAS GRAND';

    // Count walk-in and booking passengers from the bookings list
    final walkInTickets = widget.bookings.where((b) => b.passengerUid == null).length;
    final bookingTickets = widget.bookings.where((b) => b.passengerUid != null).length;
    final allTickets = walkInTickets + bookingTickets;
    final inspectionsMade = widget.inspections.length;

    final hasBookingScans = widget.scannedTickets.isNotEmpty;
    final ticketMode = hasBookingScans ? 'REGULAR TRIP WITH BOOKINGS' : 'REGULAR TRIP';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text('ARRIVAL REPORT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SizedBox.expand(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: mq.size.width - 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Top row: date/time and route/company
              // Top: company then route centered
              Center(
                child: Column(
                  children: [
                    Text(
                      now.toLocal().toString().split('.')[0],
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Text('BATMAN STAREXPRESS CORPORATION', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green[800])),
                    const SizedBox(height: 4),
                    Text(routeLabel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // Driver / Conductor card
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DRIVER', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        const SizedBox(height: 3),
                        Text(widget.tripInfo['driver'] ?? 'Unknown', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('CONDUCTOR', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        const SizedBox(height: 3),
                        Text(widget.tripInfo['conductor'] ?? 'Unknown', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Dispatcher rectangular panel (tappable)
            InkWell(
              onTap: () async {
                // Show options: view records or dispatch a new trip
                final choice = await showDialog<String?>(
                  context: context,
                  builder: (_) => SimpleDialog(
                    title: const Text('Dispatcher Actions'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(context).pop('records'),
                        child: const Text('View Records'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(context).pop('dispatch'),
                        child: const Text('Dispatch New Trip'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );

                if (choice == 'records') {
                  if (!mounted) return;
                  final dispatcherInfo = {'name': widget.tripInfo['dispatcher'] ?? 'Unknown'};
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => RecordsScreen(dispatcherInfo: dispatcherInfo)),
                  );
                } else if (choice == 'dispatch') {
                  if (!mounted) return;
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Confirm Dispatch'),
                      content: const Text('Finalize current trip and prepare for new trip? This will reset current trip counts.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    // Capture conductor uid before clearing
                    final prevConductor = AppState.instance.conductor;
                    final prevUid = prevConductor?['uid']?.toString();

                    // Finalize current trip and start a fresh trip with vehicleNo
                    final oldTrip = LocalStorage.getCurrentTripId();
                    await LocalStorage.finalizeTrip(oldTrip);
                    final assignedBus = await DeviceConfigService.getAssignedBus();
                    await LocalStorage.startNewTrip(vehicleNo: assignedBus);
                    if (assignedBus != null) {
                      await LocalStorage.setCurrentVehicleNo(assignedBus);
                    }

                    // Clear in-memory bookings and remove persisted bookings for previous conductor
                    try {
                      BookingManager().clearBookings();
                      if (prevUid != null && prevUid.isNotEmpty) {
                        await LocalStorage.deleteBookingsForConductor(prevUid);
                      }
                    } catch (_) {}

                    // Clear current conductor/driver session
                    await LocalStorage.clearCurrentConductor();
                    await LocalStorage.clearCurrentDriver();
                    AppState.instance.clearSession();

                    if (!mounted) return;

                    if (!mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dispatcher', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    Text(widget.tripInfo['dispatcher'] ?? 'Not assigned', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 2x2 Stats grid (compact)
            SizedBox(
              height: panelH * 2 + 8,
              child: Column(
                children: [
                  SizedBox(
                    height: panelH,
                    child: Row(
                      children: [
                        Expanded(
                          child: Card(
                            color: Colors.green[50],
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Walk-in Tickets', style: TextStyle(color: Colors.green[800], fontSize: 9)),
                                  const SizedBox(height: 4),
                                  Text(walkInTickets.toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Card(
                            color: Colors.green[50],
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Booking Tickets', style: TextStyle(color: Colors.green[800], fontSize: 9)),
                                  const SizedBox(height: 4),
                                  Text(bookingTickets.toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: panelH,
                    child: Row(
                      children: [
                        Expanded(
                          child: Card(
                            color: Colors.green[50],
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('All Tickets', style: TextStyle(color: Colors.green[800], fontSize: 9)),
                                  const SizedBox(height: 4),
                                  Text(allTickets.toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Card(
                            color: Colors.green[50],
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Inspections Made', style: TextStyle(color: Colors.green[800], fontSize: 9)),
                                  const SizedBox(height: 4),
                                  Text(inspectionsMade.toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.yellow[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  ticketMode,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                ),
              ),
            ),

            const SizedBox(height: 12),
            if (LocalStorage.isManualMode()) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                child: const Text('--- SWITCHED TO MANUAL ---', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              ),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final ok = await _printArrivalReport(context);
                  if (ok && mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const DispatchScreen()),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('PRINT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _printArrivalReport(BuildContext context) async {
    try {
      final now = DateTime.now();
      final timeOfDay = TimeOfDay.now();
      // Ensure we use normalized route value when printing and saving
      final routeValue = (widget.tripInfo['route'] ?? '').toString().toLowerCase();

      // Separate walk-in and booking passengers
      final walkInPassengers = widget.bookings.where((b) => b.passengerUid == null).toList();
      final bookingOnlyPassengers = widget.bookings.where((b) => b.passengerUid != null).toList();
      final allPassengers = widget.bookings.toList();
      
      debugPrint('[ARRIVAL-REPORT] Total bookings: ${widget.bookings.length}');
      debugPrint('[ARRIVAL-REPORT] Walk-in passengers: ${walkInPassengers.length}');
      debugPrint('[ARRIVAL-REPORT] Booking-only passengers: ${bookingOnlyPassengers.length}');
      for (final b in widget.bookings) {
        debugPrint('[ARRIVAL-REPORT] Booking: ${b.passengerName} (uid: ${b.passengerUid}, type: ${b.passengerType}, amount: ${b.amount})');
      }

      // Group walk-in bookings by type (for listing) and compute overall ticket-type counts
      final fullFareBookings = walkInPassengers.where((b) => b.passengerType == 'REGULAR').toList();
      final studentBookings = walkInPassengers.where((b) => b.passengerType == 'STUDENT').toList();
      final seniorBookings = walkInPassengers.where((b) => b.passengerType == 'SENIOR').toList();
      final pwdBookings = walkInPassengers.where((b) => b.passengerType == 'PWD').toList();
      final baggageBookings = walkInPassengers.where((b) => b.passengerType == 'BAGGAGE').toList();

      // Ticket-type counts should include both bookings and walk-ins
      final fullFareCount = allPassengers.where((b) => b.passengerType == 'REGULAR').length;
      final studentCount = allPassengers.where((b) => b.passengerType == 'STUDENT').length;
      final seniorCount = allPassengers.where((b) => b.passengerType == 'SENIOR').length;
      final pwdCount = allPassengers.where((b) => b.passengerType == 'PWD').length;
      final baggageCount = allPassengers.where((b) => b.passengerType == 'BAGGAGE').length;

      // Calculate totals
      double fullFareSales = fullFareBookings.fold(0, (sum, b) => sum + b.amount);
      double studentSales = studentBookings.fold(0, (sum, b) => sum + b.amount);
      double seniorSales = seniorBookings.fold(0, (sum, b) => sum + b.amount);
      double pwdSales = pwdBookings.fold(0, (sum, b) => sum + b.amount);
      double baggageSales = baggageBookings.fold(0, (sum, b) => sum + b.amount);

      double cashSales = fullFareSales + studentSales + seniorSales + pwdSales + baggageSales;
      double totalBookingSales = bookingOnlyPassengers.fold(0, (sum, b) => sum + b.amount);

      // Build report using table printing for alignment
      await _printer.setAlignment(1);
      await _printer.setTextBold(true);
      await _printer.setTextSize(28);
      await _printer.printText('BATMAN STAREXPRESS\n');
      await _printer.printText('ARRIVAL REPORT\n');
      await _printer.nextLine(1);

      await _printer.setTextSize(20);
      await _printer.setTextBold(false);
      await _printer.setAlignment(0);

      // Key/value header block
      await _printer.printTableText(['Opening', 'REF-0001'], [6,4], [0,2]);
      await _printer.printTableText(['Closing', 'REF-0001'], [6,4], [0,2]);
      await _printer.printTableText(['DATE', now.toLocal().toString().split(' ')[0]], [6,4], [0,2]);
      await _printer.printTableText(['TIME', timeOfDay.format(context)], [6,4], [0,2]);
      // Use trip ID for printed reports - right column, single-row table; reduce size to avoid wrapping
      await _printer.setTextSize(18);
      await _printer.setTextBold(true);
      await _printer.printTableText(['TRIP ID', LocalStorage.getCurrentTripId()], [4,6], [0,2]);
      await _printer.setTextBold(false);
      await _printer.setTextSize(20);
      await _printer.printTableText(['VEHICLE NO.', widget.tripInfo['vehicleNo']!], [6,4], [0,2]);

      await _printer.nextLine(1);
      await _printer.setAlignment(1);
      await _printer.setTextBold(true);
          await _printer.printText('$routeValue\n');
      await _printer.setTextBold(false);
      await _printer.printText('${widget.tripInfo['route']}\n');
      await _printer.nextLine(1);

      await _printer.setAlignment(0);
      await _printer.printTableText(['DRIV NAME', widget.tripInfo['driver']!], [6,4], [0,2]);
      await _printer.printTableText(['COND NAME', widget.tripInfo['conductor']!], [6,4], [0,2]);
      await _printer.printTableText(['DISP NAME', widget.tripInfo['dispatcher']!], [6,4], [0,2]);
      
      // Count total tickets across all bookings
      final totalTickets = widget.bookings.length;
      await _printer.printTableText(['NO. OF TICKETS', totalTickets.toString()], [6,4], [0,2]);
      await _printer.nextLine(1);

      // Ticket counts per type
      await _printer.setTextBold(true);
      await _printer.setAlignment(1);
      await _printer.printText('TICKET TYPE COUNT\n');
      await _printer.setAlignment(0);
      await _printer.setTextBold(false);
      // Use combined counts (bookings + walk-ins)
      await _printer.printTableText(['Full Fare', fullFareCount.toString()], [6,4], [0,2]);
      await _printer.printTableText(['Student', studentCount.toString()], [6,4], [0,2]);
      await _printer.printTableText(['Senior Citizen', seniorCount.toString()], [6,4], [0,2]);
      await _printer.printTableText(['PWD', pwdCount.toString()], [6,4], [0,2]);
      await _printer.printTableText(['Baggage', baggageCount.toString()], [6,4], [0,2]);
      await _printer.nextLine(1);

      // Global counters for walk-in and booking ticket numbering
      int walkinCounter = 1;
      int bookingCounter = 1;

      // Helper to print lists in aligned columns with compact layout
      Future<void> printList(String title, List<Booking> list, {required bool isBooking}) async {
        if (list.isEmpty) return;
        await _printer.setTextBold(true);
        await _printer.setAlignment(1);
        await _printer.printText('$title\n');
        await _printer.setAlignment(0);
        await _printer.setTextBold(false);
        // Column widths: Tkt#=2, Time=3, From=3, To=3, Amt=3
        // Alignment: Tkt# left, Time center, From center, To center, Amt center
        await _printer.printTableText(['Tkt#','Time','From','To','Amt'], [2,3,3,3,3], [0,1,1,1,1]);
        for (var b in list) {
          // Use km-only values for From/To columns (e.g., "0", "70").
          // Fallback to empty string when km cannot be resolved.
          final fromPlace = FareTable.getKmString(b.fromLocation);
          final toPlace = FareTable.getKmString(b.toLocation);
          // Format amount without .00 if whole number
          final amtDisplay = b.amount % 1 == 0 
            ? b.amount.toInt().toString() 
            : b.amount.toStringAsFixed(2);

          // Ticket numbering: W### for walk-ins, B### for bookings
          final tktLabel = isBooking
            ? 'B${bookingCounter.toString().padLeft(3, '0')}'
            : 'W${walkinCounter.toString().padLeft(3, '0')}';

          await _printer.printTableText([
            tktLabel,
            b.time,
            fromPlace,
            toPlace,
            amtDisplay
          ], [2,3,3,3,3], [0,1,1,1,1]);

          if (isBooking) {
            bookingCounter++;
          } else {
            walkinCounter++;
          }
        }
        await _printer.nextLine(1);
      }

      // Print walk-in groups using WALK-IN title
      await printList('WALK-IN', fullFareBookings, isBooking: false);
      await printList('STUDENT', studentBookings, isBooking: false);
      await printList('SENIOR CITIZEN', seniorBookings, isBooking: false);
      await printList('PWD', pwdBookings, isBooking: false);
      await printList('BAGGAGE', baggageBookings, isBooking: false);
      // Booking tickets use bookingCounter labeling
      await printList('BOOKING', bookingOnlyPassengers, isBooking: true);

      // Sales summary
      await _printer.setTextBold(true);
      await _printer.printTableText(['CASH SALES', cashSales.toStringAsFixed(2)], [6,4], [0,2]);
      await _printer.printTableText(['BOOKING SALES', totalBookingSales.toStringAsFixed(2)], [6,4], [0,2]);
      await _printer.nextLine(1);
      await _printer.printTableText(['TOTAL CASH SALES', cashSales.toStringAsFixed(2)], [6,4], [0,2]);
      await _printer.printTableText(['TOTAL BOOKING SALES', totalBookingSales.toStringAsFixed(2)], [6,4], [0,2]);
      await _printer.nextLine(3);
      // If manual mode was enabled, print a centered marker for auditors at bottom
      if (LocalStorage.isManualMode()) {
        await _printer.setAlignment(1);
        await _printer.setTextBold(true);
        await _printer.printText('--- SWITCHED TO MANUAL ---\n');
        await _printer.setTextBold(false);
        await _printer.setAlignment(0);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report printed successfully')));
      }

      // Build arrival report payload for Firestore
      try {
        final tripId = LocalStorage.getCurrentTripId();
        final nowIso = DateTime.now().toIso8601String();

        // Compute summary
        final totalPassengers = widget.bookings.length;
        final totalBookingSales = widget.bookings.where((b) => b.passengerUid != null).fold(0.0, (s, b) => s + b.amount);
        final totalCashSales = widget.bookings.where((b) => b.passengerUid == null).fold(0.0, (s, b) => s + b.amount);
        final totalAmount = totalBookingSales + totalCashSales;

        final assignedBus = await DeviceConfigService.getAssignedBus();
        final ids = await DeviceIdentifierService.getDeviceIdentifiers();
        final androidId = ids?['androidId'];
        
        // Use assignedBus if available, otherwise try to map from Android ID
        final busNumber = assignedBus ?? LocalStorage.getBusNumberFromAndroidId(androidId);

        // Load and transform walk-ins and bookings to use ticket numbers
        final walkinsRaw = LocalStorage.loadWalkinsForTrip(tripId);
        final bookingsRaw = LocalStorage.loadBookingsForTrip(tripId);
        
        // Transform walk-ins: replace 'id' with 'walkinId' and use W### format
        int walkinCounter = 1;
        final walkins = walkinsRaw.map((w) {
          final transformed = Map<String, dynamic>.from(w);
          transformed.remove('id'); // Remove old id field
          transformed['walkinId'] = 'W${walkinCounter.toString().padLeft(3, '0')}';
          walkinCounter++;
          return transformed;
        }).toList();
        
        // Transform bookings: replace 'id' with 'bookingId' and use B### format
        int bookingCounter = 1;
        final bookings = bookingsRaw.map((b) {
          final transformed = Map<String, dynamic>.from(b);
          transformed.remove('id'); // Remove old id field
          transformed['bookingId'] = 'B${bookingCounter.toString().padLeft(3, '0')}';
          bookingCounter++;
          return transformed;
        }).toList();

        final report = {
          'tripId': tripId,
          'reportedAt': nowIso,
          'summary': {
            'totalPassengers': totalPassengers,
            'totalAmount': totalAmount,
            'totalCashSales': totalCashSales,
            'totalBookingSales': totalBookingSales,
            'inspectionsCount': widget.inspections.length,
            'bookingCount': widget.bookings.where((b) => b.passengerUid != null).length,
            'walkInCount': widget.bookings.where((b) => b.passengerUid == null).length,
            'totalTickets': widget.bookings.length,
          },
          'manualMode': LocalStorage.isManualMode(),
          'walkins': walkins,
          'bookings': bookings,
          'inspections': widget.inspections,
          'conductor': {'name': widget.tripInfo['conductor'] ?? ''},
          'driver': {'name': widget.tripInfo['driver'] ?? ''},
          'dispatcher': {'name': widget.tripInfo['dispatcher'] ?? ''},
          'vehicleNo': widget.tripInfo['vehicleNo'] ?? 'Unknown',
          'busNumber': busNumber,
          'route': widget.tripInfo['route'] ?? '',
          'androidId': androidId,
          // Let Cloud Function set server timestamps for createdAt/syncedAt if available.
        };

        // Check connectivity before attempting Firestore write
        final conn = await Connectivity().checkConnectivity();
        if (conn == ConnectivityResult.none) {
          // Save to pending Hive box for later sync
          final box = await Hive.openBox('arrival_reports_pending');
          await box.put(tripId, report);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline: report saved locally and will sync when online')));
        } else {
          // Attempt Firestore upload
          final col = FirebaseFirestore.instance.collection('arrivalReports');
          await col.doc(report['tripId'] as String).set({
            ...report,
            'createdAt': FieldValue.serverTimestamp(),
            'syncedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          // Delete bookings from local storage after successful sync
          await LocalStorage.deleteBookingsForTrip(tripId);

          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arrival report uploaded')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload report: $e')));
      }

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
      return false;
    }
  }
}
