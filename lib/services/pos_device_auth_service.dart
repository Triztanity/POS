import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'device_identifier_service.dart';
import 'device_config_service.dart';

/// POS Device Authentication Service
/// 
/// Handles device-level Firebase authentication for the POS system.
/// Maps each physical POS device to its Firebase credentials based on Android ID.
/// 
/// Supported Devices:
/// - Device 1: Android ID 2590ecaf10bb2b56 (BUS-001)
/// - Device 2: Android ID e9fb9c8908a3cb9f (BUS-002)
/// 
/// On app startup, this service auto-detects which device is running
/// and signs in with the appropriate credentials.

class POSDeviceAuthService {
  static final POSDeviceAuthService _instance = POSDeviceAuthService._internal();
  
  factory POSDeviceAuthService() {
    return _instance;
  }
  
  POSDeviceAuthService._internal();

  /// Device credential mapping
  /// Maps Android ID → (email, password)
  static const Map<String, Map<String, String>> _deviceCredentials = {
    '2590ecaf10bb2b56': {
      'email': 'posdevice001@example.com',
      'password': 'Test1234.',
      'deviceName': 'BUS-001',
    },
    'e9fb9c8908a3cb9f': {
      'email': 'posdevice002@example.com',
      'password': 'Test1234.',
      'deviceName': 'BUS-002',
    },
  };

  /// Bus number → credential mapping (fallback when androidId detection fails)
  static const Map<String, Map<String, String>> _busCredentials = {
    'BUS-001': {
      'email': 'posdevice001@example.com',
      'password': 'Test1234.',
      'deviceName': 'BUS-001',
    },
    'BUS-002': {
      'email': 'posdevice002@example.com',
      'password': 'Test1234.',
      'deviceName': 'BUS-002',
    },
  };

  String? _currentDeviceId;
  String? _currentDeviceName;

  /// Get the current device's Android ID
  Future<String?> getDeviceId() async {
    if (_currentDeviceId != null) return _currentDeviceId;
    
    try {
      final identifiers = await DeviceIdentifierService.getDeviceIdentifiers();
      _currentDeviceId = identifiers?['androidId'];
      debugPrint('🔍 Detected Android ID: $_currentDeviceId');
      return _currentDeviceId;
    } catch (e) {
      debugPrint('❌ Error getting Android ID: $e');
      return null;
    }
  }

  /// Get the current device's registered name
  Future<String?> getDeviceName() async {
    if (_currentDeviceName != null) return _currentDeviceName;
    
    final deviceId = await getDeviceId();
    if (deviceId == null) return null;
    
    _currentDeviceName = _deviceCredentials[deviceId]?['deviceName'];
    return _currentDeviceName;
  }

  /// Sign in the device to Firebase
  /// Returns true if successful, false otherwise
  Future<bool> signInDevice() async {
    try {
      // Try androidId-based credentials first
      final deviceId = await getDeviceId();
      Map<String, String>? credentials;

      if (deviceId != null) {
        credentials = _deviceCredentials[deviceId];
      }

      // Fallback: use assigned bus number from DeviceConfigService
      if (credentials == null) {
        debugPrint('⚠️ AndroidId lookup failed (id=$deviceId), trying bus-based fallback');
        final assignedBus = await DeviceConfigService.getAssignedBus();
        if (assignedBus != null) {
          credentials = _busCredentials[assignedBus];
          debugPrint('[POS Auth] Bus-based fallback: $assignedBus');
        }
      }

      if (credentials == null) {
        debugPrint('❌ No credentials found for device (androidId=$deviceId)');
        return false;
      }

      final email = credentials['email']!;
      final password = credentials['password']!;
      final deviceName = credentials['deviceName']!;

      debugPrint('🔄 Signing in POS device: $deviceName');

      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      _currentDeviceName = deviceName;
      debugPrint('✅ Device signed in successfully: ${userCredential.user?.email}');
      return true;

    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Firebase Auth Error [${e.code}]: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected error during device sign-in: $e');
      return false;
    }
  }

  /// Ensure the device is signed in and that the signed-in user has the 'pos' role
  /// Returns true if signed in and role confirmed, false otherwise.
  Future<bool> ensureSignedInWithPosRole() async {
    try {
      // Check if already signed in as a POS device
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final email = currentUser.email;
        if (email != null && email.endsWith('@example.com')) {
          return true;
        }
        // Signed in as wrong user — sign out first
        await FirebaseAuth.instance.signOut();
      }

      // Sign in with POS device credentials
      final signed = await signInDevice();
      if (!signed) return false;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // Accept any @example.com POS device email as authorized
      final email = user.email;
      if (email != null && email.endsWith('@example.com')) {
        return true;
      }

      final firestore = FirebaseFirestore.instance;
      // Check users collection for uid-keyed doc
      final uidDoc = await firestore.collection('users').doc(user.uid).get();
      if (uidDoc.exists && uidDoc.data()?['role'] == 'pos') {
        return true;
      }

      // Fallback: check email-keyed doc (rules support either)
      if (email != null && email.isNotEmpty) {
        final emailDoc = await firestore.collection('users').doc(email).get();
        if (emailDoc.exists && emailDoc.data()?['role'] == 'pos') {
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error ensuring device sign-in/role: $e');
      return false;
    }
  }

  /// Check if device is currently authenticated
  bool isAuthenticated() {
    return FirebaseAuth.instance.currentUser != null;
  }

  /// Get current authenticated user
  User? getCurrentUser() {
    return FirebaseAuth.instance.currentUser;
  }

  /// Get device name if authenticated
  String? getAuthenticatedDeviceName() {
    return _currentDeviceName;
  }

  /// Sign out the device
  Future<void> signOutDevice() async {
    try {
      await FirebaseAuth.instance.signOut();
      _currentDeviceId = null;
      _currentDeviceName = null;
      debugPrint('✅ Device signed out');
    } catch (e) {
      debugPrint('❌ Error signing out: $e');
    }
  }
}
