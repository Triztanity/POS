# QR Validation System Refactor

**Status**: ✅ Complete  
**Date**: January 5, 2025  
**Last Updated**: January 5, 2025

---

## Overview

This document describes the complete refactored QR scanning and validation system. The refactor consolidates all route validation logic into a centralized service, eliminates redundant checks, and provides clean, reusable helpers for station lookup and route validation.

---

## Architecture

### Core Components

#### 1. **RouteValidationService** (`lib/services/route_validation_service.dart`)
The single source of truth for all station and route validation logic.

**Key Attributes:**
- **`stationSequence`**: Constant list of 54 stations in route order (Nasugbu Terminal → Batangas Terminal)
- **Route Order**: Index increases from Nasugbu (0) to Batangas (53)

**Key Methods:**

| Method | Purpose | Input | Output |
|--------|---------|-------|--------|
| `getStationIndex(stationName)` | Fuzzy match a station name to its index | `String?` | `int` (-1 if not found) |
| `validateRouteDirection(originIdx, destIdx, routeDir)` | Check if origin→destination follows route rules | `int, int, String` | `ValidationResult` |
| `isValidDestination(dest, availableDestinations)` | Verify destination is in dropdown list | `String?, List<String>` | `bool` |

**Route Rules:**
- **North Route** (Nasugbu → Batangas): `originIndex < destinationIndex`
- **South Route** (Batangas → Nasugbu): `originIndex > destinationIndex`

**ValidationResult Class:**
```dart
class ValidationResult {
  final bool success;        // true = valid, false = invalid
  final String? message;     // Error message (null if successful)
}
```

---

#### 2. **OfflineQrService** (`lib/services/offline_qr_service.dart`)
Handles QR parsing, field normalization, comprehensive validation, duplicate detection, and local storage.

**Key Method:**
```dart
static Future<OfflineQrResult> validateAndProcess({
  required String rawQr,                    // Raw QR payload (JSON or base64)
  String? currentBusNumber,                 // Device's assigned bus (e.g., 'BUS-002')
  String? currentRoute,                     // Route direction ('North' or 'South')
  List<String>? availableDestinations,      // Valid destinations from dropdown
}) async
```

**Validation Pipeline:**

1. **Parse QR Payload**
   - Attempts raw JSON decode first
   - Falls back to base64-decode then JSON decode
   - Returns error if both fail

2. **Normalize Keys**
   - Strips whitespace and underscores
   - Converts to lowercase
   - Builds alias map for common field name variations

3. **Map to Canonical Fields**
   - `transactionId`: txn, txnid
   - `origin`: from, fromplace, originplace
   - `destination`: to, toplace, destinationplace
   - `fare`: amount, price, fareamount
   - `paymentMethod`: method, payment, paymenttype, paymethod, pmethod, pay_method
   - `busNumber`: vehicleno, vehiclenumber
   - `busRoute`: route
   - `paymentStatus`: status
   - `createdAt`: createdatiso, created, timestamp, time, ts, date

4. **Validate Required Fields**
   - `transactionId`, `origin`, `destination`, `fare` must be present

5. **Validate Bus Number**
   - Normalizes both device and QR bus numbers
   - Checks for exact match or substring match
   - Default device bus: 'BUS-002'
   - Error: "Passenger boarded the wrong bus"

6. **Validate Origin**
   - Uses `RouteValidationService.getStationIndex(origin)`
   - Must match a station in the canonical sequence
   - Error: "System could not determine the origin or destination"

7. **Validate Destination**
   - Checks against `availableDestinations` list (from FareTable.placeNames)
   - Must exist in dropdown
   - Error: "System could not determine the origin or destination"

8. **Validate Destination Index**
   - Confirms destination maps to a station index
   - Error: "System could not determine the origin or destination"

9. **Validate Route Direction** (if provided)
   - Uses `RouteValidationService.validateRouteDirection(originIdx, destIdx, currentRoute)`
   - Enforces North/South rules
   - Error: "Passenger is out of route and going to the wrong direction"

10. **Validate Payment Method**
    - Must be 'GCash' (case-insensitive)
    - Default if missing: 'GCash'
    - Error: "Payment method not GCash"

11. **Duplicate Check**
    - Queries `ScanStorage.hasScanned(transactionId)`
    - Prevents rescanning same ticket
    - Error: "Ticket already used"

