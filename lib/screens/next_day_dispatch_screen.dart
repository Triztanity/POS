import 'dart:async';
import 'package:flutter/material.dart';

import '../local_storage.dart';
import '../models/booking.dart';
import '../services/app_state.dart';
import '../services/device_config_service.dart';
import '../services/nfc_reader_mode_service.dart';
import 'login_screen.dart';
import 'dispatch_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'route_selection_screen.dart';
import '../services/firebase_dispatch_service.dart';

class NextDayDispatchScreen extends StatefulWidget {
  const NextDayDispatchScreen({super.key});

  @override
  State<NextDayDispatchScreen> createState() => _NextDayDispatchScreenState();
}

class _NextDayDispatchScreenState extends State<NextDayDispatchScreen> {
  late String currentTripId;

  String? _assignedBus;

  @override
  void initState() {
    super.initState();
    // Persist that app is on this screen so it will restore here on restart
    LocalStorage.saveLastScreen('next_day_dispatch_screen', {});
    currentTripId = LocalStorage.getCurrentTripId();
    _loadAssignedBus();
  }

  Future<void> _loadAssignedBus() async {
    try {
      final b = await DeviceConfigService.getAssignedBus();
      if (mounted)
        setState(() => _assignedBus = b ?? LocalStorage.getCurrentVehicleNo());
    } catch (_) {
      if (mounted)
        setState(() => _assignedBus = LocalStorage.getCurrentVehicleNo());
    }
  }

  Future<void> _confirmDeployWithRoute(
      Map<String, String> route, String dispatcherUid) async {
    final prevConductor = AppState.instance.conductor;
    final prevUid = prevConductor?['uid']?.toString();

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

    // Clear persisted last screen so app won't reopen back to this screen after deploy
    await LocalStorage.clearLastScreen();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _showDispatcherConfirmDialog(
      BuildContext context, Map<String, String> route) async {
    NFCReaderModeService.instance.resetDebounce();
    final completer = Completer<void>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        late StreamSubscription<dynamic> nfcSubscription;
        nfcSubscription =
            NFCReaderModeService.instance.onTag.listen((data) async {
          try {
            final tappedUid = data['uid']?.toString() ?? '';
            final employee = LocalStorage.getEmployee(tappedUid);
            if (employee != null && (employee['role'] ?? '') == 'dispatcher') {
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
    // walkins/inspections not displayed on this screen

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch (Next Day)'),
        centerTitle: true,
        backgroundColor: Colors.green[800],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 6)
                          ],
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Icon(Icons.directions_bus,
                            size: 56, color: Colors.green[800]),
                      ),
                      const SizedBox(height: 12),
                      Text('Next-Day Dispatch',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      if (_assignedBus != null)
                        Text('Vehicle: ${_assignedBus!}',
                            style: TextStyle(color: Colors.grey[700])),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Next-Day Checklist',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            Icon(Icons.battery_charging_full,
                                size: 18, color: Colors.green),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'Charge the device fully before leaving')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            Icon(Icons.print, size: 18, color: Colors.blue),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text('Ensure printer paper is stocked')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            Icon(Icons.wifi, size: 18, color: Colors.indigo),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'Confirm arrival reports have been uploaded (when online)')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            Icon(Icons.checklist_rtl,
                                size: 18, color: Colors.teal),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'Keep this screen open if your shift has ended')),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Padding(
                    padding:
                        EdgeInsets.symmetric(vertical: 14.0, horizontal: 8.0),
                    child: Text('Deploy',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white)),
                  ),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromRGBO(255, 0, 0, 1)),
                  onPressed: () async {
                    final conn = await Connectivity().checkConnectivity();
                    if (conn == ConnectivityResult.none) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Device must be online to deploy.')));
                      return;
                    }

                    final selected = await Navigator.push<Map<String, String>>(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const RouteSelectionScreen(returnOnSelect: true)),
                    );
                    if (selected == null) return;

                    await _showDispatcherConfirmDialog(context, selected);
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    // Navigate back to Dispatch screen and clear last-screen marker
                    await LocalStorage.clearLastScreen();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const DispatchScreen()),
                    );
                  },
                  child: const Text('Return'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
