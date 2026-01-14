# QR Validation Architecture Diagram

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                      QR SCANNING SYSTEM                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────────┐           ┌──────────────────────┐       │
│  │   QR Scanner Screen  │           │   Manual Entry Form  │       │
│  │  (Mobile Camera QR)  │           │  (Keyboard Input)    │       │
│  └──────────────────────┘           └──────────────────────┘       │
│            │                                    │                   │
│            └────────────┬────────────────────────┘                  │
│                         ▼                                           │
│              ┌──────────────────────┐                              │
│              │ Normalize & Parse QR │                              │
│              │ (JSON + Base64)      │                              │
│              └──────────────────────┘                              │
│                         │                                           │
│                         ▼                                           │
│       ┌─────────────────────────────────────────┐                 │
│       │  VALIDATION PIPELINE (12 Steps)        │                 │
│       ├─────────────────────────────────────────┤                 │
│       │ 1. Parse QR Payload                    │                 │
│       │ 2. Normalize Keys                      │                 │
│       │ 3. Map to Canonical Fields             │                 │
│       │ 4. Check Required Fields               │                 │
│       │ 5. Default Payment Method              │                 │
│       │ 6. Validate Payment Method             │                 │
│       │ 7. Validate Bus Number                 │                 │
│       │ 8. Validate Origin (RouteValService) ◄─┤─ Uses Index    │
│       │ 9. Validate Destination Dropdown   ◄──┤─ Uses Index    │
│       │ 10. Get Destination Index          ◄──┤─ Uses Index    │
│       │ 11. Validate Route Direction       ◄──┤─ Uses Index    │
│       │ 12. Check Duplicate & Save            │                 │
│       └─────────────────────────────────────────┘                 │
│                         │                                           │
│                         ▼                                           │
│       ┌─────────────────────────────────────────┐                 │
│       │     ROUTEVALIDATIONSERVICE              │                 │
│       │     (Single Source of Truth)           │                 │
│       ├─────────────────────────────────────────┤                 │
│       │ stationSequence (54 stations)           │                 │
│       │ ├─ Index 0: Nasugbu Terminal           │                 │
│       │ ├─ Index 1: Lian Shed                  │                 │
│       │ ├─ ...                                 │                 │
│       │ └─ Index 53: Batangas Terminal         │                 │
│       │                                        │                 │
│       │ getStationIndex(name) → int            │                 │
│       │ validateRouteDirection(...) → Result   │                 │
│       │ isValidDestination(...) → bool         │                 │
│       └─────────────────────────────────────────┘                 │
│                         │                                           │
│                         ▼                                           │
│       ┌─────────────────────────────────────────┐                 │
│       │        VALIDATION RESULT                │                 │
│       ├─────────────────────────────────────────┤                 │
│       │ ✓ Success: Valid QR, proceed           │                 │
│       │ ✗ Error: Show error message to operator│                 │
│       └─────────────────────────────────────────┘                 │
│                         │                                           │
│         ┌───────────────┴───────────────┐                          │
│         │                               │                          │
│         ▼ (Success)                     ▼ (Error)                 │
│  ┌──────────────────────┐      ┌──────────────────────┐          │
│  │ Booking Confirmation │      │   Error Dialog       │          │
│  │ - Show passenger info│      │ - Show error message │          │
│  │ - Select fare type   │      │ - Suggest correction │          │
│  │ - Confirm fare       │      └──────────────────────┘          │
│  └──────────────────────┘                                         │
│         │                                                          │
│         ▼                                                          │
│  ┌──────────────────────┐                                         │
│  │ Ticket Printer       │                                         │
│  │ - Print thermal slip │                                         │
│  │ - Record transaction │                                         │
│  └──────────────────────┘                                         │
│         │                                                          │
│         ▼                                                          │
│  ┌──────────────────────┐                                         │
│  │ ScanStorage (Hive)   │                                         │
│  │ - Persist QR data    │                                         │
│  │ - Prevent duplicates │                                         │
│  └──────────────────────┘                                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Validation Flow: Index-Based Route Logic

