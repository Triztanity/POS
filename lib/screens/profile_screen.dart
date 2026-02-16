import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import '../local_storage.dart';
import '../models/booking.dart';
import '../services/nfc_auth_service.dart';
import '../services/nfc_reader_mode_service.dart';
import '../services/app_state.dart';
// records_screen import removed (manual mode removed)
import '../utils/dialogs.dart';

class ProfileScreen extends StatefulWidget {
  final String? routeInfo; // Display route information
  final Map<String, dynamic>? conductor; // Logged-in conductor info

  const ProfileScreen({super.key, this.routeInfo, this.conductor});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final NFCAuthService _nfc = NFCAuthService();
  Map<String, dynamic>? _driver; // populated after driver taps their card
  bool _scanningDriver = false;
  String _driverStatus = '';
  StreamSubscription<Map<String, dynamic>>? _nfcSub;

  // Driver change authorization state
  bool _waitingForDispatcherApproval = false;
  Map<String, dynamic>?
      _pendingDriver; // Driver waiting for dispatcher approval

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
          "PROFILE",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(screenW * 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "USER INFORMATION",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),
              // Route info display (North / South)
              Text(
                'Route: ${widget.routeInfo ?? 'Unknown'}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800]),
                textAlign: TextAlign.left,
              ),

              const SizedBox(height: 6),
              // Trip info
              _infoRow('TRIP ID', LocalStorage.getCurrentTripId()),
              _infoRow('VEHICLE NO.', LocalStorage.getCurrentVehicleNo(),
                  isValueSmall: true),

              const Divider(thickness: 1),

              // Conductor card is always visible
              _roleCard(screenW, 'conductor'),
              SizedBox(height: screenH * 0.02),

              // Driver card only shown after successful driver tap
              if (_driver != null) _roleCardFromEmp(screenW, _driver!),
              if (_driver == null) _driverTapCard(screenW),

