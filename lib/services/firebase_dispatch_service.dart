import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'pos_device_auth_service.dart';

class FirebaseDispatchService {
  static final FirebaseDispatchService _instance =
      FirebaseDispatchService._internal();
  final _firestore = FirebaseFirestore.instance;

  factory FirebaseDispatchService() {
    return _instance;
  }

  FirebaseDispatchService._internal();

  /// Write dispatch details to Firebase under the schedules collection.
  /// This updates a scheduled trip with the actual dispatch information.
  ///
  /// Uses lazy device authentication: device auth happens on-demand when syncing,
  /// not at app startup. This allows offline operation and graceful sync retry.
  Future<void> writeDispatchDetails({
    required String tripId,
    String? driverName,
    String? conductorName,
  }) async {
    try {
      // Ensure device is authenticated to Firestore (lazy auth on sync)
      final posAuth = POSDeviceAuthService();
      final authenticated = await posAuth.ensureSignedInWithPosRole();
      if (!authenticated) {
        print(
            '⚠️ POS device not authenticated to Firebase. Trip dispatch is pending.');
        throw Exception(
            'Device authentication failed. Will retry when network available.');
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception(
            'Device is not authenticated to Firebase. Check POS device credentials.');
      }

      final now = DateTime.now();
      final dispatchTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

      // Update the schedule document with dispatch details
      // This write succeeds because device is authenticated
      await _firestore.collection('schedules').doc(tripId).update({
        'driverName': driverName,
        'conductorName': conductorName,
        'dispatchTime': dispatchTime,
        'status': 'dispatched',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print(
          '✅ Dispatch details written for trip $tripId (device: ${currentUser.email})');
    } catch (e) {
      print('❌ Error writing dispatch details: $e');
      rethrow;
    }
  }

  /// Get a scheduled trip by ID
  Future<Map<String, dynamic>?> getSchedule(String tripId) async {
    try {
      final doc = await _firestore.collection('schedules').doc(tripId).get();
      return doc.data();
    } catch (e) {
      print('Error getting schedule: $e');
      return null;
    }
  }

  /// Create a `tripDetails` document when a POS uploads a trip dispatch.
  ///
  /// Fields written:
  /// - `tripId`: provided trip identifier
  /// - `vehicleNumber`: provided vehicle number
  /// - `dispatchTime`: server timestamp marking upload time
  /// - `uploadedBy`: email of the authenticated POS device (if available)
  ///
  /// Uses lazy device authentication: device auth happens on-demand when syncing,
  /// not at app startup. This allows offline operation and graceful sync retry.
  Future<void> writeTripDetails({
    required String tripId,
    required String vehicleNumber,
  }) async {
    try {
      // Ensure device is authenticated to Firestore (lazy auth on sync)
      final posAuth = POSDeviceAuthService();
      final authenticated = await posAuth.ensureSignedInWithPosRole();
      if (!authenticated) {
        print(
            '⚠️ POS device not authenticated to Firebase. Trip details upload is pending.');
        throw Exception(
            'Device authentication failed. Will retry when network available.');
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception(
            'Device is not authenticated to Firebase. Check POS device credentials.');
      }

      final docRef = _firestore.collection('tripDetails').doc(tripId);

      final data = {
        'tripId': tripId,
        'vehicleNumber': vehicleNumber,
        'dispatchTime': FieldValue.serverTimestamp(),
        'uploadedBy': currentUser.email,
      };

      await docRef.set(data, SetOptions(merge: true));

      print(
          '✅ Trip details uploaded for trip $tripId (vehicle: $vehicleNumber) by ${currentUser.email}');
    } catch (e) {
      print('❌ Error uploading trip details: $e');
      rethrow;
    }
  }

  /// Claims a pre-departure schedule for a bus and atomically sets route + status.
  /// Returns the claimed tripId on success.
  Future<String?> claimAndDispatchSchedule({
    required String busNumber,
    required Map<String, String> route,
    required String dispatcherUid,
  }) async {
    // Ensure device is authenticated to Firestore
    final posAuth = POSDeviceAuthService();
    final authenticated = await posAuth.ensureSignedInWithPosRole();
    if (!authenticated) {
      print(
          '⚠️ POS device not authenticated to Firebase. Cannot claim schedule.');
      throw Exception('Device authentication failed');
    }

    final db = FirebaseFirestore.instance;

    // Query for pre-departure schedule for this bus
    final query = await db
        .collection('schedules')
        .where('busNumber', isEqualTo: busNumber)
        .where('status', isEqualTo: 'pre-departure')
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    final docRef = doc.reference;

    try {
      await db.runTransaction((tx) async {
        final snapshot = await tx.get(docRef);
        final data = snapshot.data();
        if (data == null) throw Exception('Schedule document missing data');
        final currentStatus = (data['status'] ?? '').toString();
        if (currentStatus != 'pre-departure') {
          throw Exception('Schedule status changed (expected pre-departure)');
        }

        // Atomically set status, dispatchTime and route fields
        tx.update(docRef, {
          'status': 'departed',
          'dispatchTime': FieldValue.serverTimestamp(),
          'routeId': route['routeId'],
          'routeName': route['routeName'],
          'routeAssignedBy': dispatcherUid,
          'routeAssignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      final tripId = doc.data()['tripId']?.toString();
      return tripId ?? doc.id;
    } catch (e) {
      print('❌ Claim+Dispatch transaction failed: $e');
      rethrow;
    }
  }
}
