import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../local_storage.dart';
import '../models/booking.dart';
import 'app_state.dart';
import 'device_config_service.dart';
import 'pos_device_auth_service.dart';
import 'realtime_count_service.dart';
import 'rtdb_gps_listener_service.dart';

class TripRecordLiveService {
  static final TripRecordLiveService _instance =
      TripRecordLiveService._internal();

  factory TripRecordLiveService() => _instance;

  TripRecordLiveService._internal();

  static const Duration _publishInterval = Duration(seconds: 10);

  Timer? _timer;
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  StreamSubscription<int>? _gpsStationSub;
  StreamSubscription<String>? _appStateSub;
  String? _busNumber;
  String _routeDirection = 'north_to_south';
  String? _lastPublishedTripId;
  String? _lastPublishedSignature;
  bool _running = false;
  bool _publishing = false;

  bool get isRunning => _running;

  Future<void> start({
    required String busNumber,
    required String routeDirection,
  }) async {
    _busNumber = busNumber;
    _routeDirection = routeDirection;

    if (_running) {
      debugPrint('[TripRecordLive] Already running, updating context.');
      unawaited(publishNow(reason: 'context-update'));
      return;
    }

    _running = true;
    _timer = Timer.periodic(
      _publishInterval,
      (_) => unawaited(publishNow(reason: 'timer')),
    );

    _gpsStationSub = RtdbGpsListenerService().stationChanges.listen((_) {
      unawaited(publishNow(reason: 'gps-change'));
    });

    _appStateSub = AppState.instance.changes.listen((reason) {
      unawaited(publishNow(reason: 'app-state:$reason'));
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        unawaited(publishNow(reason: 'online'));
      }
    });