              // Logout Button
              SizedBox(
                width: double.infinity,
                height: screenH * 0.065,
                child: ElevatedButton(
                  onPressed: () async {
                    // Require NFC confirmation: only the same conductor may log out
                    final current = AppState.instance.conductor;
                    if (current == null) {
                      await Dialogs.showMessage(context, 'Error',
                          'No conductor is currently logged in');
                      return;
                    }

                    // Show a modal that immediately starts polling the reader
                    final bool? confirmed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) {
                        String status =
                            'Tap your ID card on the reader to confirm logout';
                        bool loading = true;
                        bool started = false;

                        String norm(String? u) => (u ?? '')
                            .replaceAll(RegExp(r'[^A-Fa-f0-9]'), '')
                            .toUpperCase();
                        final expectedUid = norm(current['uid']?.toString());

                        return StatefulBuilder(
                          builder: (ctx2, setState) {
                            if (!started) {
                              started = true;
                              // Subscribe to ReaderMode events for the duration of the dialog
                              StreamSubscription<Map<String, dynamic>>? sub;
                              sub = NFCReaderModeService.instance.onTag
                                  .listen((user) async {
                                final actualUid = norm(user['uid']?.toString());
                                if (actualUid.isEmpty) {
                                  setState(() {
                                    status = 'No card detected. Waiting...';
                                    loading = false;
                                  });
                                  return;
                                }

                                if (actualUid != expectedUid) {
                                  setState(() {
                                    status = 'Card does not match. Try again.';
                                    loading = false;
                                  });
                                  return;
                                }

                                // Matched: cancel subscription and close dialog with success
                                try {
                                  await sub?.cancel();
                                } catch (_) {}
                                if (Navigator.canPop(ctx2))
                                  Navigator.pop(ctx2, true);
                              });
                            }

                            return AlertDialog(
                              title: const Text('Confirm Logout'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(status),
                                  const SizedBox(height: 12),
                                  if (loading)
                                    const CircularProgressIndicator(),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx2, false);
                                  },
                                  child: const Text('Cancel'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );

                    if (confirmed != true) return;

                    // UID matched and dialog closed: proceed to clear persisted and in-memory bookings and session
                    try {
                      final uid = current['uid']?.toString();
                      if (uid != null && uid.isNotEmpty) {
                        await LocalStorage.deleteBookingsForConductor(uid);
                      }
                    } catch (_) {}
                    // Clear in-memory bookings
                    try {
                      BookingManager().clearBookings();
                    } catch (_) {}

                    // Clear session from both AppState and persistent storage
                    AppState.instance.clearSession();
                    await LocalStorage.clearCurrentConductor();
                    await LocalStorage
                        .clearLastScreen(); // Clear navigation state on logout

                    // Reset ReaderMode debounce and ensure reader mode is active
                    try {
                      NFCReaderModeService.instance.resetDebounce();
                      await NFCReaderModeService.instance.start();
                      // small delay to let native reader initialize
                      await Future.delayed(const Duration(milliseconds: 250));
                    } catch (_) {}

                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "LOG OUT",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Manual mode removed: button intentionally omitted
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Restore driver from AppState if already set
    _driver = AppState.instance.driver;
    debugPrint(
        '[PROFILE] initState: driver from AppState = ${_driver?['name']} uid=${_driver?['uid']}');

    // Subscribe to native ReaderMode for driver tap detection
    _nfcSub = NFCReaderModeService.instance.onTag.listen((user) async {
      debugPrint(
          '[PROFILE] NFC event received: name=${user['name']}, role=${user['role']}, uid=${user['uid']}');
      final role = (user['role'] ?? '').toString().toLowerCase();

      // If waiting for dispatcher approval, check if this is a dispatcher
      if (_waitingForDispatcherApproval) {
        if (role == 'dispatcher') {
          debugPrint(
              '[PROFILE] Dispatcher ${user['name']} approved driver change');
          _approveDriverChange();
        } else {
          debugPrint(
              '[PROFILE] Non-dispatcher tapped during approval wait: $role');
          await Dialogs.showMessage(context, 'Unauthorized',
              'Only dispatchers can approve. Card belongs to $role.');
        }
        return;
      }

      // Normal driver detection
      if (role == 'driver') {
        // Check if this is a different driver than currently registered
        final currentDriverUid = _driver?['uid']?.toString();
        final newDriverUid = user['uid']?.toString();

        if (_driver != null && currentDriverUid != newDriverUid) {
          // Different driver tapped - request dispatcher approval
          debugPrint(
              '[PROFILE] Different driver tapped: ${user['name']} (current: ${_driver!['name']})');
          _showDriverChangeDialog(user);
        } else if (_driver == null) {
          // No driver yet, register immediately
          debugPrint(
              '[PROFILE] Driver detected and _driver is null, storing: ${user['name']}');
          setState(() {
            _driver = user;
            _driverStatus = '';
          });
          AppState.instance.setDriver(user);

          if (mounted) {
            await Dialogs.showMessage(context, 'Driver Detected',
                'DRIVER ${user['name'] ?? '—'} detected');
          }
        } else {
          debugPrint('[PROFILE] Same driver tapped again, ignoring');
        }
      } else {
        debugPrint('[PROFILE] Non-driver role received: $role');
      }
    });
  }

  void _showDriverChangeDialog(Map<String, dynamic> newDriver) {
    final newName = newDriver['name'] ?? '—';
    final currentName = _driver?['name'] ?? '—';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        elevation: 10,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Center(
          child: Text(
            'DRIVER CHANGE AUTHORIZATION',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current driver: $currentName',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'New driver: $newName',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Changing the registered driver requires dispatcher approval.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please tap the dispatcher card to authorize this change.',
              style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _waitingForDispatcherApproval = false;
                _pendingDriver = null;
              });
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    setState(() {
      _waitingForDispatcherApproval = true;
      _pendingDriver = newDriver;
    });
  }

  Future<void> _approveDriverChange() async {
    Navigator.pop(context); // Close dialog

    setState(() {
      _driver = _pendingDriver;
      _driverStatus = '';
      _waitingForDispatcherApproval = false;
      _pendingDriver = null;
    });

    AppState.instance.setDriver(_driver);

    await Dialogs.showMessage(
        context, 'Driver Changed', 'Driver changed to ${_driver!['name']}');
  }

  @override
  void dispose() {
    _nfcSub?.cancel();
    super.dispose();
  }

  Widget _infoRow(String label, String value, {bool isValueSmall = false}) {
    if (!isValueSmall) {
      // Centered, larger layout for role cards
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "$label:",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Flexible(
              child: Text(value,
                  style: TextStyle(fontSize: isValueSmall ? 13 : 14),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _roleCard(double screenW, String role) {
    // For conductor role, use the logged-in conductor passed from LoginScreen
    Map<String, dynamic>? emp;
    if (role == 'conductor' && widget.conductor != null) {
      emp = widget.conductor!;
    } else {
      // Fallback: fetch first employee matching role (for other roles)
      final all = LocalStorage.getAllEmployees();
      emp = all.firstWhere(
          (e) => (e['role'] ?? '').toString().toLowerCase() == role,
          orElse: () => {});
    }

    final name = emp.isEmpty ? '—' : (emp['name'] ?? '—');
    final uid = emp.isEmpty ? null : (emp['uid'] ?? '');
    final masked = uid == null || uid.toString().isEmpty
        ? '****'
        : _maskUid(uid.toString());

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: EdgeInsets.all(screenW * 0.03),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Role label removed; position shown below
            _infoRow('NAME', name),
            _infoRow('Employee ID', masked, isValueSmall: true),
            _infoRow('Position', role[0].toUpperCase() + role.substring(1),
                isValueSmall: true),
          ],
        ),
      ),
    );
  }

  Widget _roleCardFromEmp(double screenW, Map<String, dynamic> emp) {
    final role = (emp['role'] ?? 'driver').toString();
    final name = emp['name'] ?? '—';
    final uid = emp['uid'] ?? '';
    final masked = uid.toString().isEmpty ? '****' : _maskUid(uid.toString());

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: EdgeInsets.all(screenW * 0.03),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Role label removed; position shown below
            _infoRow('NAME', name),
            _infoRow('Employee ID', masked, isValueSmall: true),
            _infoRow('Position', role[0].toUpperCase() + role.substring(1),
                isValueSmall: true),
          ],
        ),
      ),
    );
  }

