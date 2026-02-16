import 'package:flutter/material.dart';
import 'dart:async';
import '../local_storage.dart';
import '../services/nfc_reader_mode_service.dart';
import '../services/app_state.dart';
import '../models/booking.dart';
import 'home_screen.dart';
import '../utils/dialogs.dart';
// route_selection_screen removed from post-login flow

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _status = 'Tap your ID card at the back of the POS';
  StreamSubscription? _nfcSub;

  @override
  void initState() {
    super.initState();
    // Ensure debounce cleared and subscribe immediately so the login screen
    // can accept a tap right after navigation from logout.
    try {
      NFCReaderModeService.instance.resetDebounce();
    } catch (_) {}

    _nfcSub = NFCReaderModeService.instance.onTag.listen((user) {
      debugPrint('[LOGIN] NFC tag event received: $user');
      final role = (user['role'] ?? '').toString().toLowerCase();

      // Skip inspector card on login screen (handled globally)
      if (role == 'inspector') {
        debugPrint('[LOGIN] inspector card detected, ignoring on login screen');
        return;
      }

      if (role == 'conductor') {
        debugPrint('[LOGIN] conductor detected, calling _handleConductorLogin');
        if (!mounted) {
          debugPrint('[LOGIN] widget not mounted, returning');
          return;
        }
        _handleConductorLogin(user);
      } else {
        final name = user['name'] ?? 'User';
        final roleDisplay = ((user['role'] ?? '').toString());
        if (roleDisplay.isNotEmpty) {
          final display =
              roleDisplay[0].toUpperCase() + roleDisplay.substring(1);
          setState(() {
            _status =
                'Tap accepted for $display $name. Only CONDUCTOR can login on this device.';
          });
        }
      }
    });

    // Initialize local storage
    LocalStorage.init().then((_) {
      // status hint
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _status = 'Tap your ID card at the back of the POS';
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _nfcSub?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  void _handleConductorLogin(Map<String, dynamic> user) {
    debugPrint('[LOGIN] _handleConductorLogin called with user: $user');
    final name = user['name'] ?? 'User';
    debugPrint('[LOGIN] name=$name, mounted=$mounted');

    // Store conductor in AppState so it persists across navigation
    AppState.instance.setConductor(user);
    AppState.instance.setDriver(null); // Clear any previous driver on new login

    // Persist session to storage for app restart recovery
    LocalStorage.saveCurrentConductor(user);

    // Load persisted bookings for this conductor (if any)
    try {
      final uid = user['uid']?.toString();
      if (uid != null && uid.isNotEmpty) {
        BookingManager().loadForConductor(uid);
      }
    } catch (_) {}

    if (!mounted) {
      debugPrint('[LOGIN] widget not mounted, returning');
      return;
    }

    try {
      debugPrint('[LOGIN] navigating to HomeScreen (no route chooser)');
      // Prefer persisted route if present, otherwise default to north_to_south
      final curRoute = LocalStorage.getCurrentRoute();
      String routeDirection = 'north_to_south';
      if (curRoute != null) {
        final rid = curRoute['routeId'];
        if (rid == 'south_to_north') routeDirection = 'south_to_north';
      }

      // Persist last screen as home with chosen routeDirection
      LocalStorage.saveLastScreen(
          'home_screen', {'routeDirection': routeDirection});

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                HomeScreen(routeDirection: routeDirection, conductor: user)),
      );
      debugPrint('[LOGIN] Navigator.pushReplacement to HomeScreen succeeded');
    } catch (e) {
      debugPrint('[LOGIN] ERROR during Navigator.pushReplacement: $e');
    }

    if (mounted) {
      try {
        Dialogs.showMessage(context, 'Welcome', 'Welcome, $name!');
        debugPrint('[LOGIN] dialog shown');
      } catch (e) {
        debugPrint('[LOGIN] error showing dialog: $e');
      }
    }
  }

  Future<void> _loginManual() async {
    final input = _nameController.text.trim();
    if (input.isEmpty) {
      await Dialogs.showMessage(
          context, 'Login', 'Please enter employee name or ID');
      return;
    }

    // Validate against LocalStorage: allow login only if matches an employee record
    final employees = LocalStorage.getAllEmployees();
    Map<String, dynamic>? match;
    final inputLower = input.toLowerCase();
    final inputUidNorm =
        input.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();

    for (final e in employees) {
      final name = (e['name'] ?? '').toString();
      final uid = (e['uid'] ?? '').toString();
      final uidNorm = uid.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();
      if (name.toLowerCase() == inputLower ||
          (uidNorm.isNotEmpty && uidNorm == inputUidNorm)) {
        match = Map<String, dynamic>.from(e);
        break;
      }
    }

    if (match == null) {
      await Dialogs.showMessage(
          context, 'Login failed', 'Not recognized — manual login failed');
      return;
    }

    // Only allow conductors to login on this device
    final role = (match['role'] ?? '').toString().toLowerCase();
    if (role != 'conductor') {
      await Dialogs.showMessage(context, 'Login not allowed',
          'Tap accepted for ${match['role']} ${match['name']}. Only CONDUCTOR can login on this device.');
      return;
    }

    // Successful manual login
    AppState.instance.setConductor(match);
    AppState.instance.setDriver(null);

    // Persist session to storage for app restart recovery
    LocalStorage.saveCurrentConductor(match);

    try {
      final uid = match['uid']?.toString();
      if (uid != null && uid.isNotEmpty) BookingManager().loadForConductor(uid);
    } catch (_) {}

    // Save default route and navigate directly to HomeScreen
    LocalStorage.saveLastScreen(
        'home_screen', {'routeDirection': 'north_to_south'});
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) =>
              HomeScreen(routeDirection: 'north_to_south', conductor: match)),
    );
    if (mounted) {
      await Dialogs.showMessage(
          context, 'Welcome', 'Welcome, ${match['name']}!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenW * 0.07),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: screenW * 0.45,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green[700],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.directions_bus,
                  size: 48,
                  color: Colors.white,
                ),
              ),

              SizedBox(height: screenH * 0.05),

              // NFC status
              Text(
                _status,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              // Manual fallback
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Manual: Employee name or ID',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _loginManual,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text("Login"),
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
