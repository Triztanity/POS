import 'dart:async';
import 'package:flutter/material.dart';
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
import '../services/firebase_dispatch_service.dart';

class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  late String currentTripId;
  late BookingManager _bookingManager;

  @override
  void initState() {
    super.initState();
    currentTripId = LocalStorage.getCurrentTripId();
    _bookingManager = BookingManager();
    _loadBookings();
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
    final assignedBus = await DeviceConfigService.getAssignedBus();
    if (assignedBus == null) {
      debugPrint('⚠️ Unable to determine assigned bus for this device');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to determine assigned bus.')));
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to deploy: $e')));
      return;
    }

    if (claimedTripId == null) {
      debugPrint('⚠️ No pre-departure schedule found for bus $assignedBus');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('No pre-departure schedule found for bus $assignedBus')));
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('New trip deployed: $newTrip (Bus: $assignedBus)')));
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
              if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);

              if (mounted) {
                await _confirmDeployWithRoute(
                    route, employee['uid']?.toString() ?? '');
              }
              if (!completer.isCompleted) completer.complete();
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Invalid card. Expected dispatcher, got ${employee?['role'] ?? 'unknown'}')),
                );
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
            if (!completer.isCompleted) completer.complete();
          },
          child: AlertDialog(
            title: const Text('Dispatcher Confirmation'),
            content: const Text(
                'Please tap your dispatcher ID card to confirm deploy.'),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await nfcSubscription.cancel();
                  } catch (_) {}
                  if (Navigator.canPop(dialogContext))
                    Navigator.pop(dialogContext);
                  if (!completer.isCompleted) completer.complete();
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

  @override
  Widget build(BuildContext context) {
    final walkins = LocalStorage.loadWalkinsForTrip(currentTripId);
    final inspections = LocalStorage.loadInspectionsForTrip(currentTripId);
    final bookingTickets = _bookingManager
        .getBookings()
        .where((b) => b.passengerUid != null)
        .length;
    final allTickets = bookingTickets + walkins.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch'),
        centerTitle: true,
        backgroundColor: Colors.green[800],
        elevation: 2,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
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
                        ],
                      ),
                    ),
                  ],
                ),
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
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.blue[50]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Dispatcher',
                          style:
                              TextStyle(fontSize: 12, color: Colors.black54)),
                      Text('Not assigned',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                        const Text('Summary',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Text('Walk-in tickets for this trip: ${walkins.length}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 6),
                        Text('Booking tickets for this trip: $bookingTickets',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 6),
                        Text('All tickets: $allTickets',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 6),
                        Text('Inspections recorded: ${inspections.length}',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('Actions',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                    'Finalizing will lock all records for this trip and start a new trip session.'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pushReplacement(
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
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Device must be online to deploy.')));
                            return;
                          }

                          // Open route selection in chooser mode
                          final selected =
                              await Navigator.push<Map<String, String>>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RouteSelectionScreen(
                                    returnOnSelect: true)),
                          );
                          if (selected == null) return;

                          await _showDispatcherConfirmDialog(context, selected);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