  Widget _driverTapCard(double screenW) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: _scanningDriver ? null : _scanDriver,
        child: Padding(
          padding: EdgeInsets.all(screenW * 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Driver',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _scanningDriver
                    ? 'Scanning for driver card…'
                    : 'Tap driver card to show details',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              if (_driverStatus.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_driverStatus,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _maskUid(String normalizedUid) {
    // normalizedUid is hex uppercase without separators, e.g. EB4D4506
    final pairs = <String>[];
    for (var i = 0; i < normalizedUid.length; i += 2) {
      if (i + 2 <= normalizedUid.length)
        pairs.add(normalizedUid.substring(i, i + 2));
    }
    if (pairs.isEmpty) return '****';
    // mask all except last pair
    final visible = pairs.last;
    final masked = List.filled(pairs.length - 1, '**');
    final out = [...masked, visible].join(':');
    return out;
  }

  Future<void> _scanDriver() async {
    setState(() {
      _scanningDriver = true;
      _driverStatus = '';
    });

    final uid = await _nfc.pollUid();

    if (!mounted) return;

    if (uid == null) {
      setState(() {
        _driverStatus = 'No NFC tag detected. Re-tap.';
        _scanningDriver = false;
      });
      return;
    }

    final user = LocalStorage.getEmployee(uid);
    if (user == null) {
      setState(() {
        _driverStatus = 'Card not recognized. Contact admin.';
        _scanningDriver = false;
      });
      return;
    }

    final role = (user['role'] ?? '').toString().toLowerCase();
    if (role != 'driver') {
      setState(() {
        _driverStatus = 'Card belongs to $role — only drivers are shown here.';
        _scanningDriver = false;
      });
      return;
    }

    // Valid driver found — show their card
    setState(() {
      _driver = user;
      _scanningDriver = false;
      _driverStatus = '';
    });
  }
}
