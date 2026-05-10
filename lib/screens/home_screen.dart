import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_screen.dart';
import 'bookings_screen.dart';
import 'records_screen.dart';
import 'booking_alerts_screen.dart';
import 'package:senraise_printer/senraise_printer.dart';
import 'package:untitled/screens/qr_scanner_screen.dart';
import 'passengers_screen.dart';
import 'package:untitled/utils/fare_calculator.dart';
import 'package:untitled/utils/stops.dart';
import '../services/app_state.dart';
import '../services/device_config_service.dart';
import '../services/nfc_reader_mode_service.dart';
import '../services/sms_booking_alert_service.dart';
import '../services/qr_validation_service.dart';
import '../services/rtdb_occupancy_publisher_service.dart';
import '../services/trip_record_live_service.dart';
import '../local_storage.dart';
import '../main.dart' show navigatorKey;
import '../utils/dialogs.dart';
import '../utils/route_validator.dart' as route_validator;

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
  final SmsBookingAlertService _smsAlertService = SmsBookingAlertService();
  StreamSubscription<Map<String, dynamic>>? _bookingAlertSub;
  StreamSubscription<void>? _fareTableSub;
  List<Map<String, dynamic>> _activeBookingAlerts = [];
  String _activeScheduleTimeKey = '';
  String _activeRouteDirectionKey = '';

  @override
  void initState() {
    super.initState();
    AppState.instance.setCurrentScreen('home_screen');
    routeDirection = widget.routeDirection ?? 'north_to_south';
    _refreshAvailableStops(preserveSelection: false);

    _fareTableSub = FareTable.changes.listen((_) {
      if (!mounted) return;
      setState(() {
        _refreshAvailableStops(preserveSelection: true);
      });
    });

    // Detect assigned bus for this device (BUS-001 / BUS-002)
    // Re-detect every launch; if successful it overwrites any stale cache
    DeviceConfigService.autoDetectAndSaveAssignedBus().then((detected) async {
      final bus = detected ?? await DeviceConfigService.getAssignedBus();
      if (mounted) {
        setState(() => _assignedBus = bus);
      }
      await _refreshActiveScheduleContext();
      // Start RTDB occupancy publisher after schedule context is ready
      if (bus != null && bus.isNotEmpty) {
        RtdbOccupancyPublisherService().start(
          busNumber: bus,
          routeDirection: routeDirection,
        );
        unawaited(TripRecordLiveService().start(
          busNumber: bus,
          routeDirection: routeDirection,
        ));
      }
    });

    _initActiveBookingAlerts();
  }

  Future<void> _initActiveBookingAlerts() async {
    await _smsAlertService.startListening();
    final stored = await _smsAlertService.getStoredAlerts();
    if (!mounted) return;

    setState(() {
      _activeBookingAlerts = _normalizeActiveBookingAlerts(stored);
    });

    await _bookingAlertSub?.cancel();
    _bookingAlertSub = _smsAlertService.alertsStream.listen((_) async {
      await _refreshActiveScheduleContext();
      final latest = await _smsAlertService.getStoredAlerts();
      if (!mounted) return;
      setState(() {
        _activeBookingAlerts = _normalizeActiveBookingAlerts(latest);
      });
    });
  }

  Future<void> _refreshActiveScheduleContext() async {
    // ── Primary: read from locally saved accepted schedule (no network) ──
    final localSchedule = LocalStorage.getAcceptedSchedule();
    if (localSchedule != null) {
      final localKey = LocalStorage.getAcceptedScheduleTimeKey();
      final routeStr =
          (localSchedule['route'] ?? localSchedule['routeName'] ?? '')
              .toString();
      final derivedDirection = _deriveRouteDirectionFromText(routeStr);
      if (localKey.isNotEmpty && mounted) {
        setState(() {
          _activeScheduleTimeKey = localKey;
          if (derivedDirection.isNotEmpty) {
            _activeRouteDirectionKey = derivedDirection;
            routeDirection = derivedDirection;
          }
        });
        debugPrint('[HomeScreen] Loaded schedule key from local: "$localKey"');
      }
    }

    // ── Secondary: poll Firebase to refresh/confirm (updates local if changed) ──
    final bus = (_assignedBus ?? '').trim();
    if (bus.isEmpty) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('schedules')
          .where('busNumber', isEqualTo: bus)
          .where('status', isEqualTo: 'departed')
          .orderBy('dispatchTime', descending: true)
          .limit(1)
          .get();

      if (!mounted) return;

      if (query.docs.isEmpty) {
        // No departed schedule on Firebase — keep local schedule if present
        if (localSchedule == null) {
          setState(() {
            _activeScheduleTimeKey = '';
            _activeRouteDirectionKey = '';
          });
        }
        return;
      }

      final data = query.docs.first.data();
      // Debug: log all keys present in the schedule document
      debugPrint(
          '[HomeScreen] Firebase schedule doc keys: ${data.keys.toList()}');

      final rawScheduleTime = data['ScheduledTimeStr'] ??
          data['scheduledTimeStr'] ??
          data['ScheduleTime'] ??
          data['scheduleTime'] ??
          data['scheduledTime'] ??
          data['scheduledTimeSTR'] ??
          data['ScheduledTime'] ??
          data['schedule_time'] ??
          data['dispatchTime'];

      debugPrint(
          '[HomeScreen] Firebase rawScheduleTime: $rawScheduleTime (${rawScheduleTime?.runtimeType})');

      final activeScheduleKey = _normalizeScheduleKey(rawScheduleTime);
      debugPrint(
          '[HomeScreen] Firebase normalized activeScheduleKey: "$activeScheduleKey"');

      final routeStr = (data['route'] ?? data['routeName'] ?? '').toString();
      final derivedDirection = _deriveRouteDirectionFromText(routeStr);

      if (mounted) {
        setState(() {
          _activeScheduleTimeKey = activeScheduleKey;
          if (derivedDirection.isNotEmpty) {
            _activeRouteDirectionKey = derivedDirection;
            routeDirection = derivedDirection;
          }
        });
      }

      // Update local store with latest Firebase data (keeps offline copy fresh)
      if (activeScheduleKey.isNotEmpty) {
        LocalStorage.setActiveScheduleTimeKey(activeScheduleKey);
      }
      // Persist full schedule doc locally if we don't have one yet
      if (localSchedule == null && activeScheduleKey.isNotEmpty) {
        final enriched = Map<String, dynamic>.from(data);
        enriched['savedAt'] = DateTime.now().toIso8601String();
        await LocalStorage.saveAcceptedSchedule(enriched);
        debugPrint('[HomeScreen] Bootstrapped local schedule from Firebase.');
      }

      final parts = routeStr.split(RegExp(r'\s+to\s+', caseSensitive: false));
      if (parts.length == 2) {
        final fromCity = parts[0].trim().toLowerCase();
        final toCity = parts[1].trim().toLowerCase();
        if (mounted) {
          setState(() {
            final fromMatch = availableStops.cast<String?>().firstWhere(
                (s) =>
                    s != null &&
                    FareTable.extractPlaceName(s)
                        .toLowerCase()
                        .startsWith(fromCity),
                orElse: () => null);
            final toMatch = availableStops.cast<String?>().firstWhere(
                (s) =>
                    s != null &&
                    FareTable.extractPlaceName(s)
                        .toLowerCase()
                        .startsWith(toCity),
                orElse: () => null);
            if (fromMatch != null) fromLocation = fromMatch;
            if (toMatch != null) toLocation = toMatch;
          });
        }
      }
    } catch (e) {
      debugPrint(
          '[HomeScreen] Firebase schedule refresh error (non-fatal): $e');
      // Non-fatal — local schedule is still valid
    }
  }

  List<Map<String, dynamic>> _normalizeActiveBookingAlerts(
      List<Map<String, dynamic>> alerts) {
    const trackedBookingIds = {
      '0OhBkgEAYh35UgwtMXU3',
      'q1MWmuqcMNKKns4wtFwl',
    };

    final sorted = List<Map<String, dynamic>>.from(alerts)
      ..sort((a, b) => ((b['receivedAtMs'] as int?) ?? 0)
          .compareTo((a['receivedAtMs'] as int?) ?? 0));

    // Keep latest event per booking first so status transitions such as
    // waiting -> on-board can correctly hide stale waiting entries.
    final latestByBooking = <String, Map<String, dynamic>>{};
    final withoutBookingId = <Map<String, dynamic>>[];
    for (final item in sorted) {
      final bookingId = (item['bookingId'] ?? '').toString().trim();
      if (bookingId.isNotEmpty) {
        latestByBooking.putIfAbsent(bookingId, () => item);
      } else {
        withoutBookingId.add(item);
      }
    }

    final list = <Map<String, dynamic>>[];

    bool shouldLogBooking(Map<String, dynamic> item) {
      final bookingId = (item['bookingId'] ?? '').toString().trim();
      return trackedBookingIds.contains(bookingId);
    }

    void logBookingDecision(Map<String, dynamic> item, String decision,
        {String details = ''}) {
      if (!shouldLogBooking(item)) return;
      final bookingId = (item['bookingId'] ?? '').toString().trim();
      final status = (item['status'] ?? '').toString().trim().toLowerCase();
      final origin = (item['origin'] ?? '').toString().trim();
      final destination = (item['destination'] ?? '').toString().trim();
      final itemScheduleKey = _extractAlertScheduleKey(item);
      final activeScheduleKey = _activeScheduleTimeKey;
      final activeDirection = (_activeRouteDirectionKey.isNotEmpty
              ? _activeRouteDirectionKey
              : routeDirection)
          .trim()
          .toLowerCase();
      debugPrint(
        '[BookingFilter][Home] bookingId=$bookingId decision=$decision '
        'status=$status activeDir=$activeDirection origin="$origin" '
        'destination="$destination" activeSchedule="$activeScheduleKey" '
        'itemSchedule="$itemScheduleKey" $details',
      );
    }

    String? routeRejectReason(Map<String, dynamic> item) {
      final activeDirection = (_activeRouteDirectionKey.isNotEmpty
              ? _activeRouteDirectionKey
              : routeDirection)
          .trim()
          .toLowerCase();
      if (activeDirection.isEmpty) return 'missing_active_direction';

      final originRaw =
          (item['origin'] ?? item['from'] ?? item['fromLocation'] ?? '')
              .toString()
              .trim();
      final destinationRaw =
          (item['destination'] ?? item['to'] ?? item['toLocation'] ?? '')
              .toString()
              .trim();

      if (originRaw.isNotEmpty && destinationRaw.isNotEmpty) {
        final stationList =
            route_validator.RouteValidator.getStationListForDirection(
                activeDirection);
        final origin = QRValidationService.resolveStationName(originRaw);
        final destination =
            QRValidationService.resolveStationName(destinationRaw);
        final originIndex = route_validator.RouteValidator.findStationIndex(
            origin, stationList);
        final destinationIndex =
            route_validator.RouteValidator.findStationIndex(
                destination, stationList);

        if (originIndex >= 0 && destinationIndex >= 0) {
          if (originIndex < destinationIndex) return null;
          return 'route_station_order_mismatch';
        }
      }

      final itemDirection = _deriveRouteDirectionFromText(
        (item['busRoute'] ?? item['routeName'] ?? item['route'] ?? '')
            .toString(),
      );
      if (itemDirection.isNotEmpty) {
        if (itemDirection == activeDirection) return null;
        return 'route_direction_mismatch';
      }

      return 'route_unresolved';
    }

    for (final item in latestByBooking.values) {
      final origin = (item['origin'] ?? '').toString().trim();
      final seats = int.tryParse((item['seats'] ?? '').toString()) ?? 0;
      final status = (item['status'] ?? '').toString().trim().toLowerCase();

      if (origin.isEmpty || seats <= 0) {
        logBookingDecision(item, 'reject',
            details: 'reason=missing_origin_or_seats');
        continue;
      }
      if (status != 'waiting') {
        logBookingDecision(item, 'reject', details: 'reason=not_waiting');
        continue;
      }
      final routeReason = routeRejectReason(item);
      if (routeReason != null) {
        logBookingDecision(item, 'reject', details: 'reason=$routeReason');
        continue;
      }
      logBookingDecision(item, 'accept');
      list.add(item);
    }

    // Keep legacy/no-bookingId waiting alerts compatible.
    for (final item in withoutBookingId) {
      final origin = (item['origin'] ?? '').toString().trim();
      final seats = int.tryParse((item['seats'] ?? '').toString()) ?? 0;
      final status = (item['status'] ?? '').toString().trim().toLowerCase();
      if (origin.isEmpty || seats <= 0) {
        logBookingDecision(item, 'reject',
            details: 'reason=missing_origin_or_seats');
        continue;
      }
      if (status != 'waiting') {
        logBookingDecision(item, 'reject', details: 'reason=not_waiting');
        continue;
      }
      final routeReason = routeRejectReason(item);
      if (routeReason != null) {
        logBookingDecision(item, 'reject', details: 'reason=$routeReason');
        continue;
      }
      logBookingDecision(item, 'accept');
      list.add(item);
    }

    final descendingStation = routeDirection == 'south_to_north';
    list.sort((a, b) {
      final stationA = _extractStationNumber(a);
      final stationB = _extractStationNumber(b);

      if (stationA >= 0 && stationB >= 0 && stationA != stationB) {
        return descendingStation
            ? stationB.compareTo(stationA)
            : stationA.compareTo(stationB);
      }

      // Fallback to most recent if station cannot be compared.
      return ((b['receivedAtMs'] as int?) ?? 0)
          .compareTo((a['receivedAtMs'] as int?) ?? 0);
    });

    return list.take(2).toList();
  }

  int _extractStationNumber(Map<String, dynamic> item) {
    final stationRaw = (item['station'] ?? '').toString().trim();
    final fromStation = int.tryParse(stationRaw);
    if (fromStation != null) return fromStation;

    final origin = (item['origin'] ?? '').toString().trim();
    final match = RegExp(r'^(\d+)\s*\.').firstMatch(origin);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? -1;
    }
    return -1;
  }

  String _extractAlertScheduleKey(Map<String, dynamic> item) {
    return _normalizeScheduleKey(
      (item['ScheduledTimeStr'] ??
          item['scheduledTimeStr'] ??
          item['ScheduleTime'] ??
          item['ScheduleTIme'] ??
          item['scheduleTime'] ??
          item['scheduledTime'] ??
          item['scheduledTimeSTR']),
    );
  }

  String _deriveRouteDirectionFromText(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return '';

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

    return '';
  }

  String _normalizeScheduleKey(dynamic raw) {
    if (raw == null) return '';

    if (raw is Timestamp) {
      return _formatScheduleMinuteKey(raw.toDate());
    }

    if (raw is DateTime) {
      return _formatScheduleMinuteKey(raw);
    }

    final text = raw.toString().trim();
    if (text.isEmpty) return '';

    final asDate = DateTime.tryParse(text) ??
        DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (asDate != null) {
      return _formatScheduleMinuteKey(asDate);
    }

    return text.toLowerCase();
  }

  String _formatScheduleMinuteKey(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  @override
  void dispose() {
    _bookingAlertSub?.cancel();
    _fareTableSub?.cancel();
    // Stop RTDB publisher when home screen is disposed
    RtdbOccupancyPublisherService().stop();
    super.dispose();
  }

  void _refreshAvailableStops({required bool preserveSelection}) {
    final nextStops = List<String>.from(fareTableStops);
    if (nextStops.isEmpty) return;

    final previousFrom = preserveSelection ? fromLocation : '';
    final previousTo = preserveSelection ? toLocation : '';
    final matchedFrom =
        preserveSelection ? _findEquivalentStop(nextStops, previousFrom) : null;
    final matchedTo =
        preserveSelection ? _findEquivalentStop(nextStops, previousTo) : null;

    availableStops = nextStops;
    fromLocation = matchedFrom ??
        (routeDirection == 'north_to_south'
            ? availableStops.first
            : availableStops.last);

    final validToStops = getValidToStops();
    toLocation = matchedTo != null && validToStops.contains(matchedTo)
        ? matchedTo
        : (validToStops.isNotEmpty ? validToStops.first : '');
  }

  String? _findEquivalentStop(List<String> stops, String selected) {
    if (selected.isEmpty) return null;
    final selectedPlace =
        FareTable.normalizePlaceName(FareTable.extractPlaceName(selected));
    for (final stop in stops) {
      final stopPlace =
          FareTable.normalizePlaceName(FareTable.extractPlaceName(stop));
      if (stopPlace == selectedPlace) return stop;
    }
    return null;
  }

  String? _assignedBus;

  bool get _isSessionLockedToRecordsOnly =>
      AppState.instance.tripCancelledLocked;

  Future<void> _showLockedModeMessage() async {
    if (!mounted) return;
    await Dialogs.showMessage(
      context,
      'Trip Locked',
      'Trip has been cancelled for this session. Only Menu > Records > Arrival Report is allowed.',
    );
  }

  String? passengerType;

  final List<String> passengerTypes = [
    'REGULAR',
    'STUDENT',
    'SENIOR',
    'PWD',
    'CHILD',
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
    if (routeDirection == 'north_to_south') {
      return 'Nasugbu to Batangas';
    }
    if (routeDirection == 'south_to_north') {
      return 'Batangas to Nasugbu';
    }
    return 'Unknown';
  }

  double get fare {
    final originPlace = FareTable.extractPlaceName(fromLocation);
    final destPlace = FareTable.extractPlaceName(toLocation);
    return FareCalculator.calculateFare(
      origin: originPlace,
      destination: destPlace,
      passengerType: passengerType ?? 'REGULAR',
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
    final isLocked = _isSessionLockedToRecordsOnly;

    final double vpadSmall = screenH * 0.006;
    final double vpad = screenH * 0.012;
    final double headerHeight = screenH * 0.07;

    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: _buildDrawer(screenW, context),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: screenW * 0.03, vertical: vpadSmall),
          child: Column(
            children: [
              _buildHeader(screenW, headerHeight),
              SizedBox(height: vpadSmall),
              if (isLocked)
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: vpadSmall),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Text(
                    'Trip cancelled: operational features are locked. Use Menu > Records > Arrival Report only.',
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLocationSelector(
                      label: "FROM",
                      value: fromLocation,
                      options: getValidFromStops(),
                      enabled: !isLocked,
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
                      enabled: !isLocked,
                      onChanged: (v) => setState(() => toLocation = v),
                    ),
                    SizedBox(height: vpad + vpadSmall),
                    _buildPassengerTypeSelector(screenW),
                    SizedBox(height: vpad + vpadSmall),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQrPopupButton(screenH, screenW, context),
                        ),
                        SizedBox(width: screenW * 0.02),
                        Expanded(
                          child: _buildBookingsInWaitingButton(
                              screenH, screenW, context),
                        ),
                      ],
                    ),
                    SizedBox(height: vpad + vpadSmall),
                    _buildScanTicketButton(screenH, context),
                    SizedBox(height: vpadSmall),
                    SizedBox(height: screenH * 0.02),
                    _buildQuantityAndTotal(screenW),
                    SizedBox(height: vpad + vpadSmall),
                    _buildPrintButton(screenH),
                    SizedBox(height: vpadSmall),
                  ],
                ),
              ),
            ],
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
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            title: const Text("PROFILE"),
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    routeInfo: getRouteDisplay(),
                    conductor: widget.conductor,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
          ListTile(
            title: const Text("BOOKINGS"),
            onTap: () async {
              Navigator.pop(context);
              if (_isSessionLockedToRecordsOnly) {
                await _showLockedModeMessage();
                return;
              }
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
            onTap: () async {
              Navigator.pop(context);
              if (_isSessionLockedToRecordsOnly) {
                await _showLockedModeMessage();
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PassengersScreen(routeDirection: routeDirection),
                ),
              );
            },
          ),
          ListTile(
            title: const Text("RECORDS"),
            onTap: () {
              Navigator.pop(context);
              _showConductorAuthDialog(context);
            },
          ),
        ],
      ),
    );
  }

  /// Header UI
  Widget _buildHeader(double screenW, double headerHeight) {
    final assignedBus = (_assignedBus ?? '').trim();
    // Normalize assigned bus to a short numeric id (e.g. 'BUS-001' -> '001')
    String posLabel;
    if (assignedBus.isNotEmpty) {
      final digits = assignedBus.replaceAll(RegExp(r'[^0-9]'), '');
      final padded = digits.isNotEmpty ? digits.padLeft(3, '0') : assignedBus;
      posLabel = 'POS $padded';
    } else {
      posLabel = 'POS';
    }

    // Use IntrinsicHeight so both panels match the MENU's measured height.
    // This applies the MENU's height onto the Batman panel rather than
    // the other way around.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: screenW * 0.67,
            color: Colors.green[700],
            padding: EdgeInsets.symmetric(vertical: headerHeight * 0.12),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Batman Starexpress',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    posLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Builder(builder: (context) {
            return GestureDetector(
              onTap: () => Scaffold.of(context).openEndDrawer(),
              child: Container(
                width: screenW * 0.25,
                color: Colors.green[700],
                padding: EdgeInsets.symmetric(vertical: headerHeight * 0.12),
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

  Widget _buildActiveBookingsPanel(
      double screenW, double screenH, BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: screenH * 0.42),
      padding: EdgeInsets.all(screenW * 0.03),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade400, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_bus, color: Colors.green[800], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ACTIVE BOOKINGS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.green[900],
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  if (_isSessionLockedToRecordsOnly) {
                    await _showLockedModeMessage();
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          BookingAlertsScreen(routeDirection: routeDirection),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('VIEW ALL'),
              ),
            ],
          ),
          if (_activeBookingAlerts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No active booking alerts yet.',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            )
          else
            ..._activeBookingAlerts.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final item = entry.value;
              final origin = _stripStationPrefix(
                (item['origin'] ?? 'Unknown origin').toString(),
              );
              final seats = (item['seats'] ?? 0).toString();

              return Container(
                margin: EdgeInsets.only(top: screenH * 0.007),
                padding: EdgeInsets.symmetric(
                  horizontal: screenW * 0.03,
                  vertical: screenH * 0.008,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 10),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: rank == 1
                            ? Colors.green.shade700
                            : Colors.green.shade300,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          color:
                              rank == 1 ? Colors.white : Colors.green.shade900,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            origin,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '$seats seat${seats == '1' ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.green.shade900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _stripStationPrefix(String value) {
    return value.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim();
  }

  /// Passenger Type UI
  Widget _buildPassengerTypeSelector(double screenW) {
    final isLocked = _isSessionLockedToRecordsOnly;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('PASSENGER TYPE:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        Container(
          width: screenW * 0.45,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: isLocked
                  ? Colors.grey
                  : (passengerType == null ? Colors.red : Colors.black54),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButton<String>(
            isExpanded: true,
            underline: const SizedBox(),
            value: passengerType,
            hint:
                const Text('Select Type', style: TextStyle(color: Colors.grey)),
            items: passengerTypes
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: isLocked
                ? null
                : (value) => setState(() => passengerType = value!),
          ),
        ),
      ],
    );
  }

  /// QR Popup Button
  Widget _buildQrPopupButton(
      double screenH, double screenW, BuildContext context) {
    return SizedBox(
      height: screenH * 0.150,
      child: OutlinedButton.icon(
        onPressed: () async {
          if (_isSessionLockedToRecordsOnly) {
            await _showLockedModeMessage();
            return;
          }
          _showQrPopup(context);
        },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.green.shade700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: Icon(Icons.qr_code, color: Colors.green[700]),
        label: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'VIEW QR',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// BOOKINGS IN WAITING Button
  Widget _buildBookingsInWaitingButton(
      double screenH, double screenW, BuildContext context) {
    final incomingCount = _activeBookingAlerts.length;
    final hasIncoming = incomingCount > 0;

    return SizedBox(
      height: screenH * 0.150,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: hasIncoming ? 1 : 0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        builder: (context, glow, child) {
          final borderColor = Color.lerp(
            Colors.green.shade700,
            Colors.orange.shade500,
            glow * 0.35,
          )!;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: hasIncoming
                  ? [
                      BoxShadow(
                        color:
                            Colors.orange.withAlpha((56 + (31 * glow)).round()),
                        blurRadius: 12 + (10 * glow),
                        spreadRadius: 1.2 + (1.5 * glow),
                        offset: const Offset(0, 2),
                      )
                    ]
                  : const [],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: OutlinedButton(
                    onPressed: () async {
                      if (_isSessionLockedToRecordsOnly) {
                        await _showLockedModeMessage();
                        return;
                      }
                      _showBookingsDialog(context, screenW, screenH);
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: borderColor, width: hasIncoming ? 2 : 1.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.list_alt, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'BOOKINGS',
                            style: TextStyle(
                                fontSize: 30, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (hasIncoming)
                  Positioned(
                    top: -8,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        '$incomingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showBookingsDialog(
      BuildContext context, double screenW, double screenH) {
    if (_isSessionLockedToRecordsOnly) {
      _showLockedModeMessage();
      return;
    }
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
              horizontal: screenW * 0.01, vertical: screenH * 0.04),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenW * 0.99,
              maxHeight: screenH * 0.94,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildActiveBookingsPanel(screenW, screenH, context),
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
      height: screenH * 0.080,
      child: ElevatedButton(
        onPressed: () async {
          if (_isSessionLockedToRecordsOnly) {
            await _showLockedModeMessage();
            return;
          }

          if (LocalStorage.isManualMode()) {
            showDialog(
                context: context,
                builder: (_) => AlertDialog(
                        title: const Text('Manual Mode'),
                        content: const Text(
                            'Device is in manual ticketing mode. Scanning is disabled.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'))
                        ]));
            return;
          }

          // Check if driver is registered; if not, prompt for driver tap
          final driver = AppState.instance.driver;
          if (driver == null) {
            final driverTapped = await _promptForDriverTap();
            if (!driverTapped) return; // User cancelled
          }

          // Get conductor and driver names from AppState
          final conductorName =
              AppState.instance.conductor?['name'] ?? 'Unknown';
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
            await Dialogs.showMessage(
                context, 'Transaction', 'Transaction $result completed');
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
    // Reset debounce cache to allow immediate rescans
    NFCReaderModeService.instance.resetDebounce();

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
            try {
              await sub?.cancel();
            } catch (_) {}
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            if (!completer.isCompleted) completer.complete(true);
          } else {
            await Dialogs.showMessage(context, 'Invalid Card',
                'Card tapped is not a driver (role=$role). Please tap driver card.');
          }
        });

        return AlertDialog(
          title: const Text('Driver required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('Please tap your Driver ID card to continue scanning.'),
              SizedBox(height: 12),
              CircularProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  await sub?.cancel();
                } catch (_) {}
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
        try {
          await sub?.cancel();
        } catch (_) {}
        try {
          if (Navigator.canPop(context)) Navigator.pop(context);
        } catch (_) {}
        completer.complete(false);
      }
    });

    final result = await completer.future;
    // stop reader mode if no longer needed
    try {
      await NFCReaderModeService.instance.stop();
    } catch (_) {}
    return result;
  }

  /// Quantity + Total section
  Widget _buildQuantityAndTotal(double screenW) {
    final isLocked = _isSessionLockedToRecordsOnly;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('QUANTITY',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
                onChanged: isLocked
                    ? null
                    : (value) => setState(() => quantity = value!),
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
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
      height: screenH * 0.080,
      child: ElevatedButton(
        onPressed: () async {
          if (_isSessionLockedToRecordsOnly) {
            await _showLockedModeMessage();
            return;
          }

          if (passengerType == null) {
            showDialog(
                context: context,
                builder: (_) => AlertDialog(
                        title: const Text('Select Passenger Type'),
                        content: const Text(
                            'Please select a passenger type before printing a ticket.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'))
                        ]));
            return;
          }
          if (LocalStorage.isManualMode()) {
            showDialog(
                context: context,
                builder: (_) => AlertDialog(
                        title: const Text('Manual Mode'),
                        content: const Text(
                            'Device is in manual ticketing mode. Printing is disabled.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'))
                        ]));
            return;
          }
          final now = DateTime.now();
          final weekday = [
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat',
            'Sun'
          ][now.weekday - 1];
          final date =
              "$weekday ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
          final period = now.hour >= 12 ? 'PM' : 'AM';
          final hour12 = ((now.hour + 11) % 12 + 1).toString().padLeft(2, '0');
          final minute = now.minute.toString().padLeft(2, '0');
          final time = '$hour12:$minute $period';

          // Extract place names from formatted strings (km|Place)
          final originPlace = FareTable.extractPlaceName(fromLocation);
          final destPlace = FareTable.extractPlaceName(toLocation);

          final actualTotal = fare * quantity;
          final totalAmount = actualTotal.toStringAsFixed(2);

          // Compute walk-in discount as difference between regular total and actual total
          final regularFarePerSeat = FareCalculator.calculateFare(
            origin: originPlace,
            destination: destPlace,
            passengerType: 'REGULAR',
            quantity: 1,
          ).toDouble();
          final regularTotal = regularFarePerSeat * quantity;
          final discountValue =
              (regularTotal - actualTotal).clamp(0.0, double.infinity);
          final regularAmount = regularTotal.toStringAsFixed(2);
          final discountAmount = discountValue.toStringAsFixed(2);

          // Get route display (just "North" or "South")
          String routeDisplay = (routeDirection == 'north_to_south')
              ? 'North'
              : (routeDirection == 'south_to_north')
                  ? 'South'
                  : 'Unknown';

          // Calculate distance based on origin and destination
          String distance = _calculateDistance(originPlace, destPlace);

          // Get conductor name from AppState (logged-in conductor)
          final conductorName =
              AppState.instance.conductor?['name'] ?? 'Unknown Conductor';

          // Require driver tapped in for printing
          final driver = AppState.instance.driver;
          if (driver == null) {
            // Notify user that driver must tap in
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('No Driver'),
                content: const Text(
                    'No driver has tapped in. Please have the driver tap their card to proceed.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK')),
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
            title: 'WALK-IN TICKET',
            vehicleNo: _assignedBus ?? 'BUS-001',
            date: date,
            time: time,
            from: originPlace,
            to: destPlace,
            distance: distance,
            passengerType: passengerType!,
            route: routeDisplay,
            driverName: driverName,
            conductorName: conductorName,
            payment: "CASH",
            quantity: quantity.toString(),
            amount: totalAmount,
            originalFare: regularAmount,
            discountAmount: discountAmount,
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
            'passengerType': passengerType!,
            'amount': amountDouble,
            'source': 'walkin',
          };
          try {
            await LocalStorage.saveWalkin(walkinRecord);
            await TripRecordLiveService().publishNow(reason: 'walkin');
          } catch (e) {
            debugPrint('[HomeScreen] Failed saving walkin: $e');
          }
          setState(() => passengerType = null);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor:
              passengerType == null ? Colors.grey : Colors.green[700],
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
      debugPrint(
          '[DISTANCE] $origin (${originEntry.km}km) -> $destination (${destEntry.km}km) = ${kmTraveled}km');
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
    bool enabled = true,
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
            final safeValue = options.contains(value)
                ? value
                : (options.isNotEmpty ? options.first : null);
            if (safeValue == null) {
              return Container(
                height: 40,
                alignment: Alignment.centerLeft,
                child: Text('No available destinations',
                    style: TextStyle(color: Colors.grey[600])),
              );
            }
            return DropdownButton<String>(
              isExpanded: true,
              underline: const SizedBox(),
              value: safeValue,
              items: options
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: enabled ? (v) => onChanged(v!) : null,
            );
          }),
        ),
      ],
    );
  }

  /// Conductor authentication dialog for opening Records/Arrival Report.
  void _showConductorAuthDialog(BuildContext context) {
    final activeConductor = AppState.instance.conductor;
    final expectedUid = activeConductor?['uid']?.toString().trim() ?? '';

    if (activeConductor == null || expectedUid.isEmpty) {
      unawaited(Dialogs.showMessage(
        context,
        'Conductor Required',
        'No active conductor is registered for this trip.',
      ));
      return;
    }

    // Reset NFC debounce so conductor card can be read immediately
    NFCReaderModeService.instance.resetDebounce();

    final completer = Completer<void>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        late StreamSubscription<dynamic> nfcSubscription;

        // Set up subscription immediately when builder is called
        nfcSubscription =
            NFCReaderModeService.instance.onTag.listen((data) async {
          try {
            final employee = Map<String, dynamic>.from(data as Map);
            String tappedUid = employee['uid']?.toString() ?? '';
            debugPrint('[CONDUCTOR-AUTH] Tag tapped: $tappedUid');

            if (employee['recognized'] != false) {
              debugPrint(
                  '[CONDUCTOR-AUTH] Card found: ${employee['name']} (role=${employee['role']})');
              if (employee['role'] == 'conductor') {
                final tappedEmployeeUid =
                    employee['uid']?.toString().trim() ?? '';
                if (tappedEmployeeUid != expectedUid) {
                  await Dialogs.showMessage(
                    context,
                    'Not allowed',
                    'Please tap the active conductor ID for this trip.',
                  );
                  return;
                }

                try {
                  nfcSubscription.cancel();
                } catch (_) {}
                if (Navigator.canPop(dialogContext)) {
                  Navigator.pop(dialogContext);
                }

                // Use global navigator key to avoid context issues
                navigatorKey.currentState?.push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RecordsScreen(routeDirection: routeDirection),
                  ),
                );
                if (!completer.isCompleted) {
                  completer.complete();
                }
              } else {
                Dialogs.showMessage(context, 'Not allowed',
                    'Card is ${employee['role']}, not conductor');
              }
            } else {
              debugPrint('[CONDUCTOR-AUTH] Card $tappedUid NOT found');
              Dialogs.showMessage(
                  context, 'Not Found', 'Conductor card not recognized.');
            }
          } catch (e) {
            debugPrint('[CONDUCTOR-AUTH] Error: $e');
          }
        });

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            try {
              nfcSubscription.cancel();
            } catch (_) {}
            if (!completer.isCompleted) completer.complete();
          },
          child: AlertDialog(
            elevation: 10,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Center(
              child: Text(
                'CONDUCTOR AUTHENTICATION',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
            content: Text(
              'Please tap the active conductor ID card for ${activeConductor['name'] ?? 'this trip'}.',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  try {
                    nfcSubscription.cancel();
                  } catch (_) {}
                  if (Navigator.canPop(dialogContext)) {
                    Navigator.pop(dialogContext);
                  }
                  if (!completer.isCompleted) {
                    completer.complete();
                  }
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