```
USER SCANS QR
    │
    ├─ Origin: "Lian Shed"
    ├─ Destination: "Palico Terminal"
    └─ Route: "North"
         │
         ▼
    ┌────────────────────────────────┐
    │ RouteValidationService         │
    │ getStationIndex("Lian Shed")   │
    │ → Returns: 1                   │
    └────────────────────────────────┘
         │
         ▼
    ┌────────────────────────────────┐
    │ RouteValidationService         │
    │ getStationIndex("Palico Term")│
    │ → Returns: 6                   │
    └────────────────────────────────┘
         │
         ▼
    ┌────────────────────────────────────────┐
    │ validateRouteDirection(1, 6, "North")   │
    │                                        │
    │ Rules:                                 │
    │ - North: originIndex < destIndex      │
    │ - Check: 1 < 6? YES ✓                │
    │                                        │
    │ Result: success = true                │
    └────────────────────────────────────────┘
         │
         ▼
    ✓ VALID - PROCEED
```

---

## Station Sequence Visualization

```
NORTH ROUTE →  (Nasugbu → Batangas)

Index 0:   Nasugbu Terminal           ◄─ Route Start
Index 1:   Lian Shed                  │
Index 2:   Sagbat                     │
Index 3:   Central                    │
Index 4:   Irrigation Waiting Shed    │
...                                   │
Index 15:  Brgy. Hall Lanatan         │
Index 16:  Balayan Waltermart         │
Index 17:  Spyder Fuel Gumamela       │  Distance increases
Index 18:  Gimalas                    │  (more stops from origin)
...                                   │
Index 34:  Lemery Xentro Mall         │
Index 35:  Laguile Food House         │
...                                   │
Index 50:  Citimart Bauan             │
Index 51:  San Antonio                │
Index 52:  San Pascual                │
Index 53:  Batangas Terminal          ◄─ Route End

VALIDATION RULE:
  Origin Index < Destination Index
  (Passenger travels forward/northward)
```

---

## Field Normalization & Aliasing

```
RAW QR PAYLOAD
    │
    ├─ "transactionId" or "txn" or "txnid"
    ├─ "busNumber" or "vehicleNo" or "vehicleNumber"
    ├─ "busRoute" or "route"
    ├─ "origin" or "from" or "fromPlace" or "originPlace"
    ├─ "destination" or "to" or "toPlace" or "destinationPlace"
    ├─ "fare" or "amount" or "price" or "fareAmount"
    ├─ "paymentMethod" or "method" or "payment" or "paymentType"
    ├─ "paymentStatus" or "status"
    └─ "createdAt" or "createdAtIso" or "created" or "timestamp"
         │
         ▼
    NORMALIZE KEYS
    (Strip spaces/underscores, lowercase)
         │
         ▼
    CANONICAL FIELD NAMES
    {
      'transactionId': <value>,
      'busNumber': <value>,
      'origin': <value>,
      'destination': <value>,
      'fare': <value>,
      'paymentMethod': <value>,
      'paymentStatus': <value>,
      'createdAt': <value>
    }
         │
         ▼
    VALIDATED & PROCESSED
```

---

## Error Handling Decision Tree

```
QR VALIDATION
    │
    ├─ Invalid QR Format?
    │  └─ Error: "Invalid QR payload"
    │
    ├─ Missing Required Field?
    │  └─ Error: "Missing field: {fieldName}"
    │
    ├─ Payment Method ≠ GCash?
    │  └─ Error: "Payment method not GCash"
    │
    ├─ Bus Number Mismatch?
    │  └─ Error: "Passenger boarded the wrong bus"
    │
    ├─ Origin Not in Station List?
    │  └─ Error: "System could not determine the origin or destination"
    │
    ├─ Destination Not in Dropdown?
    │  └─ Error: "System could not determine the origin or destination"
    │
    ├─ Route Direction Violation?
    │  └─ Error: "Passenger is out of route and going to the wrong direction"
    │
    ├─ Already Scanned (Duplicate)?
    │  └─ Error: "Ticket already used"
    │
    └─ All Checks Passed?
       └─ Success: "OK" + Validated Data
```

---

## Data Flow: QR → Validation → Storage

