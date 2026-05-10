import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../local_storage.dart';
import '../utils/fare_calculator.dart';
import 'pos_device_auth_service.dart';

class FareTableCacheService {
  static final FareTableCacheService _instance =
      FareTableCacheService._internal();

  factory FareTableCacheService() => _instance;

  FareTableCacheService._internal();

  static const Duration cacheTtl = Duration(hours: 12);

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isRefreshing = false;
  bool _started = false;

  Future<void> loadCachedEntries() async {
    final cachedMaps = LocalStorage.loadFareTableEntries();
    if (cachedMaps.isEmpty) {
      debugPrint(
          '[FareTableCache] No cached fare table, using bundled defaults');
      return;
    }

    final cachedEntries = cachedMaps.map(FareEntry.fromMap).toList();
    final cachedValidationError = FareTable.getValidationError(cachedEntries);
    if (cachedValidationError != null) {
      debugPrint(
          '[FareTableCache] Cached fare table invalid, using bundled defaults: $cachedValidationError');
      return;
    }

    FareTable.loadEntries(cachedEntries);
    debugPrint(
        '[FareTableCache] Loaded ${cachedEntries.length} cached entries');
  }

  void start() {
    if (_started) return;
    _started = true;

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        refreshIfStale();
      }
    });

    refreshIfStale(force: true);
  }

  Future<void> refreshIfStale({bool force = false}) async {
    if (_isRefreshing) return;
    if (!force && !isCacheStale()) return;

    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      debugPrint('[FareTableCache] Offline, refresh deferred');
      return;
    }

    await refreshNow();
  }

  bool isCacheStale() {
    final metadata = LocalStorage.getFareTableCacheMetadata();
    final syncedAtRaw = metadata?['lastSyncedAt']?.toString();
    if (syncedAtRaw == null || syncedAtRaw.isEmpty) return true;

    final syncedAt = DateTime.tryParse(syncedAtRaw);
    if (syncedAt == null) return true;

    return DateTime.now().difference(syncedAt) >= cacheTtl;
  }

  Future<void> refreshNow() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final signedIn = await POSDeviceAuthService().ensureSignedInWithPosRole();
      if (!signedIn) {
        debugPrint(
            '[FareTableCache] POS auth unavailable, keeping current fare table');
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('fare_table_entries')
          .orderBy('km')
          .get();

      final activeDocs = snapshot.docs.where((doc) {
        final isActive = doc.data()['isActive'];
        return isActive != false;
      }).toList(growable: false);

      final entries = activeDocs
          .map((doc) => FareEntry.fromMap(doc.data()))
          .toList(growable: false);

      final validationError = FareTable.getValidationError(entries);
      if (validationError != null) {
        debugPrint(
            '[FareTableCache] Remote fare table invalid/incomplete, keeping current fare table: $validationError');
        return;
      }

      FareTable.loadEntries(entries);
      await LocalStorage.saveFareTableEntries(
        entries.map((entry) => entry.toMap()).toList(growable: false),
        syncedAt: DateTime.now(),
      );
      final stationCount =
          entries.where((entry) => entry.place.isNotEmpty).length;
      debugPrint(
          '[FareTableCache] Refreshed ${entries.length} remote entries ($stationCount stations, ${snapshot.docs.length - activeDocs.length} inactive skipped)');
    } catch (e) {
      debugPrint(
          '[FareTableCache] Refresh failed, keeping current fare table: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _started = false;
  }
}