12. **Save to Local Storage**
    - Stores record in Hive box 'scans'
    - Adds `scannedAt` timestamp
    - Preserves original payload as `rawPayload`
    - Returns record with ID for downstream use

**Result Object:**
```dart
class OfflineQrResult {
  final bool success;              // true = all checks passed
  final String message;            // Status or error message
  final Map<String, dynamic>? data; // Validated data or error details
}
```

---

#### 3. **FareTable** (`lib/utils/fare_calculator.dart`)
Provides the canonical list of valid destination places used in home_screen dropdown.

**Key Property:**
```dart
static List<String> get placeNames => [
  'NASUGBU', 'LIAN', 'SAGBAT', 'CENTRAL', 'IRRIGATION',
  'BILARAN', 'PALICO', 'PAHINANTE', 'LUNTAL', 'TALON',
  'TUY', 'OBISPO', 'PUTOL', 'GUINHAWA', 'MUNTING TUBIG',
  // ... (54 places total)
  'BATANGAS TERMINAL'
]
```

**Integration:**
- OfflineQrService calls `FareTable.placeNames` as default available destinations
- Ensures QR destination matches a fare table entry
- Aligns with home_screen dropdown (where user selects destination)

---

## Validation Flow Diagram

```
Raw QR Payload
    ↓
[Parse QR] → Invalid? → Error: "Invalid QR payload"
    ↓
[Normalize Keys & Map to Canonical Fields]
    ↓
[Check Required Fields] → Missing? → Error: "Missing field: {fieldName}"
    ↓
[Default Payment Method to 'GCash']
    ↓
[Validate Payment Method] → Not GCash? → Error: "Payment method not GCash"
    ↓
[Validate Bus Number] → Mismatch? → Error: "Passenger boarded the wrong bus"
    ↓
[Get Origin Index] → RouteValidationService.getStationIndex(origin)
    ↓
[Origin not found?] → Error: "System could not determine the origin or destination"
    ↓
[Get Destination Index] → RouteValidationService.getStationIndex(destination)
    ↓
[Destination not in available list?] → Error: "System could not determine the origin or destination"
    ↓
[Destination index not found?] → Error: "System could not determine the origin or destination"
    ↓
[If Route Provided: Validate Direction] → RouteValidationService.validateRouteDirection(...)
    ↓
[Direction invalid?] → Error: "Passenger is out of route and going to the wrong direction"
    ↓
[Check for Duplicate] → ScanStorage.hasScanned(transactionId)
    ↓
[Already scanned?] → Error: "Ticket already used"
    ↓
[Save to ScanStorage & Return]
    ↓
Success: "OK" with validated data
```

---

## Usage Examples

### Basic Offline Validation (Scanner Integration)

```dart
import 'services/offline_qr_service.dart';
import 'utils/fare_calculator.dart';

// In QR scanner after capturing QR code
final result = await OfflineQrService.validateAndProcess(
  rawQr: capturedQrString,
  currentBusNumber: 'BUS-002',
  currentRoute: 'North',  // or 'South'
  availableDestinations: FareTable.placeNames, // Explicit list
);

if (result.success) {
  // Proceed with booking confirmation
  final qrData = result.data;
  print('✓ Valid: ${qrData['origin']} → ${qrData['destination']}');
} else {
  // Show error to operator
  print('✗ ${result.message}');
}
```

### Station Lookup (Helper)

```dart
import 'services/route_validation_service.dart';

// Find a station's position in the route
final index = RouteValidationService.getStationIndex('Lian');
if (index >= 0) {
  print('Station at index $index');
} else {
  print('Station not found');
}
```

### Route Direction Validation (Helper)

```dart
import 'services/route_validation_service.dart';

// Validate passenger's origin→destination against route
final result = RouteValidationService.validateRouteDirection(
  2,        // Origin index (Lian)
  35,       // Destination index (Puting Bato)
  'North',  // Route direction
);

if (result.success) {
  print('✓ Valid route');
} else {
  print('✗ ${result.message}');
}
```

### Destination Dropdown Validation (Helper)

```dart
import 'services/route_validation_service.dart';
import 'utils/fare_calculator.dart';

// Check if user selected destination is valid
final isValid = RouteValidationService.isValidDestination(
  'PALICO',
  FareTable.placeNames,
);
```

---

## Key Design Decisions

### 1. **Centralized Station List**
- Single source of truth in `RouteValidationService.stationSequence`
- Index-based route validation (avoids string searching)
- Ordered Nasugbu (0) to Batangas (53)

