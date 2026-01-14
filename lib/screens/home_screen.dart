import 'dart:async';
import 'package:flutter/material.dart';
import 'profile_screen.dart';
import 'bookings_screen.dart';
import 'records_screen.dart';
import 'package:senraise_printer/senraise_printer.dart';
import 'package:untitled/screens/qr_scanner_screen.dart';
import 'passengers_screen.dart';
import 'package:untitled/utils/fare_calculator.dart';
import 'package:untitled/utils/stops.dart';
import '../services/app_state.dart';
import '../services/device_config_service.dart';
import '../services/nfc_reader_mode_service.dart';
import '../local_storage.dart';
import '../main.dart' show navigatorKey;

class HomeScreen extends StatefulWidget {
  final String? routeDirection; // 'forward' or 'reverse'
  final Map<String, dynamic>? conductor; // Logged-in conductor info

  const HomeScreen({super.key, this.routeDirection, this.conductor});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late String fromLocation;
  late String toLocation;
  late String routeDirection; // 'forward' or 'reverse'
  late List<String> availableStops;

  @override
  void initState() {
    super.initState();
    routeDirection = widget.routeDirection ?? 'north_to_south';
    availableStops = List.from(fareTableStops);
    
    // Set from/to locations based on route direction
    if (routeDirection == 'north_to_south') {
      // North: Nasugbu → Batangas Terminal (start from Nasugbu, go up to Batangas)
      fromLocation = availableStops.first; // Nasugbu
      toLocation = availableStops.last;    // Batangas Terminal
    } else {
      // South: Batangas Terminal → Nasugbu (start from Batangas, go down to Nasugbu)
      fromLocation = availableStops.last;  // Batangas Terminal (but this is index 0 conceptually for south route)
      toLocation = availableStops.first;   // Nasugbu
    }

    // Detect assigned bus for this device (BUS-001 / BUS-002)
    DeviceConfigService.getAssignedBus().then((bus) async {
      bus ??= await DeviceConfigService.autoDetectAndSaveAssignedBus();
      if (mounted) setState(() => _assignedBus = bus);
    });
  }

  String? _assignedBus;

  String passengerType = 'REGULAR';

  final List<String> passengerTypes = [
    'REGULAR',
    'STUDENT',
    'BAGGAGE',
    'CHILD',
    'SENIOR',
    'PWD',
  ];

  /// Get valid "From" stops based on route direction
  /// For north_to_south: Nasugbu → Batangas (normal order)
  /// For south_to_north: Batangas → Nasugbu (reversed order, Bolbok at top)
  List<String> getValidFromStops() {
    if (routeDirection == 'north_to_south') {
      return availableStops;
    } else {
      // Reverse order: Bolbok at top, Nasugbu at bottom
      return List.from(availableStops.reversed);
    }
  }

  // Get valid "To" stops based on current "From" stop and route direction
  // Destination always shows next place after origin, going toward Nasugbu
  List<String> getValidToStops() {
    int fromIndex = availableStops.indexOf(fromLocation);
    if (fromIndex == -1) return [];
    
    if (routeDirection == 'north_to_south') {
      // Nasugbu → Batangas: return stops after the "From" stop (going up toward Batangas)
      return availableStops.sublist(fromIndex + 1);
    } else {
      // Batangas → Nasugbu: return stops before the "From" stop (going down toward Nasugbu)
      // But display them in reverse order so it reads naturally from origin toward destination
      final stopsBeforeOrigin = availableStops.sublist(0, fromIndex);
      return List.from(stopsBeforeOrigin.reversed);
    }
  }

  // Get current route display string
  String getRouteDisplay() {
    return '$fromLocation → $toLocation';
  }

  double get fare {
    final originPlace = FareTable.extractPlaceName(fromLocation);
    final destPlace = FareTable.extractPlaceName(toLocation);
    return FareCalculator.calculateFare(
      origin: originPlace,
      destination: destPlace,
      passengerType: passengerType,
      quantity: 1,
    ).toDouble();
  }

  int quantity = 1;

  final SenraisePrinter printer = SenraisePrinter();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;

