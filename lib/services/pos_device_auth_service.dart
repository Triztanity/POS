import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'device_identifier_service.dart';

/// POS Device Authentication Service
/// 
/// Handles device-level Firebase authentication for the POS system.
/// Maps each physical POS device to its Firebase credentials based on Android ID.
/// 
/// Supported Devices:
/// - Device 1: Android ID e48d8154b4dc3378 (BUS-001)
/// - Device 2: Android ID ca04c9993ebc9f65 (BUS-002)
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
    'e48d8154b4dc3378': {
      'email': 'posdevice001@example.com',
      'password': 'Test1234.',
      'deviceName': 'BUS-001',
    },
    'ca04c9993ebc9f65': {
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
      final deviceId = await getDeviceId();
      
      if (deviceId == null) {
        debugPrint('❌ Could not get device Android ID');
        return false;
      }

      final credentials = _deviceCredentials[deviceId];
      
      if (credentials == null) {
        debugPrint('❌ Device ID not registered: $deviceId');
        debugPrint('⚠️ Registered devices: ${_deviceCredentials.keys.join(", ")}');
        return false;
      }

      final email = credentials['email']!;
      final password = credentials['password']!;
      final deviceName = credentials['deviceName']!;

      debugPrint('🔄 Signing in POS device: $deviceName ($deviceId)');

      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      _currentDeviceName = deviceName;
      debugPrint('✅ Device signed in successfully: ${userCredential.user?.email}');
      return true;

    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Firebase Auth Error [${e.code}]: ${e.message}');
      debugPrint('   Email: ${_deviceCredentials[_currentDeviceId]?['email']}');
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
      final signed = isAuthenticated() ? true : await signInDevice();
      if (!signed) return false;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final firestore = FirebaseFirestore.instance;
      // Check users collection for uid-keyed doc
      final uidDoc = await firestore.collection('users').doc(user.uid).get();
      if (uidDoc.exists && uidDoc.data()?['role'] == 'pos') {
        return true;
      }

      // Fallback: check email-keyed doc (rules support either)
      final emailKey = user.email;
      if (emailKey != null && emailKey.isNotEmpty) {
        final emailDoc = await firestore.collection('users').doc(emailKey).get();
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
