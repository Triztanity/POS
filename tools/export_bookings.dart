#!/usr/bin/env dart
/// Quick script to export bookings from Firebase
/// 
/// Usage: dart tools/export_bookings.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:io';

// Firebase options - replace with your actual config
const firebaseOptions = {
  'apiKey': 'YOUR_API_KEY',
  'authDomain': 'YOUR_AUTH_DOMAIN',
  'projectId': 'YOUR_PROJECT_ID',
  'storageBucket': 'YOUR_STORAGE_BUCKET',
  'messagingSenderId': 'YOUR_MESSAGING_SENDER_ID',
  'appId': 'YOUR_APP_ID',
};

void main() async {
  try {
    print('🔄 Initializing Firebase...');
    
    // Note: This script needs to be run from the project root
    // It will use your existing Firebase configuration
    await Firebase.initializeApp();

    print('📚 Fetching bookings from Firestore...');
    
    final firestore = FirebaseFirestore.instance;
    final snapshot = await firestore.collection('bookings').get();

    print('   Found ${snapshot.docs.length} bookings');

    final List<Map<String, dynamic>> bookings = [];
    for (final doc in snapshot.docs) {
      bookings.add({
        'id': doc.id,
        ...doc.data(),
      });
    }

    // Pretty print JSON
    final jsonString = const JsonEncoder.withIndent('  ').convert(bookings);
    
    // Save to file in current directory
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final fileName = 'bookings_$timestamp.json';
    final file = File(fileName);
    
    await file.writeAsString(jsonString);

    print('✅ Export successful!');
    print('   📊 Exported ${bookings.length} bookings');
    print('   📁 File: $fileName');
    print('   📍 Path: ${file.absolute.path}');
    
    exit(0);
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}

