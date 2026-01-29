import 'package:flutter/material.dart';
import 'package:senraise_printer/senraise_printer.dart';
import 'screens/splash_screen.dart';
import 'services/device_config_service.dart';
import 'services/app_state.dart';
import 'screens/inspector_screen.dart';
import 'local_storage.dart';
import 'services/nfc_reader_mode_service.dart';
import 'services/inspector_nfc_handler.dart';
import 'services/inspection_sync_service.dart';
import 'services/arrival_report_sync_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Global navigator key for deep linking and inspector navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local offline storage before app starts
  await LocalStorage.init();

  // Initialize Firebase (required for Firestore uploads of arrival reports)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[MAIN] Firebase.initializeApp OK');
  } catch (e) {
    debugPrint('[MAIN] Firebase.initializeApp failed: $e');
  }

  // Device-level auth removed from startup (Option 2: Lazy-Load Device Auth)
  // Device will authenticate on-demand when syncing data to Firestore.
  // This allows app to start instantly and work offline without blocking on Firebase.
  // See: firebase_dispatch_service.dart and arrival_report_sync_service.dart

  // Attempt to auto-detect device and persist assigned bus (must run before UI)
  try {
    final assigned = await DeviceConfigService.autoDetectAndSaveAssignedBus();
    if (assigned != null) {
      debugPrint('Device assigned bus detected: $assigned');
    } else {
      debugPrint('Device assigned bus NOT detected at startup');
    }
  } catch (e) {
    debugPrint('Device auto-detect failed: $e');
  }

  try {
    final version = await SenraisePrinter().getServiceVersion();
    debugPrint("Printer service version: $version");
  } catch (e) {
    debugPrint("Printer not detected: $e");
  }

  runApp(const AfcsApp());
}

class AfcsApp extends StatefulWidget {
  const AfcsApp({super.key});

  @override
  State<AfcsApp> createState() => _AfcsAppState();
}

class _AfcsAppState extends State<AfcsApp> {
  @override
  void initState() {
    super.initState();
    // Start native NFC ReaderMode for reliable tag detection
    NFCReaderModeService.instance.start();
    // Start global NFC listener in AppState so driver taps register app-wide
    AppState.instance.startNfcListener();
    // Initialize inspection sync service (watches for connectivity changes)
    InspectionSyncService();
    // Start arrival report background sync service
    ArrivalReportSyncService();
    
    debugPrint('[MAIN] AfcsApp initState complete');
  }

  @override
  void dispose() {
    NFCReaderModeService.instance.stop();
    InspectorNFCHandler.instance.dispose();
    InspectionSyncService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Initialize inspector NFC handler with the global navigator key
    // This allows it to intercept inspector card taps from any screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[MAIN] Post-frame callback: initializing InspectorNFCHandler');
      InspectorNFCHandler.instance.initialize(navigatorKey);
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "AFCS POS",
      navigatorKey: navigatorKey,
      home: const SplashScreen(),
      routes: {
        '/inspector': (ctx) => InspectorScreen(
          routeDirection: 'north_to_south', // TODO: Get from app state
        ),
      },
    );
  }
}
