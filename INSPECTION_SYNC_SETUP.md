# Inspection Data Sync Guide

This guide explains how inspection audit data is synced from the POS device to the dispatch dashboard.

## Overview

- **Device Mode**: Primarily offline-first
- **Inspection Data**: Saved locally in Hive database
- **Sync Trigger**: Automatic when device comes online (connectivity detected)
- **Manual Sync**: User can tap "Sync Now" button anytime when online
- **Fallback**: Retries failed syncs up to 3 times with exponential backoff

## Data Flow

```
Inspector creates audit
    ↓
Inspection saved to local Hive DB (isSynced=false)
    ↓
Device connectivity changes → ONLINE
    ↓
InspectionSyncService detects online status
    ↓
Attempts to POST inspection data to dispatch API
    ↓
On Success: Mark isSynced=true, update local record
On Failure: Record syncError, retry later
```

## Configuration

To enable sync, configure your dispatch API endpoint in [InspectionSyncService](lib/services/inspection_sync_service.dart):

```dart
static const String _apiBaseUrl = 'https://your-dispatch-api.com/api';
static const String _syncEndpoint = '$_apiBaseUrl/inspections/sync';
```

### API Endpoint Specification

**POST** `/inspections/sync`

**Headers**:
```
Content-Type: application/json
Authorization: Bearer {auth_token}
```

**Request Body**:
```json
{
  "id": "uuid",
  "timestamp": "2025-12-18T10:30:00.000Z",
  "busNumber": "BUS-002",
  "tripSession": "north_to_south",
  "inspectorUid": "uid123",
  "conductorUid": "uid456",
  "driverUid": "uid789",
  "manualPassengerCount": 42,
  "systemPassengerCount": 42,
  "isCleared": true,
  "discrepancyResolved": null,
  "resolutionReason": null,
  "customExplanation": null,
  "comments": "All clear",
  "isSynced": true,
  "syncError": null
}
```

**Response**: `200 OK` or `201 Created`

## Usage

### Display Sync Status (in UI)

```dart
import 'package:untitled/widgets/inspection_sync_status_widget.dart';

// In your screen:
InspectionSyncStatusWidget()
```

This displays:
- Connection status (Online/Offline)
- Inspection counts (Total, Synced, Pending, Errors)
- Manual "Sync Now" button
- Auto-sync progress indicator

### Programmatic Access

```dart
final syncService = InspectionSyncService();

// Get current status
final status = await syncService.getSyncStatus();
print('Pending: ${status["pendingCount"]}');
print('Online: ${status["isOnline"]}');

// Manually trigger sync
await syncService.syncNow();
```

## Data Persistence

Inspections are stored in the **Hive `inspections` box** with the following structure:

```dart
{
  "id": "...",
  "timestamp": "...",
  // ... inspection fields ...
  "isSynced": false,      // false until successfully synced
  "syncError": null       // error message if sync failed
}
```

**Local Storage Methods** (in [LocalStorage](lib/local_storage.dart)):

- `saveInspection(Map)` — Save a new inspection
- `loadInspections()` — Load all inspections (synced + pending)
- `updateInspection(id, Map)` — Update inspection (used for tracking sync status)

## Sync Lifecycle

1. **Inspector completes audit** → Inspection saved with `isSynced=false`
2. **Device goes online** → ConnectivityListener triggers sync
3. **Sync Service posts each pending inspection** → Retry up to 3 times on failure
4. **On success** → `isSynced=true`, `syncError=null`
5. **On failure (after retries)** → `syncError="<reason>"` recorded locally
6. **Manual retry** → User can tap "Sync Now" to retry failed inspections

## Retry Logic

- **Initial Attempt**: Immediate
- **Retry 1**: After 30 seconds
- **Retry 2**: After 60 seconds
- **Retry 3**: After 90 seconds
- **Max Retries**: 3 attempts per inspection
- **Timeout**: 15 seconds per request

## Error Handling

- Network errors → Retry automatically
- Server 5xx errors → Retry automatically
- Server 4xx errors → Log error, skip retry (malformed data)
- Timeout → Retry automatically

Error messages are stored in `syncError` field for debugging:
```dart
"Connection failed: Failed host lookup"
"Server returned 500: Internal Server Error"
"Sync request timeout for inspection-uuid"
```

## Testing

### Offline Scenario
1. Disable device network
2. Create inspection → Saved with `isSynced=false`
3. Check sync status → "Pending"
4. Re-enable network → Auto-sync attempts

### Manual Sync
1. Tap "Sync Now" button
2. Check InspectionSyncService logs
3. Verify dashboard received inspections

### Error Scenarios
- Network timeout during sync
- API endpoint returns error
- Invalid authentication token
- Check `syncError` in local inspection record

## Integration with Dashboard

The dispatch dashboard should:

1. **Receive** POST requests at the configured endpoint
2. **Validate** incoming inspection data
3. **Store** inspections with metadata (received timestamp, source device)
4. **Track** sync completion status per device
5. **Alert** management to discrepancies flagged in audit data

## Authentication

Update `_getAuthToken()` in [InspectionSyncService](lib/services/inspection_sync_service.dart) to retrieve actual auth token:

```dart
String _getAuthToken() {
  // TODO: Retrieve from AppState or secure storage
  final token = AppState.instance.authToken;
  return token ?? 'dummy_token';
}
```

## Monitoring

Enable debug logging by checking logs during sync:

```
[INSPECTION_SYNC] Device came online, attempting to sync
[INSPECTION_SYNC] Syncing 3 pending inspections
[INSPECTION_SYNC] Synced inspection abc-123 successfully
[INSPECTION_SYNC] Sync completed
```

---

**Key Points:**
- Inspections are **never deleted** locally after sync (for audit trail)
- Device **remains fully offline** except during sync window
- Sync is **automatic** and **transparent** to dispatcher
- Failed syncs are **persisted** and **retried** when online