### 2. **Fuzzy Station Matching**
- Handles common abbreviations ("Nasugbu" → "Nasugbu Terminal")
- Handles partial names ("Lian" → "Lian Shed")
- Case-insensitive and whitespace-tolerant

### 3. **Destination from FareTable**
- Aligns QR validation with actual fare dropdown
- Prevents "passenger not in system" errors
- Single source for available destinations

### 4. **Separate Validation Layers**
- **Bus Number**: Device configuration (strict match)
- **Origin/Destination**: Station list (fuzzy match)
- **Route Direction**: Index-based comparison (North/South rules)
- **Payment**: Fixed to 'GCash'
- **Duplicate**: Hive storage by transaction ID

### 5. **Clean Error Messages**
- User-facing: "System could not determine...", "Passenger is out of route...", "Passenger boarded the wrong bus"
- Debug info: Available in `result.data` for troubleshooting

---

## Integration Points

### QR Scanner (`qr_scanner_screen.dart`)
Currently uses `QRValidationService` which wraps the old `RouteValidator`.  
**Next Step**: Update to call `OfflineQrService.validateAndProcess()` directly for consistent validation.

### Home Screen (`home_screen.dart`)
Provides dropdown destinations from `FareTable.placeNames`.  
**Used By**: OfflineQrService validates QR destination against this list.

### Ticket Printer (`ticket_printer.dart`)
Receives validated data from OfflineQrService.  
**Input**: Validated `OfflineQrResult.data` with origin, destination, fare.

### Local Storage (`scan_storage.dart`)
Persists validated scans for offline audit.  
**Keyed By**: `transactionId` to enable duplicate detection.

---

## Testing Checklist

- [ ] QR with valid origin/destination → Success
- [ ] QR with invalid origin → Error: "System could not determine..."
- [ ] QR with destination not in dropdown → Error: "System could not determine..."
- [ ] QR with North route, invalid direction → Error: "Passenger is out of route..."
- [ ] QR with South route, invalid direction → Error: "Passenger is out of route..."
- [ ] QR with mismatched bus number → Error: "Passenger boarded the wrong bus"
- [ ] QR with non-GCash payment → Error: "Payment method not GCash"
- [ ] Same QR scanned twice → Error: "Ticket already used"
- [ ] QR with missing required field → Error: "Missing field: {fieldName}"
- [ ] QR with base64 encoding → Success (auto-detected)
- [ ] QR with fuzzy station names → Success (matched)

---

## Performance Notes

- **Parsing**: O(1) for both JSON and base64 paths
- **Validation**: O(n) for station list iteration (54 stations, negligible)
- **Storage**: O(1) Hive box lookup by transaction ID
- **Memory**: Single 54-element station list constant (reusable)

---

## Future Enhancements

1. **Real-Time Validation**: Connect to Firebase for online route updates
2. **Multi-Bus Support**: Validate destination based on vehicle route (currently hardcoded North/South)
3. **Offline Sync**: Queue pending validations for cloud sync when online
4. **Analytics**: Track validation failures for operator training
5. **Enhanced Fuzzy Matching**: Support phonetic matching for misspelled stations

---

## Files Modified

| File | Changes |
|------|---------|
| `lib/services/route_validation_service.dart` | Created: centralized station list, index-based validation |
| `lib/services/offline_qr_service.dart` | Refactored: uses RouteValidationService, integrates FareTable |
| `lib/utils/fare_calculator.dart` | No changes (already had placeNames) |
| `lib/screens/qr_scanner_screen.dart` | No changes (already uses QRValidationService) |

---

## Backwards Compatibility

**Old RouteValidator.dart**: Still exists, may be deprecated  
**QRValidationService**: Wraps RouteValidator, should be updated to use new service  
**BookingStationMapping**: Can be simplified to use RouteValidationService.getStationIndex()

---

## Migration Guide

If you have code using the old `RouteValidator`, replace with:

```dart
// OLD
import 'utils/route_validator.dart';
final result = RouteValidator.validateRoute(origin, dest, direction);

// NEW
import 'services/route_validation_service.dart';
final originIdx = RouteValidationService.getStationIndex(origin);
final destIdx = RouteValidationService.getStationIndex(destination);
final result = RouteValidationService.validateRouteDirection(originIdx, destIdx, direction);
```

---

**Document Version**: 1.0  
**Author**: System Refactor  
**Reviewed**: January 5, 2025
