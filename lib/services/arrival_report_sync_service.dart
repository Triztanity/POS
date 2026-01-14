import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'pos_device_auth_service.dart';

class ArrivalReportSyncService {
  static final ArrivalReportSyncService _instance = ArrivalReportSyncService._internal();
  factory ArrivalReportSyncService() => _instance;

  ArrivalReportSyncService._internal() {
    _connectivity = Connectivity();
    _init();
  }

  late final Connectivity _connectivity;
  StreamSubscription<ConnectivityResult>? _sub;
  bool _isSyncing = false;

  void _init() {
    _sub = _connectivity.onConnectivityChanged.listen((result) async {
      if (result != ConnectivityResult.none) {
        await _syncPendingReports();
      }
    });

    // Try initial sync
    _connectivity.checkConnectivity().then((res) {
      if (res != ConnectivityResult.none) _syncPendingReports();
    });
  }

  Future<void> _syncPendingReports() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      // Ensure POS device is signed in (device-level auth)
      final posAuth = POSDeviceAuthService();
      final deviceSignedIn = await posAuth.ensureSignedInWithPosRole();
      if (!deviceSignedIn) {
        print('⚠️ POS device not authenticated - arrival reports will sync when device is signed in');
        return;
      }

      final box = await Hive.openBox('arrival_reports_pending');
      final keys = box.keys.toList();
      if (keys.isEmpty) return;
      final col = FirebaseFirestore.instance.collection('arrivalReports');
      for (final k in keys) {
        try {
          final report = box.get(k);
          if (report == null) continue;
          await col.doc(k.toString()).set({
            ...Map<String, dynamic>.from(report as Map),
            'createdAt': FieldValue.serverTimestamp(),
            'syncedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          await box.delete(k);
          print('✅ Synced arrival report: $k');
        } catch (e) {
          print('❌ Failed to sync arrival report $k: $e');
          // continue with other reports
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