```
┌──────────────────────┐
│  QR Camera Capture   │
│  Raw string data     │
└──────────────────────┘
        │
        ▼
┌──────────────────────────────────────────┐
│  OfflineQrService.validateAndProcess()   │
│                                          │
│  1. Parse (JSON or Base64)              │
│  2. Normalize keys                      │
│  3. Map aliases to canonical fields     │
│  4-7. Basic validation                  │
│  8-11. RouteValidationService checks   │
│  12. Duplicate check via ScanStorage    │
└──────────────────────────────────────────┘
        │
        ├─ ✓ Success
        │   └─ OfflineQrResult { success: true, data: {...} }
        │       │
        │       ▼
        │   ┌──────────────────────────────┐
        │   │ BookingConfirmationScreen    │
        │   │ - Show QR data to conductor  │
        │   │ - Select passenger type      │
        │   │ - Confirm fare calculation   │
        │   └──────────────────────────────┘
        │       │
        │       ▼
        │   ┌──────────────────────────────┐
        │   │ TicketPrinter                │
        │   │ - Print thermal receipt      │
        │   │ - Format: 58mm width         │
        │   └──────────────────────────────┘
        │       │
        │       ▼
        │   ┌──────────────────────────────┐
        │   │ ScanStorage (Hive)           │
        │   │ - Key: transactionId         │
        │   │ - Value: full record         │
        │   │ - Timestamp: scannedAt       │
        │   │ - Payload: original QR JSON  │
        │   └──────────────────────────────┘
        │
        └─ ✗ Error
           └─ OfflineQrResult { success: false, message: "..." }
               │
               ▼
           ┌──────────────────────────────┐
           │ Error Dialog                 │
           │ - Show message to operator   │
           │ - Log error for debugging    │
           └──────────────────────────────┘
```

---

## Class Dependencies

```
QrScannerScreen
    │
    ├─ Uses: QRValidationService
    │   └─ Uses: RouteValidator (OLD - should migrate)
    │
    ├─ Uses: OfflineQrService (NEW)
    │   ├─ Uses: RouteValidationService (NEW - centralized)
    │   ├─ Uses: FareTable
    │   │   └─ Provides: placeNames list
    │   └─ Uses: ScanStorage
    │       └─ Persists: validated QR data
    │
    ├─ Uses: TicketPrinter
    │   └─ Prints: validated ticket receipt
    │
    └─ Uses: FareTable
        └─ Provides: fare calculation
```

---

## RouteValidationService Class Structure

```
┌─────────────────────────────────────────────────────────┐
│  RouteValidationService                                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Constants:                                            │
│  ├─ stationSequence: List<String> (54 stations)       │
│  │  └─ ['Nasugbu Terminal', ..., 'Batangas Terminal'] │
│  │     Index 0 ────────────────────────── Index 53   │
│  │                                                    │
│  Static Methods:                                      │
│  ├─ getStationIndex(String?) → int                   │
│  │  ├─ Input: Station name (any case/format)        │
│  │  ├─ Fuzzy: Exact then substring matching         │
│  │  └─ Output: Index 0-53 or -1 if not found       │
│  │                                                   │
│  ├─ validateRouteDirection(...) → ValidationResult   │
│  │  ├─ Input: originIdx, destIdx, routeDir         │
│  │  ├─ Logic: North rule (originIdx < destIdx)     │
│  │  │         South rule (originIdx > destIdx)     │
│  │  └─ Output: {success: bool, message?: String}   │
│  │                                                   │
│  └─ isValidDestination(...) → bool                  │
│     ├─ Input: destination, availableDestinations   │
│     ├─ Logic: Check if dest in available list     │
│     └─ Output: true/false                          │
│                                                     │
│  Private Methods:                                   │
│  └─ _normalizeStationName(String?) → String       │
│     └─ Trim, lowercase, collapse spaces           │
│                                                    │
│  Nested Classes:                                   │
│  └─ ValidationResult                              │
│     ├─ success: bool                              │
│     └─ message: String?                           │
│                                                    │
└─────────────────────────────────────────────────────────┘
```

---

## Integration Checklist

- [ ] Import `RouteValidationService`
- [ ] Import `OfflineQrService`
- [ ] Import `FareTable` for available destinations
- [ ] Update QR scanner to call `OfflineQrService.validateAndProcess()`
- [ ] Pass `availableDestinations: FareTable.placeNames`
- [ ] Handle success: show booking confirmation
- [ ] Handle error: show error dialog with message
- [ ] Persist validated data to `ScanStorage`
- [ ] Print ticket using `TicketPrinter`
- [ ] Test with sample QR codes

---

**Diagram Version**: 1.0  
**Last Updated**: January 5, 2025  
**Related**: [QR_VALIDATION_REFACTOR.md](QR_VALIDATION_REFACTOR.md) | [USAGE_GUIDE.md](USAGE_GUIDE.md)
