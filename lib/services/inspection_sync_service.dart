import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/inspection.dart';
import '../local_storage.dart';
import 'sms_status_sender_service.dart';

/// Service to sync inspection data to remote dispatch dashboard
class InspectionSyncService {
  static final InspectionSyncService _instance =
      InspectionSyncService._internal();
  late final Connectivity _connectivity;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  bool _isOnline = false;
  bool _isSyncing = false;

  // TODO: Configure your backend API endpoint
  static const Duration _syncRetryDelay = Duration(seconds: 30);
  static const int _maxRetries = 3;

  factory InspectionSyncService() {
    return _instance;
  }

  InspectionSyncService._internal() {
    _connectivity = Connectivity();
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;

      // When transitioning from offline to online, attempt sync
      if (!wasOnline && _isOnline) {
        debugPrint('[INSPECTION_SYNC] Device came online, attempting to sync');
        _syncPendingInspections();
      }
    });

    // Initial check
    _connectivity.checkConnectivity().then((result) {
      _isOnline = result != ConnectivityResult.none;
    });
  }

  /// Sync all pending (unsynced) inspections to the server
  Future<void> _syncPendingInspections() async {
    if (_isSyncing) {
      debugPrint('[INSPECTION_SYNC] Sync already in progress, skipping');
      return;
    }

    if (!_isOnline) {
      debugPrint('[INSPECTION_SYNC] Device offline, deferring sync');
      return;
    }

    _isSyncing = true;

    try {
      final pendingInspections = _getPendingInspections();
      if (pendingInspections.isEmpty) {
        debugPrint('[INSPECTION_SYNC] No pending inspections to sync');
        _isSyncing = false;
        return;
      }

      debugPrint(
          '[INSPECTION_SYNC] Syncing ${pendingInspections.length} pending inspections');

      for (final inspection in pendingInspections) {
        await _syncInspection(inspection);
      }

      debugPrint('[INSPECTION_SYNC] Sync completed');
    } catch (e) {
      debugPrint('[INSPECTION_SYNC] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Get all unsynced inspections from local storage
  List<Inspection> _getPendingInspections() {
    try {
      final allInspections = LocalStorage.loadInspections();
      return allInspections
          .map((m) => Inspection.fromMap(m))
          .where((i) => !i.isSynced)
          .toList();
    } catch (e) {
      debugPrint('[INSPECTION_SYNC] Error loading pending inspections: $e');
      return [];
    }
  }

  /// Sync a single inspection: try Firestore first, fall back to SMS gateway.
  Future<void> _syncInspection(Inspection inspection,
      {int retryCount = 0}) async {
    // --- Primary: Firestore ---
    if (_isOnline) {
      try {
        final map = inspection.toRemoteMap();
        await FirebaseFirestore.instance
            .collection('inspections')
            .doc(inspection.id)
            .set(map);
        await _markInspectionSynced(inspection.id);
        debugPrint(
            '[INSPECTION_SYNC] Synced inspection ${inspection.id} to Firestore');
        return;
      } catch (e) {
        debugPrint('[INSPECTION_SYNC] Firestore upload failed for ${inspection.id}: $e');
        // Fall through to SMS fallback
      }
    }

    // --- Fallback: SMS gateway (INS|{json}) ---
    try {
      debugPrint('[INSPECTION_SYNC] Attempting SMS fallback for ${inspection.id}');
      final result = await SmsStatusSenderService().sendInspectionSms(inspection);
      if (result['success'] == true) {
        // Mark synced via SMS so we don't retry endlessly.
        await _markInspectionSynced(inspection.id);
        debugPrint('[INSPECTION_SYNC] Sent inspection ${inspection.id} via SMS gateway');
        return;
      }
    } catch (e) {
      debugPrint('[INSPECTION_SYNC] SMS fallback failed for ${inspection.id}: $e');
    }

    // --- Both paths failed: record error and schedule retry ---
    const errorMsg = 'Both Firestore and SMS fallback failed';
    await _handleSyncError(inspection.id, errorMsg);

    if (retryCount < _maxRetries) {
      await Future.delayed(
          Duration(seconds: _syncRetryDelay.inSeconds * (retryCount + 1)));
      await _syncInspection(inspection, retryCount: retryCount + 1);
    }
  }

  /// Mark inspection as synced in local storage
  Future<void> _markInspectionSynced(String inspectionId) async {
    try {
      final allInspections = LocalStorage.loadInspections();
      final index = allInspections.indexWhere((m) => m['id'] == inspectionId);
      if (index >= 0) {
        allInspections[index]['isSynced'] = true;
        allInspections[index]['syncError'] = null;
        // Re-save the updated inspection
        await LocalStorage.updateInspection(
            inspectionId, allInspections[index]);
      }
    } catch (e) {
      debugPrint('[INSPECTION_SYNC] Error marking as synced: $e');
    }
  }

  /// Record sync error in local storage
  Future<void> _handleSyncError(String inspectionId, String errorMsg) async {
    try {
      final allInspections = LocalStorage.loadInspections();
      final index = allInspections.indexWhere((m) => m['id'] == inspectionId);
      if (index >= 0) {
        allInspections[index]['syncError'] = errorMsg;
        await LocalStorage.updateInspection(
            inspectionId, allInspections[index]);
      }
    } catch (e) {
      debugPrint('[INSPECTION_SYNC] Error recording sync error: $e');
    }
  }

  /// Get authorization token (implement based on your auth system)
  String _getAuthToken() {
    // TODO: Retrieve from app state or secure storage
    return 'dummy_token';
  }

  /// Manually trigger sync (can be called by UI, e.g., "Sync Now" button)
  Future<void> syncNow() async {
    await _syncPendingInspections();
  }

  /// Get sync status for display (e.g., pending count, last error)
  Future<Map<String, dynamic>> getSyncStatus() async {
    final allInspections = LocalStorage.loadInspections();
    final pendingCount =
        allInspections.where((m) => !(m['isSynced'] ?? false)).length;
    final syncedCount =
        allInspections.where((m) => (m['isSynced'] ?? false)).length;
    final withErrors =
        allInspections.where((m) => (m['syncError'] ?? '').isNotEmpty).length;

    return {
      'isOnline': _isOnline,
      'isSyncing': _isSyncing,
      'totalInspections': allInspections.length,
      'syncedCount': syncedCount,
      'pendingCount': pendingCount,
      'errorCount': withErrors,
    };
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription.cancel();
  }
}
