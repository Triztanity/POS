import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import '../local_storage.dart';

/// SyncService: lightweight connectivity watcher and sync skeleton.
/// This will attempt to upload unsynced employee records to Firebase when
/// connectivity is available. Firebase code is intentionally optional —
/// placeholder hooks are provided so teams can wire real sync logic.
class SyncService {
  final _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _sub;

  void start() {
    _sub = _connectivity.onConnectivityChanged.listen((result) async {
      if (result != ConnectivityResult.none) {
        await _syncNow();
      }
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _syncNow() async {
    // Get unsynced records
    final all = LocalStorage.getAllEmployees();
    final unsynced = all.where((r) => r['synced'] != true).toList();
    if (unsynced.isEmpty) return;

    // Placeholder: integrate Firestore or REST API here
    // For each record: upload -> on success mark record['synced']=true and upsert
    for (final rec in unsynced) {
      try {
        // TODO: upload to remote backend, e.g.:
        // await FirebaseFirestore.instance.collection('users').doc(rec['firebaseId'] ?? rec['uid']).set({...});

        // On success:
        rec['synced'] = true;
        await LocalStorage.upsertEmployee(rec);
      } catch (e) {
        // Leave record unsynced; retry next time
      }
    }
  }
}
