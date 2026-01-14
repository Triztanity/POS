# Inspection Data Sync Implementation Summary

## What Was Implemented

Your POS device now has **automatic offline-to-online inspection data sync** for the dispatch dashboard.

### Files Created

1. **[InspectionSyncService](lib/services/inspection_sync_service.dart)**
   - Monitors device connectivity (uses `connectivity_plus`)
   - Auto-syncs inspection data when online
   - Implements retry logic (up to 3 attempts with exponential backoff)
   - Tracks sync status per inspection (synced/pending/error)

2. **[InspectionSyncStatusWidget](lib/widgets/inspection_sync_status_widget.dart)**
   - Shows connection status (Online/Offline)
   - Displays inspection sync statistics (Total, Synced, Pending, Errors)
   - "Sync Now" button for manual syncing
   - Shows progress during active sync

### Files Modified

1. **[Inspection Model](lib/models/inspection.dart)**
   - Added `isSynced` (bool) — tracks if successfully synced to server
   - Added `syncError` (String?) — stores error message if sync failed

2. **[LocalStorage](lib/local_storage.dart)**
   - Added `updateInspection(id, Map)` — updates sync status locally

3. **[main.dart](lib/main.dart)**
   - Initializes InspectionSyncService on app startup
   - Disposes sync service on app shutdown

4. **[pubspec.yaml](pubspec.yaml)**
   - Added `http: ^1.1.0` for API requests

## How It Works

### Offline Scenario
```
1. Inspector completes audit (no internet needed)
2. Inspection saved to local Hive DB with isSynced=false
3. Device continues working offline
```

### Online Transition
```
1. Device detects internet connectivity
2. InspectionSyncService automatically triggers
3. Fetches all pending (unsynced) inspections
4. POSTs each to your dispatch API endpoint
5. On success: isSynced=true
6. On failure: Records error, retries with backoff
```

### Manual Sync
```
User can anytime tap "Sync Now" button to force sync when online
```

## Integration Steps

### 1. Configure Your API Endpoint

Edit [InspectionSyncService](lib/services/inspection_sync_service.dart) line 20-21:

```dart
static const String _apiBaseUrl = 'https://your-dispatch-api.com/api';
static const String _syncEndpoint = '$_apiBaseUrl/inspections/sync';
```

### 2. Implement Authentication

Update `_getAuthToken()` method (line 216) to return actual token:

```dart
String _getAuthToken() {
  // Example: retrieve from AppState
  return AppState.instance.authToken ?? 'fallback_token';
}
```

### 3. Display Sync Status (Optional UI)

Add to any screen:

```dart
import 'package:untitled/widgets/inspection_sync_status_widget.dart';

@override
Widget build(BuildContext context) {
  return InspectionSyncStatusWidget();
}
```

### 4. API Endpoint (Dashboard Side)

Your dispatch dashboard API should handle:

```
POST /inspections/sync
Authorization: Bearer {token}
Content-Type: application/json

{
  "id": "...",
  "timestamp": "...",
  // ...all inspection fields...
  "isSynced": true,
  "syncError": null
}
```

Response: `200 OK` or `201 Created` on success

## Key Features

✅ **Offline-First**: App works entirely offline, sync is transparent  
✅ **Auto-Retry**: Failed syncs retry up to 3 times with backoff  
✅ **Connectivity Detection**: Uses native connectivity_plus plugin  
✅ **Error Tracking**: Stores sync errors locally for debugging  
✅ **Manual Override**: "Sync Now" button for user control  
✅ **Non-Breaking**: Rest of app remains fully offline-capable  
✅ **Audit Trail**: Synced data preserved locally (never deleted)  

## Data Flow Example

```
[POS Device - Offline]
Inspector completes audit on Bus-002
↓
Inspection{
  id: "insp-123",
  isCleared: true,
  isSynced: false,
  syncError: null
}
↓ Saved to Hive
[3 hours later - Dispatcher connects device to WiFi]
↓
ConnectivityListener fires: ONLINE detected
↓
InspectionSyncService._syncPendingInspections()
↓
POST https://dispatch-api.com/api/inspections/sync
  Header: Authorization: Bearer token
  Body: Inspection{...}
↓
Dashboard API returns: 200 OK
↓
Inspection updated:
  isSynced: true,
  syncError: null
↓
Dashboard displays: "Received 15 inspections from POS-Device-001"
```

## Monitoring / Debugging

Check logs during sync:

```
[INSPECTION_SYNC] Device came online, attempting to sync
[INSPECTION_SYNC] Syncing 3 pending inspections
[INSPECTION_SYNC] Synced inspection insp-123 successfully
[INSPECTION_SYNC] Error syncing insp-456: Connection timeout
[INSPECTION_SYNC] Retrying insp-456 (attempt 1/3)...
```

Retrieve programmatically:

```dart
final status = await InspectionSyncService().getSyncStatus();
print('Pending: ${status["pendingCount"]}');
print('Errors: ${status["errorCount"]}');
print('Online: ${status["isOnline"]}');
```

## Testing Checklist

- [ ] Configure API endpoint in InspectionSyncService
- [ ] Configure auth token retrieval in _getAuthToken()
- [ ] Test offline: create inspection, verify isSynced=false
- [ ] Test online: go online, verify auto-sync triggers
- [ ] Test dashboard receives POST requests
- [ ] Test manual "Sync Now" button
- [ ] Test retry on network failure
- [ ] Test error message stored in syncError field
- [ ] Test UI shows correct sync status

## Architecture Diagram

```
┌─ POS Device ──────────────────────────────────┐
│                                               │
│  InspectorScreen                             │
│    └─→ saves Inspection                      │
│         └─→ LocalStorage.saveInspection()    │
│              └─→ Hive DB (isSynced=false)    │
│                                              │
│  InspectionSyncService (singleton)           │
│    ├─ Monitors Connectivity                  │
│    ├─ Auto-syncs when online                 │
│    ├─ Retries on failure                     │
│    └─→ Updates Inspection.isSynced           │
│                                              │
│  InspectionSyncStatusWidget                  │
│    └─→ Shows status & manual "Sync Now"     │
│                                              │
└───────────────────┬──────────────────────────┘
                    │ HTTP POST
                    ↓
        ┌─ Dispatch Dashboard ───┐
        │                        │
        │ /inspections/sync      │
        │   ├─ Validate auth     │
        │   ├─ Store inspection  │
        │   ├─ Update UI         │
        │   └─ Return 200 OK     │
        │                        │
        └────────────────────────┘
```

## Next Steps

1. **Configure endpoint** in InspectionSyncService
2. **Test sync flow** offline → online
3. **Build dashboard** to receive POST requests
4. **Add UI** (InspectionSyncStatusWidget to profile/settings screen)
5. **Monitor** sync logs during operations

---

See [INSPECTION_SYNC_SETUP.md](INSPECTION_SYNC_SETUP.md) for detailed API specs and troubleshooting.
