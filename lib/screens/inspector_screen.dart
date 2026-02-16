import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import '../services/nfc_reader_mode_service.dart';
import '../models/inspection.dart';
import '../local_storage.dart';
import '../services/app_state.dart';
import '../models/booking.dart';
import '../utils/fare_calculator.dart';

class InspectorScreen extends StatefulWidget {
  final String
      routeDirection; // 'forward' or 'reverse' (north_to_south or south_to_north)

  const InspectorScreen({super.key, required this.routeDirection});

  @override
  State<InspectorScreen> createState() => _InspectorScreenState();
}

class _InspectorScreenState extends State<InspectorScreen> {
  late TextEditingController _manualCountController;
  late TextEditingController _commentsController;
  String? _discrepancyResolved;
  String? _selectedReason;
  bool _showCustomExplanation = false;
  late TextEditingController _customExplanationController;
  late List<String> _stops;
  late List<String> _dropdownStops;
  String? _currentLocation;

  int _systemPassengerCount = 0;
  bool _isCleared = false;

  final List<String> _resolutionReasons = [
    'Passenger failed to scan QR',
    'Double counting',
    'Child / exempted passenger',
    'Conductor input error',
    'System delay',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _manualCountController = TextEditingController();
    _commentsController = TextEditingController();
    _customExplanationController = TextEditingController();
    // Prepare stops and default current location, then get system passenger count
    final forwardStops = FareTable.placeNamesWithKm;
    // Prefer the persisted route (set at route selection / dispatch) if available,
    // otherwise use the routeDirection passed into the screen.
    final currentRoute = LocalStorage.getCurrentRoute();
    final routeId =
        currentRoute != null ? currentRoute['routeId'] : widget.routeDirection;
    _stops = routeId == 'north_to_south'
        ? List.from(forwardStops)
        : List.from(forwardStops.reversed);
    // Use uppercase OVERVIEW to match other screens
    _dropdownStops = ['OVERVIEW', ..._stops];
    _currentLocation = 'OVERVIEW';
    _calculateSystemPassengerCount();
  }

