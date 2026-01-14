import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/booking.dart';
import '../services/app_state.dart';
import '../services/nfc_reader_mode_service.dart';
import '../local_storage.dart';
import 'arrival_report_screen.dart';
import '../widgets/internet_connectivity_dialog.dart';

class RecordsScreen extends StatefulWidget {
  final Map<String, dynamic>? dispatcherInfo;
  final String? routeDirection;

  const RecordsScreen({super.key, this.dispatcherInfo, this.routeDirection});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final BookingManager _bookingManager = BookingManager();

  Map<String, dynamic> _tripInfo = {};
  Map<String, dynamic> stats = {'totalPassengers': 0, 'totalCashSales': 0.0, 'totalBookingSales': 0.0};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    // If no driver is registered yet, prompt for driver tap when opening this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final driver = AppState.instance.driver;
      if (driver == null) {
        _promptForDriverTap();
      }
    });
  }

  Future<void> _promptForDriverTap() async {
    // Don't start reader mode here - use the existing one from HomeScreen
    // NFCReaderModeService is a singleton and is already running
    // Trying to start it again causes race conditions

    StreamSubscription? sub;
    final completer = Completer<void>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // subscribe when dialog built
        sub ??= NFCReaderModeService.instance.onTag.listen((user) async {
          final role = (user['role'] ?? '').toString().toLowerCase();
          if (role == 'driver') {
            // Register driver in global AppState
            AppState.instance.setDriver(user);
            // Update UI
            _loadInitialData();
            try { await sub?.cancel(); } catch (_) {}
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            if (!completer.isCompleted) completer.complete();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Card tapped is not a driver (role=$role). Please tap driver card.')),
            );
          }
        });

        return AlertDialog(
          title: const Text('Driver required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('Please ask the driver to tap their ID on the device to continue.'),
              SizedBox(height: 12),
              CircularProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try { await sub?.cancel(); } catch (_) {}
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                if (!completer.isCompleted) completer.complete();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    // Timeout to auto-close dialog after 30s
    Future.delayed(const Duration(seconds: 30)).then((_) async {
      if (!completer.isCompleted) {
        try { await sub?.cancel(); } catch (_) {}
        try { if (Navigator.canPop(context)) Navigator.pop(context); } catch (_) {}
        completer.complete();
      }
    });

    await completer.future;
    // Don't stop reader mode - it's still needed by the parent screen (HomeScreen)
  }

  void _loadInitialData() {
    final conductor = AppState.instance.conductor;
    final driver = AppState.instance.driver;
    String normalizeRoute(String? r) {
      if (r == null) return 'unknown';
      final lr = r.toString().toLowerCase().trim();
      if (lr.startsWith('n')) return 'north';
      if (lr.startsWith('s')) return 'south';
      return 'unknown';
    }

    _tripInfo = {
      'tripNo': LocalStorage.getCurrentTripId(),
      'vehicleNo': LocalStorage.getCurrentVehicleNo(),
      'conductor': conductor?['name'] ?? 'Unknown',
      'driver': driver?['name'] ?? 'Unknown',
      'dispatcher': widget.dispatcherInfo?['name'] ?? 'Unknown',
      'route': normalizeRoute(widget.routeDirection),
    };

    final bookings = _bookingManager.getBookings().toList();
    final walkins = LocalStorage.loadWalkinsForTrip(LocalStorage.getCurrentTripId());

    final int totalPassengersFromBookings = bookings.fold(0, (s, b) => s + (b.passengers));
    final int totalPassengersFromWalkins = walkins.fold(0, (s, w) => s + ((w['passengers'] as int?) ?? 1));

    final double cashFromBookingsWalkins = bookings.where((b) => b.passengerUid == null).fold(0.0, (s, b) => s + b.amount) +
        walkins.fold(0.0, (s, w) {
      final amt = w['amount'];
      if (amt is num) return s + amt.toDouble();
      return s + (double.tryParse(amt?.toString() ?? '0') ?? 0.0);
    });

    final double bookingSales = bookings.where((b) => b.passengerUid != null).fold(0.0, (s, b) => s + b.amount);

    stats = {
      'totalPassengers': totalPassengersFromBookings + totalPassengersFromWalkins,
      'totalCashSales': cashFromBookingsWalkins,
      'totalBookingSales': bookingSales,
    };

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text('RECORDS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('SUMMARY'),
                  SizedBox(height: screenH * 0.01),
                  _buildKeyValueRow('Opening', 'REF-0001', screenW),
                  _buildKeyValueRow('Closing', 'REF-0001', screenW),
                  _buildKeyValueRow('Total Passenger', stats['totalPassengers'].toString(), screenW),
                  _buildKeyValueRow('Total Cash Sales', '₱${(stats['totalCashSales'] as double).toStringAsFixed(2)}', screenW),
                  _buildKeyValueRow('Total Booking Sales', '₱${(stats['totalBookingSales'] as double).toStringAsFixed(2)}', screenW),

                  SizedBox(height: screenH * 0.01),
                  const Divider(thickness: 1.2),
                  SizedBox(height: screenH * 0.01),

                  _buildSectionHeader('TRIP INFORMATION'),
                  SizedBox(height: screenH * 0.01),
                  _buildKeyValueRow('TRIP NO.', _tripInfo['tripNo'] ?? '', screenW),
                  _buildKeyValueRow('VEHICLE NO.', _tripInfo['vehicleNo'] ?? '', screenW),
                  _buildKeyValueRow('Conductor', _tripInfo['conductor'] ?? '', screenW),
                  _buildKeyValueRow('Driver', _tripInfo['driver'] ?? '', screenW),
                  _buildKeyValueRow('Dispatcher', _tripInfo['dispatcher'] ?? '', screenW),
                  _buildKeyValueRow('Route', _tripInfo['route'] ?? '', screenW),
                  _buildKeyValueRow('No. of Inspections made', LocalStorage.loadInspectionsForTrip(LocalStorage.getCurrentTripId()).length.toString(), screenW),

                  if (LocalStorage.isManualMode()) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      child: const Text('--- SWITCHED TO MANUAL ---', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Bottom buttons
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text(
                              'BACK',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: screenW * 0.03),
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () async {
                              // Check if already connected to internet
                              final connectivity = Connectivity();
                              final conn = await connectivity.checkConnectivity();
                              
                              // If already connected, proceed directly; otherwise show dialog
                              bool isConnected = conn != ConnectivityResult.none;
                              if (!isConnected) {
                                // Show internet connectivity dialog
                                final result = await showDialog<bool>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const InternetConnectivityDialog(),
                                );
                                isConnected = result == true;
                              }

                              // Only proceed to arrival report if connected
                              if (!isConnected) return;

                              // Navigate to arrival report screen
                              final tripId = LocalStorage.getCurrentTripId();
                              // Load ONLY bookings for this trip (from LocalStorage)
                              final bookingsForTrip = LocalStorage.loadBookingsForTrip(tripId);
                              debugPrint('[RECORDS] Loaded ${bookingsForTrip.length} bookings for trip $tripId');
                              for (final b in bookingsForTrip) {
                                debugPrint('[RECORDS] Booking: ${b['passengerName']} (uid: ${b['passengerUid']}, amount: ${b['amount']})');
                              }
                              var bookings = <Booking>[];
                              for (final b in bookingsForTrip) {
                                bookings.add(Booking(
                                  id: b['id'] ?? '',
                                  passengerName: b['passengerName'] ?? 'Booking',
                                  route: b['route'] ?? '',
                                  date: b['date'] ?? '',
                                  time: b['time'] ?? '',
                                  passengers: b['passengers'] ?? 1,
                                  fromLocation: b['fromLocation'] ?? '',
                                  toLocation: b['toLocation'] ?? '',
                                  passengerType: b['passengerType'] ?? 'REGULAR',
                                  amount: (b['amount'] is num) ? (b['amount'] as num).toDouble() : double.tryParse(b['amount']?.toString() ?? '0') ?? 0.0,
                                  status: b['status'] ?? 'on-board',
                                  passengerUid: b['passengerUid'],
                                ));
                              }
                              // Add walk-in data from walkins box (current trip only)
                              final walkins = LocalStorage.loadWalkinsForTrip(tripId);
                              for (final walkin in walkins) {
                                final booking = Booking(
                                  id: walkin['id'] ?? '',
                                  passengerName: walkin['passengerName'] ?? 'Walk-in',
                                  route: walkin['route'] ?? '',
                                  date: walkin['date'] ?? '',
                                  time: walkin['time'] ?? '',
                                  passengers: walkin['passengers'] ?? 1,
                                  fromLocation: walkin['fromLocation'] ?? '',
                                  toLocation: walkin['toLocation'] ?? '',
                                  passengerType: walkin['passengerType'] ?? 'REGULAR',
                                  amount: (walkin['amount'] is num) ? (walkin['amount'] as num).toDouble() : double.tryParse(walkin['amount']?.toString() ?? '0') ?? 0.0,
                                  status: 'on-board',
                                  passengerUid: null,
                                );
                                bookings.add(booking);
                              }
                              // Load ONLY scanned tickets for this trip
                              final scannedTickets = LocalStorage.loadScannedTicketsForTrip(tripId);
                              final inspections = LocalStorage.loadInspectionsForTrip(tripId);
                              
                              if (!mounted) return;
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArrivalReportScreen(
                                    tripInfo: _tripInfo.map((k, v) => MapEntry(k, v?.toString() ?? '')),
                                    bookings: bookings,
                                    scannedTickets: scannedTickets,
                                    inspections: inspections,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text(
                              'ARRIVE',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildKeyValueRow(String label, String value, double screenW) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: screenW * 0.01),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[800]),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
