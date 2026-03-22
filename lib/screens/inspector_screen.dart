import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import '../services/nfc_reader_mode_service.dart';
import '../models/inspection.dart';
import '../local_storage.dart';
import '../services/app_state.dart';
import '../models/booking.dart';
import '../utils/fare_calculator.dart';
import '../services/inspection_sync_service.dart';
import '../services/device_config_service.dart';

class InspectorScreen extends StatefulWidget {
  final String
      routeDirection; // 'forward' or 'reverse' (north_to_south or south_to_north)

  const InspectorScreen({super.key, required this.routeDirection});

  @override
  State<InspectorScreen> createState() => _InspectorScreenState();
}

class _InspectorScreenState extends State<InspectorScreen>
    with WidgetsBindingObserver {
  late BookingManager _bookingManager;
  late TextEditingController _manualCountController;
  late TextEditingController _commentsController;
  late TextEditingController _customExplanationController;
  late List<String> stops;
  String? currentLocation;

  bool _isCleared = false;

  String _derivedRouteDirection = 'north_to_south';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bookingManager = BookingManager();
    _manualCountController = TextEditingController();
    _commentsController = TextEditingController();
    _customExplanationController = TextEditingController();

    // Derive direction from routeName if possible
    final routeInfo = LocalStorage.getCurrentRoute();
    if (routeInfo != null && routeInfo['routeName'] != null) {
      _derivedRouteDirection =
          _deriveRouteDirectionFromText(routeInfo['routeName']!);
    } else {
      _derivedRouteDirection = widget.routeDirection.isNotEmpty
          ? widget.routeDirection
          : 'north_to_south';
    }
    _initializeStopsAndLocation();
    _loadBookings();
  }

  String _deriveRouteDirectionFromText(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return 'north_to_south';
    if (text.contains('nasugbu') && text.contains('batangas')) {
      final nasugbuIdx = text.indexOf('nasugbu');
      final batangasIdx = text.indexOf('batangas');
      if (nasugbuIdx < batangasIdx) return 'north_to_south';
      if (batangasIdx < nasugbuIdx) return 'south_to_north';
    }
    if (text.contains('north_to_south') || text.contains('north to south')) {
      return 'north_to_south';
    }
    if (text.contains('south_to_north') || text.contains('south to north')) {
      return 'south_to_north';
    }
    return 'north_to_south';
  }

  void _initializeStopsAndLocation() {
    final forwardStops = FareTable.placeNamesWithKm;
    stops = _derivedRouteDirection == 'north_to_south'
        ? List.from(forwardStops)
        : List.from(forwardStops.reversed);
    currentLocation = 'OVERVIEW';
  }

  List<Booking> _getCombinedBookings() {
    var bookings = _bookingManager.getBookings().toList();
    final walkins =
        LocalStorage.loadWalkinsForTrip(LocalStorage.getCurrentTripId())
            .toList();
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
        amount: walkin['amount'] ?? 0.0,
        status: 'on-board',
        passengerUid: null,
      );
      if (!bookings.any((b) => b.id == booking.id)) bookings.add(booking);
    }
    return bookings;
  }

  String _normalizeLocationName(String location) {
    return FareTable.normalizePlaceName(location);
  }

  void _loadBookings() {
    try {
      final conductor = AppState.instance.conductor;
      final uid = conductor?['uid']?.toString();
      if (uid != null && uid.isNotEmpty) {
        _bookingManager.loadForConductor(uid);
      }
    } catch (_) {
      // continue with in-memory bookings if load fails
    }
  }

  int _getPassengersOnBoard() {
    final bookings = _getCombinedBookings();
    if (currentLocation == 'OVERVIEW') return 0;
    final currentIdx = stops.indexOf(currentLocation ?? '');
    if (currentIdx == -1) return 0;
    int count = 0;
    for (final booking in bookings) {
      if (booking.status != 'on-board') continue;
      int fromIdx = -1, toIdx = -1;
      final originNormalized = _normalizeLocationName(booking.fromLocation);
      final destNormalized = _normalizeLocationName(booking.toLocation);
      final originWords = originNormalized
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final destWords = destNormalized
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      for (int i = 0; i < stops.length; i++) {
        final stopNormalized = _normalizeLocationName(stops[i]);
        final stopWords = stopNormalized
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        if (stopWords.every((sw) => originWords.contains(sw))) fromIdx = i;
        if (stopWords.every((sw) => destWords.contains(sw))) toIdx = i;
      }
      if (fromIdx != -1 &&
          toIdx != -1 &&
          fromIdx <= currentIdx &&
          currentIdx < toIdx) {
        count += booking.passengers;
      }
    }
    return count;
  }

  // No persistent system count state here; compute on-demand via _getPassengersOnBoard()

  // Canonical dropdown logic from PassengersScreen
  List<DropdownMenuItem<String>> _buildLocationDropdownItems() {
    // Custom logic: Always show all stops in the correct order for the route
    final items = <DropdownMenuItem<String>>[];
    items.add(
      const DropdownMenuItem(
        value: 'OVERVIEW',
        child: Text('OVERVIEW',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    );
    // For Nasugbu to Batangas, show Nasugbu first, Batangas last
    // For Batangas to Nasugbu, show Batangas first, Nasugbu last
    for (final stop in stops) {
      items.add(
        DropdownMenuItem(
          value: stop,
          child: Text(stop, style: const TextStyle(fontSize: 13)),
        ),
      );
    }
    return items;
  }

  void _saveInspection() async {
    final manualInput = _manualCountController.text.trim();
    if (manualInput.isEmpty) {
      await _showMessageDialog(
          'Validation', 'Please enter the manual passenger count');
      return;
    }

    final manualCount = int.tryParse(manualInput) ?? 0;

    // No extra decision required for discrepancy; isCleared determines report.

    // Collect NFC confirmations: inspector and conductor must both tap
    final signatures = await _collectSignatures();
    if (signatures == null) {
      await _showMessageDialog('Cancelled', 'Signature confirmation cancelled');
      return;
    }

    final assignedBus = await DeviceConfigService.getAssignedBus() ?? 'BUS_01';
    final inspectorName =
        LocalStorage.getEmployee(signatures['inspector'] ?? '')?['name']
                ?.toString() ??
            'Unknown';
    final condUid = signatures['conductor'] ??
        AppState.instance.conductor?['uid']?.toString() ??
        '';
    final conductorName =
        LocalStorage.getEmployee(condUid)?['name']?.toString() ??
            AppState.instance.conductor?['name']?.toString() ??
            'Unknown';
    final driverName =
        AppState.instance.driver?['name']?.toString() ?? 'Unknown';
    final tripId = LocalStorage.getCurrentTripId();

    // Create and save inspection (use conductorUid from tap)
    // Generate inspection id in format: Ins followed by 10 random digits
    final rand = Random.secure();
    final idNum = List.generate(10, (_) => rand.nextInt(10)).join();
    final inspectionId = 'Ins$idNum';

    final inspection = Inspection(
      id: inspectionId,
      timestamp: DateTime.now().toIso8601String(),
      busNumber: assignedBus,
      tripSession: widget.routeDirection,
      inspectorUid: inspectorName,
      inspectorName: inspectorName,
      tripId: tripId.isNotEmpty ? tripId : null,
      conductorUid: conductorName,
      driverUid: driverName,
      manualPassengerCount: manualCount,
      systemPassengerCount: _getPassengersOnBoard(),
      isCleared: _isCleared,
      comments: _commentsController.text.trim().isNotEmpty
          ? _commentsController.text.trim()
          : null,
    );

    try {
      await LocalStorage.saveInspection(inspection.toMap());

      // Immediately trigger background sync so data goes to Firebase right after inspection
      InspectionSyncService().syncNow();

      await _showMessageDialog('Saved', 'Inspection saved successfully');
      Navigator.pop(context);
    } catch (e) {
      await _showMessageDialog('Error', 'Error saving inspection: $e');
    }
  }

  Future<Map<String, String>?> _collectSignatures() async {
    Map<String, String?> found = {'inspector': null, 'conductor': null};
    StreamSubscription? sub;
    final completer = Completer<Map<String, String>?>();

    // Show dialog instructing taps
    // Mark inspector modal active so global NFC handlers don't interrupt
    AppState.instance.setInspectorModalActive(true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) {
          // subscribe when dialog built
          sub ??= NFCReaderModeService.instance.onTag.listen((data) {
            final uid = (data['uid'] ?? '').toString();
            final role = (data['role'] ?? '').toString().toLowerCase();
            if (role == 'inspector') {
              found['inspector'] = uid;
              setState(() {});
            } else if (role == 'conductor') {
              found['conductor'] = uid;
              setState(() {});
            }

            if (found['inspector'] != null && found['conductor'] != null) {
              // both present
              sub?.cancel();
              Navigator.pop(dialogContext);
              completer.complete({
                'inspector': found['inspector']!,
                'conductor': found['conductor']!
              });
            }
          });

          return AlertDialog(
            elevation: 10,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Center(
              child: Text(
                'CONFIRM SIGNATURES',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Please tap the inspector card, then the conductor card on the device.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: Text(
                            'Inspector: ${found['inspector'] ?? 'waiting...'}')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            'Conductor: ${found['conductor'] ?? 'waiting...'}')),
                  ],
                ),
                const SizedBox(height: 12),
                const CircularProgressIndicator(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  sub?.cancel();
                  Navigator.pop(dialogContext);
                  completer.complete(null);
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );

    // Timeout: complete with null after 30s if not finished
    Future.delayed(const Duration(seconds: 30)).then((_) {
      if (!completer.isCompleted) {
        sub?.cancel();
        try {
          Navigator.pop(context);
        } catch (_) {}
        completer.complete(null);
      }
    });

    // Ensure the modal-active flag is cleared when the signature collection finishes
    completer.future.whenComplete(() {
      try {
        AppState.instance.setInspectorModalActive(false);
      } catch (_) {}
    });

    return completer.future;
  }

  Future<void> _showMessageDialog(String title, String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualCountController.dispose();
    _commentsController.dispose();
    _customExplanationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh bookings when screen is resumed
      setState(() {
        _loadBookings();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;

    // Keep in sync with Passenger menu by reloading bookings and counts
    _loadBookings();
    // Debug: log current route, widget prop, stops and currentLocation each build
    try {
      final cur = LocalStorage.getCurrentRoute();
      debugPrint('[INSPECTOR] build LocalStorage.getCurrentRoute: $cur');
    } catch (_) {}
    debugPrint(
        '[INSPECTOR] build widget.routeDirection=${widget.routeDirection}');
    if (stops.isNotEmpty) {
      debugPrint(
          '[INSPECTOR] build stops[0]=${stops.first}, stops[last]=${stops.last}');
    }
    debugPrint('[INSPECTOR] build currentLocation=$currentLocation');

    // Compute safe bottom padding so content doesn't overflow under nav bars
    // Add a small extra slack (12px) to ensure no fractional-pixel overflow
    final double bottomSafePad = screenH * 0.03 + mq.viewPadding.bottom + 12.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text(
          'INSPECTOR AUDIT',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // leave horizontal padding based on screen width, but ensure extra
          // bottom padding (including system inset) to avoid pixel overflow.
          padding: EdgeInsets.fromLTRB(
            screenW * 0.04,
            screenW * 0.04,
            screenW * 0.04,
            bottomSafePad,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Location selector (same style as Passengers screen)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Current Location',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 36,
                          child: DropdownButton<String>(
                            value: currentLocation,
                            isExpanded: true,
                            underline:
                                Container(color: Colors.grey[300], height: 1),
                            items: _buildLocationDropdownItems(),
                            onChanged: (value) {
                              setState(() {
                                // Only update currentLocation, never clear stops
                                currentLocation = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: screenW * 0.03),
                ],
              ),
              SizedBox(height: screenH * 0.02),

              // System and Manual count display side by side
              Row(
                children: [
                  // System count display
                  SizedBox(
                    width: screenW * 0.35,
                    child: Container(
                      padding: EdgeInsets.all(screenW * 0.04),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        border: Border.all(color: Colors.green[400]!, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'System Count',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          SizedBox(height: screenH * 0.01),
                          Text(
                            '${_getPassengersOnBoard()}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: screenW * 0.03),
                  // Manual count input
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Manual Count',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                        SizedBox(height: screenH * 0.01),
                        SizedBox(
                          height: screenH * 0.06,
                          child: TextField(
                            controller: _manualCountController,
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final manualCount = int.tryParse(value.trim());
                              setState(() {
                                if (manualCount != null) {
                                  _isCleared =
                                      (manualCount == _getPassengersOnBoard());
                                } else {
                                  _isCleared = false;
                                }
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Enter count',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: screenW * 0.02,
                                  vertical: screenH * 0.01),
                              prefixIcon: const Icon(Icons.people),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenH * 0.02),

              // Show result
              if (_isCleared)
                Container(
                  padding: EdgeInsets.all(screenW * 0.03),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    border: Border.all(color: Colors.green, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified, color: Colors.green, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'INSPECTION CLEARED\nPassenger count matches system record',
                          style: TextStyle(
                              color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_manualCountController.text.isNotEmpty && !_isCleared)
                Container(
                  padding: EdgeInsets.all(screenW * 0.03),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'DISCREPANCY DETECTED',
                            style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: screenH * 0.015),
                      Text(
                          'Manual: ${_manualCountController.text} vs System: ${_getPassengersOnBoard()}'),
                      SizedBox(height: screenH * 0.02),
                    ],
                  ),
                ),

              SizedBox(height: screenH * 0.03),

              // Comments section
              const Text('Inspector Comments',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: screenH * 0.01),
              TextField(
                controller: _commentsController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'Enter observations about driver, conductor, or trip',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              SizedBox(height: screenH * 0.03),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[400],
                        padding:
                            EdgeInsets.symmetric(vertical: screenH * 0.015),
                      ),
                      child: const Text('Back',
                          style: TextStyle(color: Colors.black)),
                    ),
                  ),
                  SizedBox(width: screenW * 0.02),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveInspection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        padding:
                            EdgeInsets.symmetric(vertical: screenH * 0.015),
                      ),
                      child: const Text('Save Inspection',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
