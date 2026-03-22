# AFCS POS App (Automated Fare Collection System Point of Sale)

A high-performance Flutter application designed for modern bus transit systems, optimized for Android POS hardware (specifically **Senraise** devices) with built-in thermal printers and NFC readers.

---

## 🚀 System Overview

The AFCS POS App serves as the primary interface for bus conductors and drivers. It manages the entire lifecycle of a bus trip—from driver dispatch and passenger boarding to ticket issuance and real-time inspections—all while maintaining a strict **Offline-First** philosophy.

### Key Capabilities:
*   **Offline-First Operation:** Issues tickets, validates bookings, and records inspections without an internet connection using local persistence.
*   **Hardware Integration:** Native control over thermal printers, NFC readers (ISO/IEC 14443), and hardware QR scanners.
*   **Hybrid Synchronization:** Automatically syncs data to **Firebase Firestore** when online and optionally communicates with a **Raspberry Pi Gateway** for local event processing.
*   **NFC-Driven Workflows:** Authenticates staff and triggers inspections via physical card taps that intercept any active screen.

---

## 🏗️ Technical Architecture

### 1. Persistence Layer (`local_storage.dart`)
Built on **Hive**, the app uses a series of high-performance local "boxes" to ensure data integrity during power loss or offline periods.
*   **Outboxes:** Queues for Inspections, Arrival Reports, and Pi Gateway events.
*   **State Boxes:** Persistence for active sessions (Conductor/Driver), current trip details, and assigned bus IDs.
*   **Cache Boxes:** Validated QR scans and walk-in ticket records.

### 2. Networking & Synchronization
*   **Cloud Sync:** `SyncService` and specialized background services (`InspectionSyncService`, `ArrivalReportSyncService`) monitor connectivity and push queued data to Firebase.
*   **Local Gateway:** `PiGatewayService` enqueues events (e.g., dispatch status changes) and attempts delivery to a local Raspberry Pi server at a configurable IP (default `192.168.4.2`).
*   **SMS Bridge:** `SmsBookingAlertService` allows the app to receive passenger booking notifications via silent SMS, enabling ticket validation even in areas with zero data coverage.

### 3. Hardware Services (`lib/services/`)
*   **`TicketPrinter`:** Abstraction for `flutter_senraise_printer_sdk`. Manages ticket layouts, thermal paper formatting (58mm), and hardware state.
*   **`NFCReaderModeService` & `NFCListenerService`:** Triggers native Android "Reader Mode" for ultra-fast, continuous tag detection. It identifies:
    *   **Driver/Conductor Cards:** Automates session login and bus assignment.
    *   **Inspector Cards:** Force-navigates the app to the Inspection screen via `InspectorNFCHandler`.
    *   **Passenger NFC:** (Extensible) for future smart-card fare collection.
*   **`QRValidationService` & `OfflineQrService`:** Implements a multi-step pipeline for validating passenger tickets.

---

## 🔄 Core Web/Hardware Workflows

### QR & Route Validation
The system uses a centralized **Index-Based Validation** system (`RouteValidationService`) to ensure passenger safety and revenue integrity.
*   **Route Sequence:** A canonical 54-station list (e.g., Nasugbu to Batangas).
*   **Fuzzy Matching:** Handles variations in station names ("Lian" vs "Lian Shed") to ensure QR codes from external booking systems are always recognized.
*   **Directional Logic:** Validates that the passenger is traveling in the correct direction (North/South) based on station indices.

### The Validation Pipeline (12 Steps):
1.  **Parse Payload:** Decode JSON or Base64 QR strings.
2.  **Normalize Keys:** Handle field name variations across different booking platforms.
3.  **Map Aliases:** Convert raw keys into canonical internal fields.
4.  **Field Check:** Ensure mandatory fields like `busNumber` and `transactionId` exist.
5.  **Payment Validation:** Enforce payment rules (e.g., GCash-only for specific QR types).
6.  **Bus Matching:** Ensure the passenger is on the correct assigned bus.
7.  **Route Match:** Verify the origin and destination belong to the active route.
8.  **Direction Check:** Compare origin index vs. destination index against the current trip direction.
9.  **Duplicate Check:** Query `ScanStorage` to prevent ticket re-use.

---

## 📁 Project Structure

### `lib/services/` (The Brain)
*   **`app_state.dart`:** Singleton managing the reactive session state.
*   **`booking_status_orchestrator_service.dart`:** Determines if a passenger can board based on local vs. cloud data.
*   **`device_config_service.dart`:** Manages bus assignments and gateway configurations.
*   **`route_validation_service.dart`:** The source of truth for all station sequences and directional rules.

### `lib/screens/` (The Interface)
*   **`home_screen.dart`:** Central dashboard showing trip stats, current station, and quick actions.
*   **`qr_scanner_screen.dart`:** High-speed scanning interface with real-time feedback.
*   **`inspector_screen.dart`:** Secure view for auditors to verify all passengers on board.
*   **`arrival_report_screen.dart`:** Detailed end-of-trip summary with mileage and passenger counts.

### `lib/models/` (Data Typing)
*   `booking.dart`, `dispatch_details.dart`, `inspection.dart`, `qr_data.dart`.

---

## 🛠️ Setup & Requirements

### Hardware Requirements
*   **Android POS:** 5.0+ (Senraise/Sunmi preferred).
*   **NFC:** ISO/IEC 14443 Type A/B support.
*   **Printer:** 58mm thermal printer integrated via SDK.

### Development Setup
1.  **Initialize Flutter:** `flutter pub get`
2.  **Firebase:** Ensure `google-services.json` is present in `android/app/`.
3.  **Build:**
    ```bash
    flutter build apk --release
    ```

### Initialization Sequence
At startup (`main.dart`), the app performs the following:
1.  **`LocalStorage.init()`**: Opens Hive boxes.
2.  **`Firebase.initializeApp()`**: Prepares cloud sync.
3.  **`DeviceConfigService.autoDetect()`**: Attempts to identify the bus based on hardware ID.
4.  **`NFCReaderModeService.start()`**: Activates background tag detection.
5.  **`SmsBookingAlertService.start()`**: Begins listening for offline booking updates.

---
*Note: This documentation is maintained for Version 1.1.0 (Refactored QR Validation System). For detailed station indices, refer to [STATION_SEQUENCE_REFERENCE.md](STATION_SEQUENCE_REFERENCE.md).*