  List<Booking> _getCombinedBookings() {
    var bookings = BookingManager().getBookings().toList();
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

  void _calculateSystemPassengerCount() {
    try {
      final bookings = _getCombinedBookings();
      if (_currentLocation == 'OVERVIEW') {
        // For inspector, show 0 for overview (match passengers screen on-board behavior)
        setState(() {
          _systemPassengerCount = 0;
        });
        return;
      }

      final currentIdx = _stops.indexOf(_currentLocation ?? '');
      if (currentIdx == -1) {
        setState(() {
          _systemPassengerCount = 0;
        });
        return;
      }

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

        for (int i = 0; i < _stops.length; i++) {
          final stopNormalized = _normalizeLocationName(_stops[i]);
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

      setState(() {
        _systemPassengerCount = count;
      });
    } catch (e) {
      debugPrint('[INSPECTOR] Error calculating system passenger count: $e');
    }
  }

  void _compareAndValidate() {
    final manualInput = _manualCountController.text.trim();
    if (manualInput.isEmpty) {
      _showMessageDialog(
          'Validation', 'Please enter the manual passenger count');
      return;
    }

    final manualCount = int.tryParse(manualInput) ?? 0;
    final matches = manualCount == _systemPassengerCount;

    setState(() {
      _isCleared = matches;
      if (matches) {
        _discrepancyResolved = null;
        _selectedReason = null;
      }
    });

    if (matches) {
      _showMessageDialog('Verified', 'Passenger count verified successfully');
    }
  }

  void _saveInspection() async {
    final manualInput = _manualCountController.text.trim();
    if (manualInput.isEmpty) {
      await _showMessageDialog(
          'Validation', 'Please enter the manual passenger count');
      return;
    }

    final manualCount = int.tryParse(manualInput) ?? 0;

    // Validate mismatch case
    if (!_isCleared && _discrepancyResolved == null) {
      await _showMessageDialog(
          'Validation', 'Please select whether the discrepancy was resolved');
      return;
    }

    if (_discrepancyResolved == 'Resolved' && _selectedReason == null) {
      await _showMessageDialog(
          'Validation', 'Please select a resolution reason');
      return;
    }

    if (_selectedReason == 'Other' &&
        _customExplanationController.text.trim().isEmpty) {
      await _showMessageDialog(
          'Validation', 'Please provide a custom explanation');
      return;
    }

    // Collect NFC confirmations: inspector and conductor must both tap
    final signatures = await _collectSignatures();
    if (signatures == null) {
      await _showMessageDialog('Cancelled', 'Signature confirmation cancelled');
      return;
    }

    // Create and save inspection (use conductorUid from tap)
    // Generate inspection id in format: Ins followed by 10 random digits
    final rand = Random.secure();
    final idNum = List.generate(10, (_) => rand.nextInt(10)).join();
    final inspectionId = 'Ins$idNum';

    final inspection = Inspection(
      id: inspectionId,
      timestamp: DateTime.now().toIso8601String(),
      busNumber: 'TBD', // TODO: Get from app state
      tripSession: widget.routeDirection,
      inspectorUid: signatures['inspector'],
      inspectorName:
          LocalStorage.getEmployee(signatures['inspector'] ?? '')?['name']
              ?.toString(),
      conductorUid: signatures['conductor'] ??
          AppState.instance.conductor?['uid']?.toString() ??
          'UNKNOWN',
      driverUid: AppState.instance.driver?['uid']?.toString() ?? 'UNKNOWN',
      manualPassengerCount: manualCount,
      systemPassengerCount: _systemPassengerCount,
      isCleared: _isCleared,
      discrepancyResolved: _discrepancyResolved,
      resolutionReason: _selectedReason == 'Other' ? null : _selectedReason,
      customExplanation: _selectedReason == 'Other'
          ? _customExplanationController.text.trim()
          : null,
      comments: _commentsController.text.trim().isNotEmpty
          ? _commentsController.text.trim()
          : null,
    );

    try {
      await LocalStorage.saveInspection(inspection.toMap());
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
    _manualCountController.dispose();
    _commentsController.dispose();
    _customExplanationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;

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
          padding: EdgeInsets.all(screenW * 0.04),
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
                            value: _currentLocation,
                            isExpanded: true,
                            underline:
                                Container(color: Colors.grey[300], height: 1),
                            items: _dropdownStops
                                .map((s) =>
                                    DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _currentLocation = value;
                                _calculateSystemPassengerCount();
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
                            '$_systemPassengerCount',
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

              // Compare button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _compareAndValidate,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Verify Count'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: EdgeInsets.symmetric(vertical: screenH * 0.015),
                  ),
                ),
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
                          'Manual: ${_manualCountController.text} vs System: $_systemPassengerCount'),
                      SizedBox(height: screenH * 0.02),

                      // Discrepancy resolution
                      const Text('Was the discrepancy resolved?',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: screenH * 0.01),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              value: 'Resolved',
                              groupValue: _discrepancyResolved,
                              onChanged: (v) => setState(() {
                                _discrepancyResolved = v;
                                _showCustomExplanation = false;
                                _selectedReason = null;
                              }),
                              title: const Text('Resolved'),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              value: 'Not Resolved',
                              groupValue: _discrepancyResolved,
                              onChanged: (v) => setState(() {
                                _discrepancyResolved = v;
                                _showCustomExplanation = false;
                                _selectedReason = null;
                              }),
                              title: const Text('Not Resolved'),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: screenH * 0.02),

                      // Resolution reason dropdown (if resolved)
                      if (_discrepancyResolved == 'Resolved')
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Resolution Reason',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: screenH * 0.01),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedReason,
                              hint: const Text('Select reason'),
                              isExpanded: true,
                              items: _resolutionReasons
                                  .map((r) => DropdownMenuItem(
                                      value: r, child: Text(r)))
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _selectedReason = v;
                                _showCustomExplanation = v == 'Other';
                              }),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            SizedBox(height: screenH * 0.015),

                            // Custom explanation (if Other)
                            if (_showCustomExplanation)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Custom Explanation',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  SizedBox(height: screenH * 0.01),
                                  TextField(
                                    controller: _customExplanationController,
                                    maxLines: 3,
                                    decoration: InputDecoration(
                                      hintText: 'Explain the custom reason',
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
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
