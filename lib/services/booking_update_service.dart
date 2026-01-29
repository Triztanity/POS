import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// BookingUpdateService
/// Handles updating booking status in Firebase Firestore
class BookingUpdateService {
  static final BookingUpdateService _instance = 
      BookingUpdateService._internal();

  factory BookingUpdateService() {
    return _instance;
  }

  BookingUpdateService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Update booking with drop-off information
  Future<bool> markBookingAsDroppedOff(String bookingId) async {
    try {
      debugPrint('[Booking Update] Updating booking: $bookingId');
      
      final dropoffTimestamp = DateTime.now().toIso8601String();

      await _firestore.collection('bookings').doc(bookingId).update({
        'status': 'dropped-off',
        'dropoffTimestamp': dropoffTimestamp,
      });

      debugPrint('[Booking Update] ✅ Successfully updated booking: $bookingId');
      return true;
      
    } on FirebaseException catch (e) {
      debugPrint('[Booking Update] ❌ Firebase error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[Booking Update] ❌ Error updating booking: $e');
      return false;
    }
  }

  /// Batch update multiple bookings
  Future<bool> markBookingsAsDroppedOff(List<String> bookingIds) async {
    try {
      debugPrint('[Booking Update] Batch updating ${bookingIds.length} bookings');
      
      final batch = _firestore.batch();
      final dropoffTimestamp = DateTime.now().toIso8601String();

      for (final bookingId in bookingIds) {
        final docRef = _firestore.collection('bookings').doc(bookingId);
        batch.update(docRef, {
          'status': 'dropped-off',
          'dropoffTimestamp': dropoffTimestamp,
        });
      }

      await batch.commit();

      debugPrint('[Booking Update] ✅ Successfully batch updated ${bookingIds.length} bookings');
      return true;
      
    } on FirebaseException catch (e) {
      debugPrint('[Booking Update] ❌ Firebase error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[Booking Update] ❌ Error batch updating bookings: $e');
      return false;
    }
  }

  /// Get booking details
  Future<Map<String, dynamic>?> getBooking(String bookingId) async {
    try {
      final doc = await _firestore.collection('bookings').doc(bookingId).get();
      
      if (doc.exists) {
        return doc.data();
      }
      return null;
      
    } catch (e) {
      debugPrint('[Booking Update] Error getting booking: $e');
      return null;
    }
  }

  /// Check if booking already dropped off
  Future<bool> isAlreadyDroppedOff(String bookingId) async {
    try {
      final booking = await getBooking(bookingId);
      return booking?['status'] == 'dropped-off';
    } catch (e) {
      debugPrint('[Booking Update] Error checking drop-off status: $e');
      return false;
    }
  }
}