    final double vpadSmall = screenH * 0.01;
    final double vpad = screenH * 0.02;
    final double headerHeight = screenH * 0.08;

    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: _buildDrawer(screenW, context),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: screenW * 0.03, vertical: vpadSmall),
          child: SingleChildScrollView(            // ⬅⬅⬅ FIXED
            child: Column(
              children: [
                _buildHeader(screenW, headerHeight),
                SizedBox(height: vpadSmall * 2),

                _buildLocationSelector(
                  label: "FROM",
                  value: fromLocation,
                  options: getValidFromStops(),
                  onChanged: (v) => setState(() {
                    fromLocation = v;
                    // Always reset "To" to the first valid destination
                    List<String> validTo = getValidToStops();
                    toLocation = validTo.isNotEmpty ? validTo.first : '';
                  }),
                ),

                SizedBox(height: vpadSmall),

                _buildLocationSelector(
                  label: "TO",
                  value: toLocation,
                  options: getValidToStops(),
                  onChanged: (v) => setState(() => toLocation = v),
                ),

                SizedBox(height: vpad),

                _buildPassengerTypeSelector(screenW),

                SizedBox(height: vpadSmall * 2),

                _buildQrPopupButton(screenH, screenW, context),

                SizedBox(height: vpadSmall),

                _buildScanTicketButton(screenH, context),

                SizedBox(height: vpadSmall * 2),

                _buildQuantityAndTotal(screenW),

                const SizedBox(height: 17),

                _buildPrintButton(screenH),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Drawer Menu
  Drawer _buildDrawer(double screenW, BuildContext context) {
    return Drawer(
      width: screenW * 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.green[700],
            padding: const EdgeInsets.all(20),
            child: const Text(
              "MENU",
              style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            title: const Text("PROFILE"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(routeInfo: getRouteDisplay(), conductor: widget.conductor)));
            },
          ),
          ListTile(
            title: const Text("TICKET"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => HomeScreen(routeDirection: routeDirection, conductor: widget.conductor)),
              );
            },
          ),
          ListTile(
            title: const Text("BOOKINGS"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BookingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            title: const Text("PASSENGERS"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PassengersScreen(routeDirection: routeDirection),
                ),
              );
            },
          ),
          ListTile(
            title: const Text("RECORDS"),
            onTap: () {
              Navigator.pop(context);
              _showDispatcherAuthDialog(context);
            },
          ),
        ],
      ),
    );
  }

  /// Header UI
  Widget _buildHeader(double screenW, double headerHeight) {
    return SizedBox(
      height: headerHeight,
      child: Row(
        children: [
          Container(
            width: screenW * 0.67,
            height: headerHeight,
            color: Colors.green[700],
              child: Center(
              child: Text(
                'Batman Starexpress ${_assignedBus ?? 'AFCS 1'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const Spacer(),
          Builder(builder: (context) {
            return GestureDetector(
              onTap: () => Scaffold.of(context).openEndDrawer(),
              child: Container(
                width: screenW * 0.25,
                height: headerHeight,
                color: Colors.green[700],
                child: const Center(
                  child: Text(
                    'MENU',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Passenger Type UI
  Widget _buildPassengerTypeSelector(double screenW) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('PASSENGER TYPE:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        Container(
          width: screenW * 0.45,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black54),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButton<String>(
            isExpanded: true,
            underline: const SizedBox(),
            value: passengerType,
            items: passengerTypes
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (value) => setState(() => passengerType = value!),
          ),
        ),
      ],
    );
  }



  /// QR Popup Button
  Widget _buildQrPopupButton(
      double screenH, double screenW, BuildContext context) {
    return GestureDetector(
      onTap: () => _showQrPopup(context),
      child: Container(
        height: screenH * 0.16,
        width: screenW * 0.6,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Text(
            'TAP TO VIEW QR',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  /// QR Popup
  void _showQrPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            height: 300,
            width: 300,
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  "QR HERE",
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// SCAN TICKET Button
  Widget _buildScanTicketButton(double screenH, BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: screenH * 0.060,
      child: ElevatedButton(
        onPressed: () async {
          if (LocalStorage.isManualMode()) {
            showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Manual Mode'), content: const Text('Device is in manual ticketing mode. Scanning is disabled.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
            return;
          }
          
          // Check if driver is registered; if not, prompt for driver tap
          final driver = AppState.instance.driver;
          if (driver == null) {
            final driverTapped = await _promptForDriverTap();
            if (!driverTapped) return; // User cancelled
          }
          
          // Get conductor and driver names from AppState
          final conductorName = AppState.instance.conductor?['name'] ?? 'Unknown';
          final driverName = AppState.instance.driver?['name'] ?? 'Unknown';

          final result = await Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (_) => QrScannerScreen(
                routeDirection: routeDirection,
                conductorName: conductorName,
                driverName: driverName,
              ),
            ),
          );

          if (result != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Transaction $result completed')),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green[700],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: const Text('SCAN TICKET',
            style: TextStyle(fontSize: 18, color: Colors.white)),
      ),
    );
  }

  /// Prompt for driver tap before scanning; returns true if driver tapped, false if cancelled
  Future<bool> _promptForDriverTap() async {
    // Ensure reader mode is active
    try {
      await NFCReaderModeService.instance.start();
    } catch (_) {}

    StreamSubscription? sub;
    final completer = Completer<bool>();

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
            try { await sub?.cancel(); } catch (_) {}
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            if (!completer.isCompleted) completer.complete(true);
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
              Text('Please ask the driver to tap their ID on the device to continue scanning.'),
              SizedBox(height: 12),
              CircularProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try { await sub?.cancel(); } catch (_) {}
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                if (!completer.isCompleted) completer.complete(false);
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
        completer.complete(false);
      }
    });

    final result = await completer.future;
    // stop reader mode if no longer needed
    try { await NFCReaderModeService.instance.stop(); } catch (_) {}
    return result;
  }

  /// Quantity + Total section
  Widget _buildQuantityAndTotal(double screenW) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('QUANTITY', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              width: screenW * 0.35,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black54),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButton<int>(
                isExpanded: true,
                underline: const SizedBox(),
                value: quantity,
                items: List.generate(
                  20,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text("${i + 1}")),
                ),
                onChanged: (value) => setState(() => quantity = value!),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('TOTAL AMOUNT',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              (fare * quantity).toStringAsFixed(2),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  /// Print button
  Widget _buildPrintButton(double screenH) {
    return SizedBox(
      width: double.infinity,
      height: screenH * 0.065,
      child: ElevatedButton(
        onPressed: () async {
          if (LocalStorage.isManualMode()) {
            showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Manual Mode'), content: const Text('Device is in manual ticketing mode. Printing is disabled.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
            return;
          }
          final now = DateTime.now();
          final date =
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
          final time =
              "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

          final totalAmount = (fare * quantity).toStringAsFixed(2);
          
          // Extract place names from formatted strings (km|Place)
          final originPlace = FareTable.extractPlaceName(fromLocation);
          final destPlace = FareTable.extractPlaceName(toLocation);

          // Get route display (just "North" or "South")
            String routeDisplay = (routeDirection == 'north_to_south')
              ? 'North'
              : (routeDirection == 'south_to_north')
                ? 'South'
                : 'Unknown';

          // Calculate distance based on origin and destination
          String distance = _calculateDistance(originPlace, destPlace);

          // Get conductor name from AppState (logged-in conductor)
          final conductorName = AppState.instance.conductor?['name'] ?? 'Unknown Conductor';
          
          // Require driver tapped in for printing
          final driver = AppState.instance.driver;
          if (driver == null) {
            // Notify user that driver must tap in
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('No Driver'),
                content: const Text('No driver has tapped in. Please have the driver tap their card to proceed.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                ],
              ),
            );
            return;
          }
          final driverName = driver['name'] ?? 'Unknown Driver';

          debugPrint('[RECEIPT] Conductor: $conductorName');
          debugPrint('[RECEIPT] Driver: $driverName');
          debugPrint('[RECEIPT] Route: $routeDisplay');
          debugPrint('[RECEIPT] Distance: $distance km');
          debugPrint('[RECEIPT] From: $originPlace, To: $destPlace');

          await printer.printReceipt(
            vehicleNo: "BUS-002",
            date: date,
            time: time,
            from: originPlace,
            to: destPlace,
            distance: distance,
            passengerType: passengerType,
            driverName: driverName,
            conductorName: conductorName,
            payment: "CASH",
            amount: totalAmount,
            route: routeDisplay,
          );

          // Create walk-in record and persist to dedicated walkins storage
          final amountDouble = double.parse(totalAmount);
          final walkinRecord = {
            'id': 'WI${DateTime.now().millisecondsSinceEpoch}',
            'passengerName': 'Walk-in Passenger',
            'route': '$originPlace - $destPlace',
            'date': date,
            'time': time,
            'passengers': quantity,
            'fromLocation': originPlace,
            'toLocation': destPlace,
            'passengerType': passengerType,
            'amount': amountDouble,
            'source': 'walkin',
          };
          try {
            await LocalStorage.saveWalkin(walkinRecord);
          } catch (e) {
            debugPrint('[HomeScreen] Failed saving walkin: $e');
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green[700],
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text(
          'PRINT',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  /// Calculate distance based on origin and destination
  String _calculateDistance(String origin, String destination) {
    // Get the km values from the FareTable for each place
    final originEntry = FareTable.getEntryByPlace(origin);
    final destEntry = FareTable.getEntryByPlace(destination);
    
    if (originEntry != null && destEntry != null) {
      final kmTraveled = (originEntry.km - destEntry.km).abs();
      debugPrint('[DISTANCE] $origin (${originEntry.km}km) -> $destination (${destEntry.km}km) = ${kmTraveled}km');
      return kmTraveled.toString();
    }
    
    debugPrint('[DISTANCE] Could not find entries for $origin or $destination');
    return '0';
  }


  /// Location Selector
  Widget _buildLocationSelector({
    required String label,
    required String value,
    required List<String> options,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black54),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Builder(builder: (_) {
            final safeValue = options.contains(value) ? value : (options.isNotEmpty ? options.first : null);
            if (safeValue == null) {
              return Container(
                height: 40,
                alignment: Alignment.centerLeft,
                child: Text('No available destinations', style: TextStyle(color: Colors.grey[600])),
              );
            }
            return DropdownButton<String>(
              isExpanded: true,
              underline: const SizedBox(),
              value: safeValue,
              items: options
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => onChanged(v!),
            );
          }),
        ),
      ],
    );
  }

  /// Dispatcher Authentication Dialog
  void _showDispatcherAuthDialog(BuildContext context) {
    // Reset NFC debounce so dispatcher card can be read immediately
    NFCReaderModeService.instance.resetDebounce();

    final completer = Completer<void>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        late StreamSubscription<dynamic> nfcSubscription;
        
        // Set up subscription immediately when builder is called
        nfcSubscription = NFCReaderModeService.instance.onTag.listen((data) {
          try {
            String tappedUid = data['uid'] ?? '';
            debugPrint('[DISPATCHER-AUTH] Tag tapped: $tappedUid');
            
            final employee = LocalStorage.getEmployee(tappedUid);
            if (employee != null) {
              debugPrint('[DISPATCHER-AUTH] Card found: ${employee['name']} (role=${employee['role']})');
              if (employee['role'] == 'dispatcher') {
                try { nfcSubscription.cancel(); } catch (_) {}
                if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
                
                // Use global navigator key to avoid context issues
                navigatorKey.currentState?.push(
                  MaterialPageRoute(
                    builder: (_) => RecordsScreen(dispatcherInfo: employee, routeDirection: routeDirection),
                  ),
                );
                if (!completer.isCompleted) completer.complete();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Card is ${employee['role']}, not dispatcher')),
                );
              }
            } else {
              debugPrint('[DISPATCHER-AUTH] Card $tappedUid NOT found');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Dispatcher card not recognized.')),
              );
            }
          } catch (e) {
            debugPrint('[DISPATCHER-AUTH] Error: $e');
          }
        });

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            try { nfcSubscription.cancel(); } catch (_) {}
            if (!completer.isCompleted) completer.complete();
          },
          child: AlertDialog(
            title: const Text('Dispatcher Authentication'),
            content: const Text('Please tap your dispatcher ID card.'),
            actions: [
              TextButton(
                onPressed: () {
                  try { nfcSubscription.cancel(); } catch (_) {}
                  if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
                  if (!completer.isCompleted) completer.complete();
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }
}

