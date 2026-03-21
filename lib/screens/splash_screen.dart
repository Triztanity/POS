import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_storage.dart';
import '../services/app_state.dart';
import '../models/booking.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Splash screen: checks for saved session on app start.
/// If logged in, navigates to last screen or RouteSelectionScreen.
/// If not, shows LoginScreen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSessionAndNavigate();
  }

  void _checkSessionAndNavigate() {
    // Delay slightly to allow UI to settle
    Future.delayed(const Duration(milliseconds: 300), () async {
      if (!mounted) {
        debugPrint('[SPLASH] Widget not mounted, returning');
        return;
      }

      try {
        debugPrint('[SPLASH] Checking for saved session...');
        final savedConductor = LocalStorage.loadCurrentConductor();
        final currentTripId = LocalStorage.getCurrentTripId();
        final localTripStatus =
            LocalStorage.getCurrentTripStatus().trim().toLowerCase();
        debugPrint('[SPLASH] Local trip status: "$localTripStatus"');

        bool validTrip = false;
        // Trust local trip status if available
        if (localTripStatus == 'departed') {
          validTrip = true;
        } else if (currentTripId.isNotEmpty) {
          // Fallback: Check Firebase for trip status ONLY if local status is missing/empty
          try {
            final tripDoc = await FirebaseFirestore.instance
                .collection('trips')
                .doc(currentTripId)
                .get();
            final tripData = tripDoc.data();
            final statusRaw = tripData != null && tripData['status'] != null
                ? tripData['status'].toString().trim().toLowerCase()
                : '';
            debugPrint(
                '[SPLASH] Trip $currentTripId status from Firestore: "$statusRaw"');
            if (statusRaw == 'departed') {
              validTrip = true;
            }
          } catch (e) {
            debugPrint('[SPLASH] Error checking trip in Firebase: $e');
            // If Firestore fails, DO NOT clear session; trust local state if tripId exists
            if (currentTripId.isNotEmpty) {
              validTrip = true;
            }
          }
        }

        final savedDriver = LocalStorage.loadCurrentDriver();

        if (savedConductor != null && savedDriver != null && validTrip) {
          // Session and valid trip exist — restore conductor to AppState
          debugPrint(
              '[SPLASH] Found saved session: ${savedConductor['name']} & ${savedDriver['name']} with valid trip $currentTripId');
          AppState.instance.setConductor(savedConductor);
          AppState.instance.setDriver(savedDriver);

          // Load persisted bookings for this conductor
          try {
            final uid = savedConductor['uid']?.toString();
            if (uid != null && uid.isNotEmpty) {
              BookingManager().loadForConductor(uid);
              debugPrint('[SPLASH] Loaded bookings for conductor $uid');
            }
          } catch (e) {
            debugPrint('[SPLASH] Error loading bookings: $e');
          }

          // Check if there's a last screen to restore
          final lastScreen = LocalStorage.loadLastScreen();
          debugPrint('[SPLASH] Last screen data: $lastScreen');

          if (!mounted) return;

          if (lastScreen != null && lastScreen['name'] == 'home_screen') {
            // Restore to HomeScreen with saved params
            final paramsData = lastScreen['params'] as dynamic;
            final params = paramsData is Map
                ? Map<String, dynamic>.from(paramsData)
                : null;
            debugPrint('[SPLASH] Restoring to HomeScreen with params: $params');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => HomeScreen(
                  routeDirection: params?['routeDirection'] as String?,
                  conductor: savedConductor,
                ),
              ),
            );
          } else {
            // No last screen saved — go directly to HomeScreen with default route
            debugPrint(
                '[SPLASH] No last screen saved, navigating to HomeScreen with default route');
            LocalStorage.saveLastScreen(
                'home_screen', {'routeDirection': 'north_to_south'});
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => HomeScreen(
                  routeDirection: 'north_to_south',
                  conductor: savedConductor,
                ),
              ),
            );
          }
        } else {
          // No valid trip/session — show Login screen
          debugPrint(
              '[SPLASH] No valid trip/session, clearing state and showing Login');
          await LocalStorage.clearSession();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } catch (e) {
        debugPrint('[SPLASH] ERROR in _checkSessionAndNavigate: $e');
        if (mounted) {
          // On error, show Login screen
          await LocalStorage.clearSession();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Text(
              'AFCS POS',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
            ),
            const SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.green[700]),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