    await publishNow(reason: 'start');
    debugPrint(
        '[TripRecordLive] Started for bus $busNumber ($routeDirection).');
  }

  Future<void> publishNow({String reason = 'manual'}) async {
    if (_publishing) return;
    if (!_isTripActive) {
      debugPrint('[TripRecordLive] Skipped $reason - no active trip or crew.');
      return;
    }

    await _publish(status: 'active', reason: reason);
  }

  Future<bool> publishCompleted({
    String reason = 'completed',
    List<Booking> finalBookings = const [],
    List<Map<String, dynamic>> inspections = const [],
    String? ticketMode,
    String? deviceAndroidId,
  }) async {
    final published = await _publish(
      status: 'completed',
      reason: reason,
      forceZeroPassenger: true,
      arrivalContext: _ArrivalCompletionContext(
        finalBookings: finalBookings,
        inspections: inspections,
        ticketMode: ticketMode,
        deviceAndroidId: deviceAndroidId,
      ),
    );
    await stop();
    return published;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _gpsStationSub?.cancel();
    _gpsStationSub = null;
    await _appStateSub?.cancel();
    _appStateSub = null;
    _running = false;
    debugPrint('[TripRecordLive] Stopped.');
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
    unawaited(_gpsStationSub?.cancel());
    _gpsStationSub = null;
    unawaited(_appStateSub?.cancel());
    _appStateSub = null;
    _running = false;
  }

  bool get _isTripActive {
    final scheduleTripId = _getScheduleTripId(logSkip: false);
    if (scheduleTripId == null) return false;
    if (AppState.instance.tripCancelledLocked) return false;

    final hasConductor = AppState.instance.conductor != null;
    final hasDriver = AppState.instance.driver != null;
    return hasConductor || hasDriver;
  }

  Future<bool> _publish({
    required String status,
    required String reason,
    bool forceZeroPassenger = false,
    _ArrivalCompletionContext? arrivalContext,
  }) async {
    if (_publishing) {
      if (status != 'completed') return false;
      for (var attempt = 0; attempt < 20 && _publishing; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_publishing) return false;
    }
    _publishing = true;

    try {
      final scheduleTripId = _getScheduleTripId();
      if (scheduleTripId == null) return false;

      final signedIn = await POSDeviceAuthService().ensureSignedInWithPosRole();
      if (!signedIn) {
        debugPrint('[TripRecordLive] Skipped $reason - POS auth unavailable.');
        return false;
      }

      final payload = await _buildPayload(
        scheduleTripId: scheduleTripId,
        status: status,
        forceZeroPassenger: forceZeroPassenger,
        arrivalContext: arrivalContext,
      );

      final signature = _buildSignature(payload);
      final isSameTrip = _lastPublishedTripId == scheduleTripId;
      if (status == 'active' &&
          isSameTrip &&
          signature == _lastPublishedSignature) {
        debugPrint(
            '[TripRecordLive] Skipped $reason - payload unchanged for $scheduleTripId.');
        return false;
      }

      final writePayload = <String, dynamic>{
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == 'completed') 'completedAt': FieldValue.serverTimestamp(),
        if (_lastPublishedTripId != scheduleTripId)
          'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('trip_records')
          .doc(scheduleTripId)
          .set(writePayload, SetOptions(merge: true));

      _lastPublishedTripId = scheduleTripId;
      _lastPublishedSignature = signature;
      debugPrint(
          '[TripRecordLive] Published $status snapshot for $scheduleTripId ($reason).');
      return true;
    } catch (e) {
      debugPrint('[TripRecordLive] Publish error ($reason): $e');
      return false;
    } finally {
      _publishing = false;
    }
  }

  Future<Map<String, dynamic>> _buildPayload({
    required String scheduleTripId,
    required String status,
    required bool forceZeroPassenger,
    _ArrivalCompletionContext? arrivalContext,
  }) async {
    final gps = RtdbGpsListenerService();
    final currentPassengerCount = forceZeroPassenger
        ? 0
        : RealtimeCountService.computeOnBoardCount(
            currentStationOrder: gps.currentStationOrder,
            currentStationName: gps.currentStationName,
            routeDirection: _routeDirection,
          );

    final summary = _buildSummary(scheduleTripId, currentPassengerCount);
    if (arrivalContext != null) {
      summary.addAll(_buildFinalSummary(scheduleTripId, arrivalContext));
    }
    final route = LocalStorage.getCurrentRoute();
    final assignedBus = await DeviceConfigService.getAssignedBus();
    final busNumber = (_busNumber?.trim().isNotEmpty ?? false)
        ? _busNumber!.trim()
        : (assignedBus ?? LocalStorage.getCurrentVehicleNo());

    final payload = <String, dynamic>{
      'tripId': scheduleTripId,
      'scheduleTripId': scheduleTripId,
      'status': status,
      'busNumber': busNumber,
      'vehicleNo': LocalStorage.getCurrentVehicleNo(),
      'route': route?['routeName'] ?? '',
      'routeDirection': _routeDirection,
      'currentStation': gps.currentStationName,
      'currentStationOrder': gps.currentStationOrder,
      'conductor': _crewPayload(AppState.instance.conductor),
      'driver': _crewPayload(AppState.instance.driver),
      'summary': summary,
    };

    if (arrivalContext != null) {
      final arrival = _buildArrivalPayload(arrivalContext);
      if (arrival.isNotEmpty) payload['arrival'] = arrival;
      payload['ticketManifest'] = _buildTicketManifest(scheduleTripId);
    }

    return payload;
  }

  Map<String, dynamic> _buildSummary(
    String scheduleTripId,
    int currentPassengerCount,
  ) {
    final bookingRecords = LocalStorage.loadBookingsForTrip(scheduleTripId);
    final walkinRecords = LocalStorage.loadWalkinsForTrip(scheduleTripId);
    final bookings = bookingRecords.map(Booking.fromMap).toList();
    final walkins = walkinRecords.map(_walkinToBooking).toList();

    final totalBookingSales =
        bookings.fold<double>(0, (sum, booking) => sum + booking.amount);
    final totalCashSales =
        walkins.fold<double>(0, (sum, booking) => sum + booking.amount);
    final totalTickets = bookingRecords.length + walkinRecords.length;

    return {
      'currentPassengerCount': currentPassengerCount,
      'totalTickets': totalTickets,
      'bookingCount': bookingRecords.length,
      'walkInCount': walkinRecords.length,
      'totalBookingSales': totalBookingSales,
      'totalCashSales': totalCashSales,
      'totalAmount': totalBookingSales + totalCashSales,
    };
  }

  Map<String, dynamic> _buildFinalSummary(
    String scheduleTripId,
    _ArrivalCompletionContext context,
  ) {
    final sourceBookings = context.finalBookings.isNotEmpty
        ? context.finalBookings
        : _loadFinalBookings(scheduleTripId);
    final expandedPassengers = sourceBookings
        .expand((booking) => booking.expandToIndividualPassengers())
        .toList();

    return {
      'finalPassengerCount': expandedPassengers.length,
      'inspectionsCount': context.inspections.length,
      'ticketTypeCounts': _ticketTypeCounts(expandedPassengers),
    };
  }

  List<Booking> _loadFinalBookings(String scheduleTripId) {
    final bookingRecords = LocalStorage.loadBookingsForTrip(scheduleTripId);
    final walkinRecords = LocalStorage.loadWalkinsForTrip(scheduleTripId);
    return [
      ...bookingRecords.map(Booking.fromMap),
      ...walkinRecords.map(_walkinToBooking),
    ];
  }

  Map<String, int> _ticketTypeCounts(List<Booking> passengers) {
    final counts = {
      'regular': 0,
      'student': 0,
      'senior': 0,
      'pwd': 0,
      'child': 0,
    };

    for (final passenger in passengers) {
      final type = passenger.passengerType.trim().toUpperCase();
      switch (type) {
        case 'STUDENT':
          counts['student'] = counts['student']! + 1;
          break;
        case 'SENIOR':
        case 'SENIOR CITIZEN':
          counts['senior'] = counts['senior']! + 1;
          break;
        case 'PWD':
          counts['pwd'] = counts['pwd']! + 1;
          break;
        case 'CHILD':
          counts['child'] = counts['child']! + 1;
          break;
        case 'REGULAR':
        default:
          counts['regular'] = counts['regular']! + 1;
          break;
      }
    }

    return counts;
  }

  Map<String, dynamic> _buildArrivalPayload(_ArrivalCompletionContext context) {
    final ticketMode = context.ticketMode?.trim();
    final deviceAndroidId = context.deviceAndroidId?.trim();

    return {
      if (ticketMode != null && ticketMode.isNotEmpty) 'ticketMode': ticketMode,
      if (deviceAndroidId != null && deviceAndroidId.isNotEmpty)
        'deviceAndroidId': deviceAndroidId,
    };
  }

  Map<String, dynamic> _buildTicketManifest(String scheduleTripId) {
    final walkinsRaw = LocalStorage.loadWalkinsForTrip(scheduleTripId);
    final bookingsRaw = LocalStorage.loadBookingsForTrip(scheduleTripId);

    return {
      'walkInTickets': _manifestTickets(walkinsRaw, 'W'),
      'bookingTickets': _manifestTickets(bookingsRaw, 'B'),
    };
  }

  List<Map<String, dynamic>> _manifestTickets(
    List<Map<String, dynamic>> records,
    String prefix,
  ) {
    final tickets = <Map<String, dynamic>>[];

    for (var index = 0; index < records.length; index++) {
      final ticket = Map<String, dynamic>.from(records[index]);
      final sourceRecordId = ticket.remove('id')?.toString();
      ticket['ticketNo'] = '$prefix${(index + 1).toString().padLeft(3, '0')}';
      if (sourceRecordId != null && sourceRecordId.isNotEmpty) {
        ticket['sourceRecordId'] = sourceRecordId;
      }
      tickets.add(ticket);
    }

    return tickets;
  }

  Booking _walkinToBooking(Map<String, dynamic> walkin) {
    return Booking(
      id: walkin['id']?.toString() ?? '',
      passengerName: walkin['passengerName']?.toString() ?? 'Walk-in Passenger',
      route: walkin['route']?.toString() ?? '',
      date: walkin['date']?.toString() ?? '',
      time: walkin['time']?.toString() ?? '',
      passengers: _parseInt(walkin['passengers'], fallback: 1),
      fromLocation: walkin['fromLocation']?.toString() ?? '',
      toLocation: walkin['toLocation']?.toString() ?? '',
      passengerType: walkin['passengerType']?.toString() ?? 'REGULAR',
      amount: _parseDouble(walkin['amount']),
      status: walkin['status']?.toString() ?? 'on-board',
      passengerUid: null,
    );
  }

  Map<String, dynamic> _crewPayload(Map<String, dynamic>? crew) {
    if (crew == null) return {'name': ''};
    return {
      'uid': crew['uid']?.toString() ?? '',
      'name': crew['name']?.toString() ?? '',
      'role': crew['role']?.toString() ?? '',
    };
  }

  String? _getScheduleTripId({bool logSkip = true}) {
    final tripId = LocalStorage.getStoredCurrentTripId()?.trim();
    if (tripId == null || tripId.isEmpty) {
      if (logSkip) {
        debugPrint('[TripRecordLive] No stored schedule trip ID; skipping.');
      }
      return null;
    }

    if (tripId.toUpperCase().startsWith('TRIP-')) {
      if (logSkip) {
        debugPrint(
            '[TripRecordLive] Refusing to publish generated trip ID $tripId.');
      }
      return null;
    }

    return tripId;
  }

  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _buildSignature(Map<String, dynamic> payload) {
    return jsonEncode(payload);
  }
}

class _ArrivalCompletionContext {
  final List<Booking> finalBookings;
  final List<Map<String, dynamic>> inspections;
  final String? ticketMode;
  final String? deviceAndroidId;

  const _ArrivalCompletionContext({
    required this.finalBookings,
    required this.inspections,
    this.ticketMode,
    this.deviceAndroidId,
  });
}
