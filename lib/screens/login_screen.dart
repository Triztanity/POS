import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../local_storage.dart';
import '../services/nfc_reader_mode_service.dart';
import '../services/app_state.dart';
import '../services/device_config_service.dart';
import '../services/pos_device_auth_service.dart';
import '../models/booking.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  StreamSubscription? _nfcSub;
  StreamSubscription<QuerySnapshot>? _scheduleSub;

  Map<String, dynamic>? _schedule;
  bool _loadingSchedule = true;
  String _assignedBus = '';

  // Scanned crew (null = not scanned yet)
  Map<String, dynamic>? _conductor;
  Map<String, dynamic>? _driver;

  String _status = 'Waiting for schedule...';

  @override
  void initState() {
    super.initState();
    AppState.instance.setCurrentScreen('login_screen');
    unawaited(_bootstrapLogin());
  }

  @override
  void dispose() {
    _nfcSub?.cancel();
    _scheduleSub?.cancel();
    super.dispose();
  }

  // ─── Schedule Listener ───────────────────────────────────────────────

  Future<void> _bootstrapLogin() async {
    if (mounted) {
      setState(() {
        _loadingSchedule = true;
        _status = 'Signing in POS device...';
      });
    }

    final signedIn = await POSDeviceAuthService().ensureSignedInWithPosRole();
    if (!mounted) return;

    if (!signedIn) {
      setState(() {
        _loadingSchedule = false;
        _status = 'Firebase login failed. Check POS device registration.';
      });
      return;
    }

    await _initScheduleListener();
    if (!mounted) return;
    _initNfc();
  }

  Future<void> _initScheduleListener() async {
    var bus = await DeviceConfigService.getAssignedBus();
    bus ??= await DeviceConfigService.autoDetectAndSaveAssignedBus();
    if (bus == null) {
      if (mounted) {
        setState(() {
          _loadingSchedule = false;
          _status = 'Device not registered to any bus.';
        });
      }
      return;
    }
    _assignedBus = bus;

    _scheduleSub = FirebaseFirestore.instance
        .collection('schedules')
        .where('busNumber', isEqualTo: bus)
        .where('status', whereIn: ['pre-departure', 'departed'])
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          if (snapshot.docs.isNotEmpty) {
            final docs = snapshot.docs.toList();

            docs.sort((a, b) {
              final dataA = a.data();
              final dataB = b.data();
              final sA = (dataA['status'] ?? '').toString().toLowerCase();
              final sB = (dataB['status'] ?? '').toString().toLowerCase();

              // 1. Departed takes absolute priority (ongoing trip)
              if (sA == 'departed' && sB != 'departed') {
                return -1;
              }
              if (sB == 'departed' && sA != 'departed') {
                return 1;
              }

              // 2. Otherwise sort by scheduledTime (earliest first)
              final timeA = dataA['scheduledTime'];
              final timeB = dataB['scheduledTime'];

              DateTime? dtA;
              if (timeA is Timestamp) {
                dtA = timeA.toDate();
              } else if (timeA is String) {
                dtA = DateTime.tryParse(timeA);
              }

              DateTime? dtB;
              if (timeB is Timestamp) {
                dtB = timeB.toDate();
              } else if (timeB is String) {
                dtB = DateTime.tryParse(timeB);
              }

              if (dtA != null && dtB != null) return dtA.compareTo(dtB);
              if (dtA != null) return -1;
              if (dtB != null) return 1;
              return 0;
            });

            final data = docs.first.data();
            setState(() {
              _schedule = data;
              _loadingSchedule = false;
              _updateStatus();
            });
          } else {
            setState(() {
              _schedule = null;
              _loadingSchedule = false;
              _status = 'No active schedule for $_assignedBus';
            });
          }
        }, onError: (e) {
          debugPrint('[LOGIN] Schedule listener error: $e');
          if (mounted) setState(() => _loadingSchedule = false);
        });
  }

  // ─── NFC Listener ────────────────────────────────────────────────────

  void _initNfc() {
    try {
      NFCReaderModeService.instance.resetDebounce();
    } catch (_) {}

    _nfcSub = NFCReaderModeService.instance.onTag.listen((user) async {
      debugPrint('[LOGIN] NFC tag: $user');
      final recognized = user['recognized'] != false;
      final role = (user['role'] ?? '').toString().toLowerCase();

      if (!recognized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Card not recognized or disabled.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ));
        }
        return;
      }

      if (role == 'inspector') {
        debugPrint('[LOGIN] inspector card, ignoring');
        return;
      }

      if (!mounted) return;

      if (role != 'conductor' && role != 'driver') {
        return;
      }

      if (user['resolvedFromFirebase'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Firebase employee validation required for login.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ));
        }
        return;
      }

      if (!_isScheduleReady()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Schedule Not Ready.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ));
        }
        return;
      }

      if (role == 'conductor') {
        setState(() {
          _conductor = user;
          _updateStatus();
        });
        AppState.instance.setConductor(user);
        await LocalStorage.saveCurrentConductor(user);
      } else if (role == 'driver') {
        setState(() {
          _driver = user;
          _updateStatus();
        });
        AppState.instance.setDriver(user);
        await LocalStorage.saveCurrentDriver(user);
      }

      // Check if both are scanned and schedule is ready
      _tryNavigate();
    });
  }

  // ─── Navigation Logic ────────────────────────────────────────────────

  void _updateStatus() {
    final scheduleReady = _isScheduleReady();
    final hasConductor = _conductor != null;
    final hasDriver = _driver != null;

    if (_schedule == null) {
      _status = 'No active schedule for $_assignedBus';
    } else if (!scheduleReady) {
      _status = 'Schedule Not Ready.';
    } else if (!hasConductor && !hasDriver) {
      _status = 'Schedule READY — Scan Conductor & Driver ID cards to begin.';
    } else if (!hasConductor) {
      _status = 'Driver scanned ✓ — Now scan Conductor ID card.';
    } else if (!hasDriver) {
      _status = 'Conductor scanned ✓ — Now scan Driver ID card.';
    } else {
      _status = 'Both scanned ✓ — Logging in...';
    }
  }

  bool _isScheduleReady() {
    if (_schedule == null) return false;
    final status = (_schedule!['status'] ?? '').toString().toLowerCase();
    return status == 'departed';
  }

  void _tryNavigate() {
    if (_conductor == null || _driver == null) return;

    if (!_isScheduleReady()) {
      // Both scanned but schedule not ready
      return;
    }

    // Save trip info from the schedule
    _saveTripFromSchedule();

    // Load bookings
    try {
      final uid = _conductor!['uid']?.toString();
      if (uid != null && uid.isNotEmpty) {
        BookingManager().loadForConductor(uid);
      }
    } catch (_) {}

    final curRoute = LocalStorage.getCurrentRoute();
    String routeDirection = _routeDirectionFromRoute(curRoute);

    // Use schedule route if available
    if (_schedule != null) {
      final routeId = (_schedule!['routeId'] ?? '').toString();
      if (routeId == 'south_to_north' || routeId == 'north_to_south') {
        routeDirection = routeId;
      } else {
        final routeName = (_schedule!['route'] ??
                _schedule!['routeName'] ??
                _schedule!['busRoute'] ??
                '')
            .toString()
            .toLowerCase();
        if (routeName.startsWith('batangas')) routeDirection = 'south_to_north';
        if (routeName.startsWith('nasugbu')) routeDirection = 'north_to_south';
      }
    }

    LocalStorage.saveLastScreen(
        'home_screen', {'routeDirection': routeDirection});

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          routeDirection: routeDirection,
          conductor: _conductor!,
        ),
      ),
    );
  }

  Future<void> _saveTripFromSchedule() async {
    if (_schedule == null) return;
    final tripId = (_schedule!['tripId'] ?? '').toString();
    if (tripId.isNotEmpty) {
      await LocalStorage.setCurrentTripId(tripId);
    }
    if (_assignedBus.isNotEmpty) {
      await LocalStorage.setCurrentVehicleNo(_assignedBus);
    }
    // Save route
    try {
      final routeId = (_schedule!['routeId'] ?? '').toString();
      final routeName = (_schedule!['route'] ??
              _schedule!['routeName'] ??
              _schedule!['busRoute'] ??
              '')
          .toString();
      if (routeId.isNotEmpty || routeName.isNotEmpty) {
        await LocalStorage.setCurrentRoute(routeId, routeName);
      }
    } catch (_) {}
  }

  String _routeDirectionFromRoute(Map<String, String>? curRoute) {
    if (curRoute != null) {
      final rid = curRoute['routeId'] ?? '';
      if (rid == 'south_to_north') return 'south_to_north';
      if (rid == 'north_to_south') return 'north_to_south';
      final rname = (curRoute['routeName'] ?? '').toLowerCase();
      if (rname.startsWith('batangas')) return 'south_to_north';
      if (rname.startsWith('nasugbu')) return 'north_to_south';
    }
    return 'north_to_south';
  }

  // ─── Build UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                EdgeInsets.symmetric(horizontal: screenW * 0.06, vertical: 16),
            child: Column(
              children: [
                // ── Header ──
                Container(
                  width: screenW * 0.35,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[700],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.directions_bus,
                      size: 40, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'StarExpress POS',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.green[800],
                  ),
                ),
                if (_assignedBus.isNotEmpty)
                  Text(
                    _assignedBus,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),

                SizedBox(height: screenH * 0.02),

                // ── Schedule Card ──
                _buildScheduleCard(),

                const SizedBox(height: 12),

                // ── Crew Cards Row ──
                Row(
                  children: [
                    Expanded(
                        child: _buildCrewCard(
                            'CONDUCTOR', _conductor, Colors.green)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _buildCrewCard('DRIVER', _driver, Colors.blue)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleCard() {
    if (_loadingSchedule) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_schedule == null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.event_busy, size: 36, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                'No Active Schedule',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Waiting for dispatcher to create a schedule for $_assignedBus',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    final status = (_schedule!['status'] ?? '').toString().toLowerCase();
    final isReady = status == 'departed';
    final routeName = (_schedule!['route'] ??
            _schedule!['routeName'] ??
            _schedule!['busRoute'] ??
            '')
        .toString();
    final rawTime = _schedule!['scheduledTime'];

    String formattedTime = '';
    if (rawTime is Timestamp) {
      formattedTime = DateFormat('h:mm a').format(rawTime.toDate());
    } else if (rawTime is String && rawTime.isNotEmpty) {
      final parsed = DateTime.tryParse(rawTime);
      formattedTime =
          parsed != null ? DateFormat('h:mm a').format(parsed) : rawTime;
    } else if (rawTime != null) {
      formattedTime = rawTime.toString();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with status badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ACTIVE SCHEDULE',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isReady ? Colors.green[600] : Colors.orange[700],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isReady ? 'READY' : 'NOT READY',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Details
            if (routeName.isNotEmpty) _scheduleRow('Trip', routeName),
            if (formattedTime.isNotEmpty) _scheduleRow('Time', formattedTime),
            _scheduleRow('Bus', _assignedBus),
          ],
        ),
      ),
    );
  }

  Widget _scheduleRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrewCard(
      String title, Map<String, dynamic>? crew, MaterialColor accent) {
    final scanned = crew != null;
    final name = crew?['name'] ?? '—';
    final letter = crew?['letter'] ?? '';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: scanned ? accent[50] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent[800],
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Icon(
              scanned ? Icons.check_circle : Icons.person_outline,
              size: 28,
              color: scanned ? accent[700] : Colors.grey[400],
            ),
            const SizedBox(height: 4),
            Text(
              scanned ? name : '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scanned ? accent[900] : Colors.grey[500],
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            if (letter.isNotEmpty)
              Text(
                letter,
                style: TextStyle(fontSize: 10, color: accent[600]),
              ),
          ],
        ),
      ),
    );
  }
}
