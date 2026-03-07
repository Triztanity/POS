import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_storage.dart';
import '../models/booking.dart';
import '../services/app_state.dart';
import '../services/device_config_service.dart';
import '../services/nfc_reader_mode_service.dart';
// pos auth and tripDetails uploads removed — schedule claim flow handles dispatch
import 'login_screen.dart';
import 'next_day_dispatch_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'route_selection_screen.dart';
import '../utils/dialogs.dart';
import '../services/firebase_dispatch_service.dart';

class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  late String currentTripId;
  late BookingManager _bookingManager;
  StreamSubscription<QuerySnapshot>? _scheduleSubscription;

  @override
  void initState() {
    super.initState();
    currentTripId = LocalStorage.getCurrentTripId();
    _bookingManager = BookingManager();
    _loadBookings();
    _listenNextSchedule();
  }

  @override
  void dispose() {
    _scheduleSubscription?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? _nextSchedule;
  bool _loadingSchedule = true;

  Future<void> _listenNextSchedule() async {
    try {
      var bus = await DeviceConfigService.getAssignedBus();
      bus ??= await DeviceConfigService.autoDetectAndSaveAssignedBus();
      if (bus == null) {
        if (mounted) setState(() => _loadingSchedule = false);
        return;
      }
      _scheduleSubscription = FirebaseFirestore.instance
          .collection('schedules')
          .where('busNumber', isEqualTo: bus)
          .where('status', isEqualTo: 'pre-departure')
          .limit(1)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        if (snapshot.docs.isNotEmpty) {
          setState(() {
            _nextSchedule = snapshot.docs.first.data();
            _loadingSchedule = false;
          });
        } else {
          setState(() {
            _nextSchedule = null;
            _loadingSchedule = false;
          });
        }
      }, onError: (e) {
        debugPrint('[Dispatch] Schedule listener error: $e');
        if (mounted) setState(() => _loadingSchedule = false);
      });
    } catch (e) {
      debugPrint('[Dispatch] Error setting up schedule listener: $e');
      if (mounted) setState(() => _loadingSchedule = false);
    }
  }

  void _loadBookings() {
    try {
      final conductor = AppState.instance.conductor;
      final uid = conductor?['uid']?.toString();
      if (uid != null && uid.isNotEmpty) {
        _bookingManager.loadForConductor(uid);
      }
    } catch (_) {}
  }

  Future<void> _confirmDeployWithRoute(
      Map<String, String> route, String dispatcherUid) async {
    // Capture previous conductor uid before clearing session
    final prevConductor = AppState.instance.conductor;
    final prevUid = prevConductor?['uid']?.toString();

    // Ensure device has assigned bus
    var assignedBus = await DeviceConfigService.getAssignedBus();
    assignedBus ??= await DeviceConfigService.autoDetectAndSaveAssignedBus();
    if (assignedBus == null) {
      debugPrint('⚠️ Unable to determine assigned bus for this device');
      if (mounted) {
        await Dialogs.showMessage(
            context, 'Error', 'Unable to determine assigned bus.');
      }
      return;
    }

    String? claimedTripId;
    try {
      claimedTripId = await FirebaseDispatchService().claimAndDispatchSchedule(
        busNumber: assignedBus,
        route: route,
        dispatcherUid: dispatcherUid,
      );
    } catch (e) {
      debugPrint(
          '⚠️ Failed to claim and dispatch schedule for $assignedBus: $e');
      if (mounted) {
        await Dialogs.showMessage(context, 'Error', 'Failed to deploy: $e');
      }
      return;
    }

    if (claimedTripId == null) {
      debugPrint('⚠️ No pre-departure schedule found for bus $assignedBus');
      if (mounted) {
        await Dialogs.showMessage(context, 'Info',
            'No pre-departure schedule found for bus $assignedBus');
      }
      return;
    }

    final newTrip = claimedTripId;
    await LocalStorage.setCurrentTripId(newTrip);
    await LocalStorage.setCurrentVehicleNo(assignedBus);
    await LocalStorage.resetTripState(newTrip);

    try {
      BookingManager().clearBookings();
      if (prevUid != null && prevUid.isNotEmpty) {
        await LocalStorage.deleteBookingsForConductor(prevUid);
      }
    } catch (_) {}

    await LocalStorage.clearCurrentConductor();
    await LocalStorage.clearCurrentDriver();
    AppState.instance.clearSession();

    // Persist route into local session
    try {
      await LocalStorage.setCurrentRoute(
          route['routeId'] ?? '', route['routeName'] ?? '');
    } catch (_) {}

    if (!mounted) {
      return;
    }
    await Dialogs.showMessage(
        context, 'Deployed', 'New trip deployed: $newTrip (Bus: $assignedBus)');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// Shows a dialog instructing the dispatcher to tap their NFC ID to confirm deploy.
  Future<void> _showDispatcherConfirmDialog(
      BuildContext context, Map<String, String> route) async {
    // Reset NFC debounce so dispatcher card can be read immediately
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
            debugPrint('[DISPATCH-CONFIRM] Tag detected: ${data['uid']}');
            final tappedUid = data['uid']?.toString() ?? '';
            final employee = LocalStorage.getEmployee(tappedUid);
            debugPrint(
                '[DISPATCH-CONFIRM] Employee: ${employee?['name']} (role=${employee?['role']})');

            if (employee != null && (employee['role'] ?? '') == 'dispatcher') {
              debugPrint(
                  '[DISPATCH-CONFIRM] Valid dispatcher, closing dialog and deploying');
              try {
                await nfcSubscription.cancel();
              } catch (_) {}
              if (Navigator.canPop(dialogContext)) {
                Navigator.pop(dialogContext);
              }

              if (mounted) {
                await _confirmDeployWithRoute(
                    route, employee['uid']?.toString() ?? '');
              }
              if (!completer.isCompleted) {
                completer.complete();
              }
            } else {
              if (mounted) {
                Dialogs.showMessage(context, 'Invalid card',
                    'Invalid card. Expected dispatcher, got ${employee?['role'] ?? 'unknown'}',
                    icon: Icons.error, iconColor: Colors.red);
              }
            }
          } catch (e) {
            debugPrint('[DISPATCH-CONFIRM] Error: $e');
          }
        });

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) async {
            try {
              await nfcSubscription.cancel();
            } catch (_) {}
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          child: AlertDialog(
            elevation: 10,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Center(
              child: Text(
                'DISPATCHER CONFIRMATION',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
            content: const Text(
              'Please tap your dispatcher ID card to confirm deploy.',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await nfcSubscription.cancel();
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

    await completer.future;
  }

  String _getRouteFromSchedule(Map<String, dynamic> schedule) {
    final route = schedule['routeName']?.toString();
    if (route != null && route.isNotEmpty) return route;
    // Derive from routeId if available
    final routeId = schedule['routeId']?.toString() ?? '';
    if (routeId.contains('north')) return 'Nasugbu to Batangas';
    if (routeId.contains('south')) return 'Batangas to Nasugbu';
    return 'Not assigned';
  }

  String _getScheduledTime(Map<String, dynamic> schedule) {
    final time = schedule['scheduledTime'];
    if (time is Timestamp) {
      final dt = time.toDate();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
    }
    if (time is String && time.isNotEmpty) return time;
    return 'Not set';
  }

  @override
  Widget build(BuildContext context) {
    final walkins = LocalStorage.loadWalkinsForTrip(currentTripId);
    final inspections = LocalStorage.loadInspectionsForTrip(currentTripId);
    final bookingTickets = _bookingManager
        .getBookings()
        .where((b) => b.passengerUid != null)
        .length;
    final allTickets = bookingTickets + walkins.length;

    return PopScope(
      canPop: false,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch'),
        centerTitle: true,
        backgroundColor: Colors.green[800],
        elevation: 2,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top content
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Finalize Trip',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Trip ID: $currentTripId',
                      style: TextStyle(
                          color: Colors.grey[700], fontSize: 11)),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10.0, vertical: 10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Trip Crew',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Driver',
                                  style: TextStyle(
                                      color: Colors.black54, fontSize: 11)),
                              Text(
                                  LocalStorage.loadCurrentDriver()?['name']
                                          ?.toString() ??
                                      'Not assigned',
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Conductor',
                                  style: TextStyle(
                                      color: Colors.black54, fontSize: 11)),
                              Text(
                                  LocalStorage.loadCurrentConductor()?['name']
                                          ?.toString() ??
                                      'Not assigned',
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Route display - expanded to fill center
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _loadingSchedule
                      ? const CircularProgressIndicator()
                      : _nextSchedule != null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('NEXT SCHEDULE',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black54)),
                                const SizedBox(height: 12),
                                Text(
                                  _nextSchedule!['route']?.toString() ??
                                      _getRouteFromSchedule(_nextSchedule!),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[800],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _getScheduledTime(_nextSchedule!),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            )
                          : const Text('No upcoming schedule',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.black54)),
                ),
              ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  const Text(
                      'Finalizing will lock all records for this trip and start a new trip session.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NextDayDispatchScreen()),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                          child: const Text('Next-Day Dispatch',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Deploy',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white)),
                          ),
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color.fromRGBO(255, 0, 0, 1)),
                          onPressed: () async {
                            final conn = await Connectivity().checkConnectivity();
                            if (conn == ConnectivityResult.none) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Device must be online to deploy.')));
                              }
                              return;
                            }

                            if (_nextSchedule == null) {
                              if (mounted) {
                                await Dialogs.showMessage(context, 'No Schedule',
                                    'No upcoming schedule found to deploy.');
                              }
                              return;
                            }

                            // Auto-select route from the Firebase schedule
                            final route = <String, String>{
                              'routeId': _nextSchedule!['routeId']?.toString() ?? '',
                              'routeName': _nextSchedule!['route']?.toString() ??
                                  _nextSchedule!['routeName']?.toString() ?? '',
                            };

                            await _showDispatcherConfirmDialog(context, route);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
