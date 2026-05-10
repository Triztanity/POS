import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../local_storage.dart';
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

  /// Mark an in-progress trip as cancelled from POS (emergency alert path).
  /// Writes only `cancelledAt` (server timestamp) on matched schedule doc.
  /// Returns true if a schedule was updated; false if no active/eligible schedule.
  Future<bool> sendCancelTripSignal({String? tripId}) async {
    try {
      final posAuth = POSDeviceAuthService();
      final authenticated = await posAuth.ensureSignedInWithPosRole();
      if (!authenticated) {
        print(
            '⚠️ POS device not authenticated to Firebase. Cannot send cancel signal.');
        return false;
      }

      tripId ??= LocalStorage.getCurrentTripId();
      if (tripId.isEmpty) {
        print('⚠️ No current tripId set in local storage.');
        return false;
      }

      final query = await _firestore
          .collection('schedules')
          .where('tripId', isEqualTo: tripId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        print('⚠️ No schedule found for tripId $tripId');
        return false;
      }

      final doc = query.docs.first;
      final data = doc.data();
      final status = (data['status'] ?? '').toString().toLowerCase();

      // Only send cancel signal for already started trips.
      if (status != 'departed' && status != 'in-progress') {
        print(
            '⚠️ Schedule is not in-progress/departed (status=$status); skip cancel signal.');
        return false;
      }

      await doc.reference.update({
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      print('✅ Cancel trip signal set for schedule tripId=$tripId');
      return true;
    } catch (e) {
      print('❌ Failed to send cancel trip signal: $e');
      return false;
    }
  }

  /// Mark the current schedule as arrived after the POS prints the arrival report.
  Future<bool> markScheduleArrived({String? tripId}) async {
    try {
      final posAuth = POSDeviceAuthService();
      final authenticated = await posAuth.ensureSignedInWithPosRole();
      if (!authenticated) {
        print(
            '⚠️ POS device not authenticated to Firebase. Cannot mark schedule arrived.');
        return false;
      }

      final resolvedTripId = (tripId ?? LocalStorage.getCurrentTripId()).trim();
      if (resolvedTripId.isEmpty) {
        print('⚠️ No current tripId set in local storage.');
        return false;
      }

      var docRef = _firestore.collection('schedules').doc(resolvedTripId);
      var snapshot = await docRef.get();

      if (!snapshot.exists) {
        final query = await _firestore
            .collection('schedules')
            .where('tripId', isEqualTo: resolvedTripId)
            .limit(1)
            .get();
        if (query.docs.isEmpty) {
          print('⚠️ No schedule found for tripId $resolvedTripId');
          return false;
        }
        snapshot = query.docs.first;
        docRef = snapshot.reference;
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status == 'arrived') {
        print('✅ Schedule already arrived for tripId=$resolvedTripId');
        return true;
      }
      if (status == 'cancelled' || status == 'canceled') {
        print(
            '⚠️ Schedule is cancelled (status=$status); skip arrived update.');
        return false;
      }

      if (status != 'departed' &&
          status != 'dispatched' &&
          status != 'in-progress') {
        print(
            '⚠️ Schedule is not active/departed (status=$status); skip arrived update.');
        return false;
      }

      await docRef.update({
        'status': 'arrived',
        'arrivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Schedule marked arrived for tripId=$resolvedTripId');
      return true;
    } catch (e) {
      print('❌ Failed to mark schedule arrived: $e');
      return false;
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
    required String driverUid,
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
          'routeAssignedBy': driverUid,
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
