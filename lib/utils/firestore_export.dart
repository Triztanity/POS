import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:io';

/// Export Firestore collection to JSON file
class FirestoreExporter {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Export bookings collection to JSON file
  static Future<String> exportBookings() async {
    try {
      print('[Export] Starting bookings export...');
      
      // Get all documents from bookings collection
      final QuerySnapshot snapshot = await _firestore
          .collection('bookings')
          .get();

      // Convert documents to list of maps
      final List<Map<String, dynamic>> bookings = [];
      for (final doc in snapshot.docs) {
        bookings.add({
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        });
      }

      // Convert to JSON
      final jsonString = jsonEncode(bookings);
      
      // Create file path in app documents directory
      final directory = Directory.systemTemp;
      final fileName = 'bookings_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${directory.path}/$fileName');
      
      // Write to file
      await file.writeAsString(jsonString);
      
      print('[Export] ✅ Exported ${bookings.length} bookings to ${file.path}');
      return file.path;
      
    } catch (e) {
      print('[Export] ❌ Error exporting bookings: $e');
      rethrow;
    }
  }

  /// Export specific collection to JSON file
  static Future<String> exportCollection(String collectionName) async {
    try {
      print('[Export] Starting export for collection: $collectionName...');
      
      final QuerySnapshot snapshot = await _firestore
          .collection(collectionName)
          .get();

      final List<Map<String, dynamic>> items = [];
      for (final doc in snapshot.docs) {
        items.add({
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        });
      }

      final jsonString = jsonEncode(items);
      
      final directory = Directory.systemTemp;
      final fileName = '${collectionName}_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${directory.path}/$fileName');
      
      await file.writeAsString(jsonString);
      
      print('[Export] ✅ Exported ${items.length} items to ${file.path}');
      return file.path;
      
    } catch (e) {
      print('[Export] ❌ Error exporting collection: $e');
      rethrow;
    }
  }

  /// Export with pretty formatting
  static Future<String> exportBookingsPretty() async {
    try {
      print('[Export] Starting bookings export (pretty format)...');
      
      final QuerySnapshot snapshot = await _firestore
          .collection('bookings')
          .get();

      final List<Map<String, dynamic>> bookings = [];
      for (final doc in snapshot.docs) {
        bookings.add({
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        });
      }

      // Pretty JSON with indentation
      final jsonString = const JsonEncoder.withIndent('  ').convert(bookings);
      
      final directory = Directory.systemTemp;
      final fileName = 'bookings_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${directory.path}/$fileName');
      
      await file.writeAsString(jsonString);
      
      print('[Export] ✅ Exported ${bookings.length} bookings to ${file.path}');
      return file.path;
      
    } catch (e) {
      print('[Export] ❌ Error exporting bookings: $e');
      rethrow;
    }
  }
}
