# StarExpress POS Code Reference

Last analyzed: 2026-04-30

This file is a working reference for future changes to the POS codebase. It summarizes the current code structure, important flows, storage layout, Firebase collections, and the places to edit when changing common behavior. Treat the code as the final source of truth, but use this as the map before diving in.

## Project Snapshot

StarExpress POS is a Flutter application for Android POS devices used in bus operations. It supports conductor/driver NFC login, bus dispatch, walk-in ticket printing, booking QR validation, passenger counting, inspections, arrival reports, and offline-first syncing.

Primary technologies:

- Flutter/Dart application in `lib/`.
- Android native Kotlin bridge in `android/app/src/main/kotlin/com/example/untitled/MainActivity.kt`.
- Local Senraise printer plugin in `packages/flutter_senraise_printer_sdk/`.
- Hive for offline-first local storage.
- Firebase Core, Auth, Firestore, and Realtime Database.
- Native NFC ReaderMode, SMS receive/send bridges, QR scanning, and thermal printing.

## Top-Level Structure

```text
POS/
	lib/
		main.dart                    App startup and global service bootstrap.
		local_storage.dart           Central Hive storage facade.
		firebase_options.dart        Generated Firebase platform options.
		theme.dart                   Currently empty.
		models/                      Data models and BookingManager.
		screens/                     User-facing Flutter screens/workflows.
		services/                    Hardware, sync, Firebase, NFC, SMS, RTDB services.
		utils/                       Fare table, route validation, station mapping, dialogs.
		widgets/                     Shared UI widgets/dialogs.
	android/                       Android host app and native platform channels.
	ios/linux/macos/windows/web/   Generated Flutter platform folders.
	packages/flutter_senraise_printer_sdk/
																Local printer plugin wrapping Senraise receipt service.
	test/                          Flutter unit/widget tests.
	tools/                         Export/check helper scripts.
	scripts/                       Mermaid rendering helper.
	docs/                          Mermaid system flowchart.
	firebase.json                  Firebase CLI config.
	firestore.rules                Firestore security rules.
	firestore.indexes.json         Firestore index config.
	pubspec.yaml                   Flutter dependencies/assets.
	package.json                   Node dependency for Firebase admin export script.
```

Generated/build folders such as `build/`, `.dart_tool/`, and platform build outputs should not be used as source references.

## App Startup

Entry point: `lib/main.dart`

Startup sequence:

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. `LocalStorage.init()` opens Hive boxes. NFC employee identities are resolved from Firebase and cached after successful lookup.
3. Firebase initializes with `DefaultFirebaseOptions.currentPlatform`.
4. Device bus assignment is cleared and auto-detected with `DeviceConfigService.autoDetectAndSaveAssignedBus()`.
5. Senraise printer service version is checked best-effort.
6. `AfcsApp` starts.

`AfcsApp.initState()` starts the long-lived app services:

- `NFCReaderModeService.instance.start()` for native Android NFC ReaderMode events.
- `AppState.instance.startNfcListener()` for app-wide driver and dispatcher NFC handling.
- `InspectionSyncService()` for inspection sync on connectivity changes.
- `SmsBookingAlertService().startListening()` for SMS/Firebase booking alerts.
- `BookingStatusOrchestratorService().initialize()` for booking status update retries.

Navigation root:

- `home: SplashScreen()`.
- Global `navigatorKey` supports inspector NFC deep navigation.
- Named route `/inspector` builds `InspectorScreen` using the current route from local storage.

## Main Dependencies

Declared in `pubspec.yaml`:

- `senraise_printer` from `packages/flutter_senraise_printer_sdk`.
- `flutter_nfc_kit` and native ReaderMode channel for NFC.
- `mobile_scanner` for QR scanning.
- `hive`, `hive_flutter`, `path_provider` for local/offline storage.
- `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_database`.
- `connectivity_plus`, `http`, `android_intent_plus`, `intl`.
- `permission_handler`, `shared_preferences`, `uuid`.

Analyzer config:

- `analysis_options.yaml` includes `flutter_lints` but disables many strict style/documentation lints.
- `packages/**` is excluded from analyzer checks.

## Local Storage Layout

Main facade: `lib/local_storage.dart`

Hive boxes opened or used by the app:

- `employees`: cached NFC employee records. Employee identities come from Firebase `user_accounts` after successful lookup by NFC UID fields; no employee card data is seeded locally.
- `bookings`: persisted bookings by trip/conductor.
- `session`: current conductor, driver, trip, route, last screen, manual mode, accepted schedule.
- `inspections`: saved inspection records and sync state.
- `scanned_tickets`: scanned booking ticket history for duplicate prevention and reports.
- `walkins`: walk-in passenger ticket records.
- `trips`: trip lifecycle/history records.
- `consumed_bookings`: durable anti-replay store for booking IDs. This intentionally survives session/trip clears.
- `device_config`: assigned bus, device serial/androidId, Pi gateway URL.
- `sms_booking_alerts`: latest SMS/Firebase booking alert items.
- `booking_status_pending`: queued booking status updates.
- `arrival_reports_pending`: legacy offline arrival report queue. Current POS arrival flow no longer writes new pending reports.
- `pi_gateway_outbox`: pending Raspberry Pi gateway events.
- `fare_table_entries`: cached Firestore fare table rows and sync metadata.

Important LocalStorage behavior:

- `LocalStorage.init()` also normalizes cached NFC UID keys.
- `clearSession()` clears conductor/driver/session, trips, bookings, scanned tickets, but does not clear `consumed_bookings`.
- `startNewTrip()`, `finalizeTrip()`, `setCurrentTripId()`, `setCurrentTripStatus()`, `setCurrentVehicleNo()`, `setCurrentRoute()`, and accepted schedule helpers are the trip/session source of truth.
- `saveBookingForTrip()`, `loadBookingsForTrip()`, `saveWalkin()`, `loadWalkinsForTrip()`, `saveScannedTicket()`, and `loadScannedTicketsForTrip()` feed passenger counts and final `trip_records` arrival data.
- `saveFareTableEntries()`, `loadFareTableEntries()`, and `getFareTableCacheMetadata()` support Firestore-backed fare/station data without clearing it during trip/session resets.

## Global Runtime State

Main singleton: `lib/services/app_state.dart`

Tracks:

- Current conductor.
- Current driver.
- Pending driver change.
- Inspector modal active flag.
- Current screen name.
- Trip-cancelled lock state.

App-wide NFC behavior:

- Driver card sets the active driver if none exists.
- Different driver card sets `pendingDriver` until dispatcher approval.
- Dispatcher card approves pending driver changes.

## Data Models

`lib/models/booking.dart`

- `Booking`: shared booking/walk-in passenger model used across screens and reports.
- Supports `passengerType` plus optional `passengerTypes` for multi-seat bookings.
- `expandToIndividualPassengers()` splits bulk bookings into seat-level records for reporting.
- `BookingManager`: in-memory singleton list plus persistence by conductor through `LocalStorage`.

`lib/models/qr_data.dart`

- Parses QR JSON payloads.
- Accepts multiple field aliases for fare, bus number, passenger count, seats, and schedule metadata.
- Normalizes assigned bus numbers.

`lib/models/scanned_ticket.dart`

- Represents completed scanned booking tickets.
- Includes booking/transaction IDs, route, passenger type, fare breakdown, crew names, and printed flag.

`lib/models/inspection.dart`

- Represents inspection/audit reports.
- Has a compact `toRemoteMap()` for Firestore uploads.

`lib/models/dispatch_details.dart`

- Lightweight dispatch details object.

## Screen Map

`lib/screens/splash_screen.dart`

- Restores saved conductor/driver/trip when a valid departed trip exists.
- Uses local trip status first; Firestore schedule status as fallback.
- Loads conductor bookings into `BookingManager`.
- Navigates to `HomeScreen` or `LoginScreen`.

`lib/screens/login_screen.dart`

- Signs in the POS device before reading Firestore schedules or resolving employee cards.
- Listens to Firestore `schedules` for the assigned bus.
- Requires schedule status `departed` before conductor/driver NFC login proceeds.
- Scans conductor and driver NFC cards and requires Firebase-validated `user_accounts` records with matching UID fields and `enabled == true`.
- Saves trip ID, vehicle number, route, conductor, and driver locally.
- Navigates to `HomeScreen` with resolved route direction.

`lib/services/employee_account_service.dart`

- Looks up tapped conductor/driver cards in Firestore `user_accounts` using POS device auth. UID-keyed docs are read directly; authUid-keyed docs are found through `employeeUidLower`/`employeeUid` field queries.
- Normalizes NFC UIDs so `employeeUid`, `employeeUidLower`, and raw reader variants compare as the same card.
- Accepts only enabled `conductor` and `driver` accounts, maps them into the existing local employee shape, and caches successful lookups in Hive.

`lib/screens/home_screen.dart`

- Main conductor screen.
- Shows route selectors, passenger type, quantity, walk-in print, QR scanner, booking alerts, and menu drawer.
- Auto-detects assigned bus and starts `RtdbOccupancyPublisherService`.
- Starts `TripRecordLiveService` after schedule context is ready so Firestore `trip_records/{scheduleTripId}` updates during the trip.
- Refreshes active schedule context from local accepted schedule first, then Firestore.
- Filters active booking alerts by status, route order/direction, and schedule key.
- Walk-in print flow calculates fare from `FareCalculator`, prints a `WALK-IN TICKET`, and saves to `walkins`.
- Successful walk-in ticket saves trigger an immediate live trip record publish.
- QR scan flow opens `QrScannerScreen` after driver requirement is satisfied.
- Menu opens Profile, Bookings, Passengers, and dispatcher-authenticated Records.
- If trip-cancelled lock is active, operational actions are blocked except Records.

`lib/screens/qr_scanner_screen.dart`

- Uses `mobile_scanner` camera scanning.
- Parses `QRData`, then validates consumed status, duplicate scan, expiration, bus number, route, schedule metadata, schedule match, and online consumed status.
- Schedule metadata/match currently log warnings in the scanner during QR producer transition, even though service validators can return invalid results.
- Opens `BookingConfirmationScreen` for passenger type and fare confirmation.
- Prints booking ticket with `TicketPrinter`.
- Saves `ScannedTicket`, marks booking consumed, saves booking for trip, and adds to `BookingManager`.

`lib/screens/booking_confirmation_screen.dart`

- Confirms QR booking fare and passenger types.
- For multi-passenger bookings, assigns passenger type per seat.
- Uses `BookingFareCalculator` per seat, then sums final fare.
- Original fare is computed as regular fare per seat times passenger count.
- Discount is `regular_total - computed_total`, clamped at zero.
- Queues `on-board` status through `BookingStatusOrchestratorService`.

`lib/screens/passenger_type_selection_screen.dart`

- Older/simpler passenger type screen that calculates fare with `FareCalculator`.
- The current QR scanner flow uses `BookingConfirmationScreen` instead.

`lib/screens/bookings_screen.dart`

- Shows booking passengers from `BookingManager`.
- Sorts on-board first, then dropped-off records.
- Marks bookings dropped off by updating local state and calling `BookingStatusOrchestratorService.updateStatus(status: dropped-off)`.

`lib/screens/booking_alerts_screen.dart`

- Shows active booking alerts from `SmsBookingAlertService`.
- Filters latest alert per booking by active status, route direction/order, and schedule key.

`lib/screens/passengers_screen.dart`

- Combines `BookingManager` bookings and current-trip walk-ins.
- Computes passenger count at current location using `fromIdx <= currentIdx < toIdx`.
- Shows scheduled drop-offs and trip revenue.

`lib/screens/inspector_screen.dart`

- Inspector audit workflow.
- Uses route direction and FareTable stops to calculate expected on-board count.
- Inspector enters manual count, then inspector and conductor NFC cards confirm signatures.
- Saves inspection locally and triggers `InspectionSyncService().syncNow()`.

`lib/screens/profile_screen.dart`

- Shows conductor/driver/trip identity.
- Allows driver registration/change with dispatcher approval.
- Blocks logout while active accepted schedule/trip lock is active.
- Logout requires the same conductor NFC card.
- Sends emergency cancel trip signal through `FirebaseDispatchService.sendCancelTripSignal()` and locks session to records/reporting.

`lib/screens/records_screen.dart`

- Dispatcher-authenticated trip summary.
- Requires driver tap if no active driver is registered.
- Aggregates current-trip bookings and walk-ins.
- Requires connectivity before proceeding to `ArrivalReportScreen`.

`lib/screens/arrival_report_screen.dart`

- Displays and prints final arrival report.
- Expands multi-seat bookings before ticket type summaries.
- Prints walk-in and booking ticket lists through Senraise printer methods.
- Writes final arrival data into the existing Firestore `trip_records/{scheduleTripId}` document.
- Marks the schedule status as `arrived` after successful print and trip-record completion.
- Publishes final zero occupancy to RTDB and finalizes/clears trip/session state.

`lib/screens/dispatch_screen.dart`

- Claims a pre-departure schedule for assigned bus.
- Requires driver NFC confirmation.
- Calls `FirebaseDispatchService.claimAndDispatchSchedule()`.
- Saves accepted schedule locally for offline schedule context.
- Clears previous conductor/bookings and returns to login.

`lib/screens/next_day_dispatch_screen.dart`

- Similar dispatch flow for next-day/pre-departure schedule.
- Includes a driver-controlled lock/unlock path.

`lib/screens/device_setup_screen.dart`

- Manual fallback for selecting/entering a known device serial.
- Looks up bus assignment in `DeviceConfigService`.

`lib/screens/device_config_screen.dart`

- Currently empty.

`lib/screens/sync_status_screen_example.dart`

- Example screen for `InspectionSyncStatusWidget`.

## Core Services

`lib/services/device_config_service.dart`

- Central registry mapping known serials/androidIds to bus numbers.
- Current known assignments include BUS-001 and BUS-002 identifiers.
- Persists assigned bus and device serial in Hive `device_config`.
- Also stores optional Pi gateway base URL.
- This is the main file to edit when adding/replacing POS hardware.

`lib/services/device_identifier_service.dart`

- Calls native `com.example.untitled/device` channel to get Android ID, serial, manufacturer, and model.

`lib/services/nfc_reader_mode_service.dart`

- Flutter side of native NFC ReaderMode.
- Uses method channel `com.example.untitled/nfc` and event channel `com.example.untitled/nfc_tags`.
- Resolves tapped employee cards through `EmployeeAccountService`, using Firebase first and only falling back to Firebase-sourced cache records.
- Emits employee maps or an unknown-card payload to `onTag` stream.
- Has 2-second same-UID debounce and `resetDebounce()`.

`lib/services/inspector_nfc_handler.dart`

- Global handler that navigates to inspector screen when inspector card is tapped.
- Uses global `navigatorKey`.

`lib/services/qr_validation_service.dart`

- Validates QR bus number against assigned device bus.
- Validates route order through `RouteValidator`.
- Checks expiration.
- Checks duplicate current-trip scan in `scanned_tickets`.
- Checks durable consumed booking in `consumed_bookings`.
- Best-effort online consumed check against Firestore `bookings_archive` and `bookings`.
- Validates schedule metadata and active schedule key.

`lib/services/ticket_printer.dart`

- Formats ticket data into `SenraisePrinter.printReceipt()`.
- Handles station cleanup, date/time, route, fare breakdown, and print errors.

`lib/services/booking_status_orchestrator_service.dart`

- Source for booking `on-board` / `dropped-off` remote status transitions.
- Online path updates status in the first active booking collection that currently contains the document.
- POS does not move documents between `bookings_new`, `bookings`, and `bookings_archive`; collection transitions are handled by Cloud Functions.
- Offline/failure path queues to `booking_status_pending`.
- Flushes every 5 seconds and on connectivity restoration.
- SMS fallback happens after 15 seconds if Firestore cannot be used.

`lib/services/fare_table_cache_service.dart`

- Loads cached fare table rows from Hive at startup, before the UI reads station/fare helpers.
- Refreshes Firestore collection `fare_table_entries` once on service start when online, then when the cache is stale.
- Uses a 12-hour TTL plus online-transition refresh; it does not poll Firestore every few seconds.
- Keeps the currently loaded table if Firestore auth/read fails or remote data is incomplete.
- Reads all fare-table docs and skips only rows where `isActive == false`, so newly added rows without an `isActive` flag are still picked up.
- Logs the exact validation failure, such as a missing km row, when a remote table is rejected.
- Blank `place` rows are valid distance-fare rows: they are cached and used by `FareTable.getEntryByKm()`, but are hidden from station dropdown/display lists.
- Coordinates stored on ticketable `fare_table_entries` rows are cached together with fares so station names, order, and coordinates refresh in one path.
- Emits `FareTable.changes` so open station selectors such as Home FROM/TO, Passengers, and Inspector can refresh when remote station data changes.

`lib/services/sms_booking_alert_service.dart`

- Receives SMS through native event channel `com.example.untitled/sms_alerts`.
- Also listens to Firestore `bookings_new` and `bookings` for the assigned bus.
- Normalizes JSON, key-value, and regex-style SMS booking/status payloads.
- Stores latest active alert per booking in Hive.
- Reconciles stored alerts against live Firestore bookings every 15 seconds.

`lib/services/sms_status_sender_service.dart`

- Sends booking status and inspection fallback messages through native `com.example.untitled/sms_sender` method channel.

`lib/services/inspection_sync_service.dart`

- Watches connectivity and syncs unsynced inspections.
- Primary upload is Firestore collection `inspections`.
- Fallback is SMS inspection payload.
- Marks inspections synced or records sync errors in local storage.

`lib/services/arrival_report_sync_service.dart`

- Legacy sync service for old Hive `arrival_reports_pending` payloads.
- Current app startup does not run this service, and the current POS arrival flow no longer creates new `arrivalReports` documents.

`lib/services/firebase_dispatch_service.dart`

- Lazy-authenticated Firestore schedule/trip operations.
- Can write dispatch details and trip details.
- Can atomically claim a pre-departure schedule and set it to `departed`.
- Can send POS emergency cancellation signal by setting `cancelledAt` on active schedule.
- Can mark an active/departed schedule as `arrived` after POS arrival printing succeeds.

`lib/services/pos_device_auth_service.dart`

- Handles Firebase Auth sign-in for POS devices and checks POS role.
- Used lazily by Firestore sync/update services rather than blocking startup.

`lib/services/pi_gateway_service.dart`

- Queues local Raspberry Pi gateway events in Hive.
- Default base URL: `http://192.168.4.2:5000`.
- Posts to `/api/pos/events`.
- Supports dispatch and booking status events.

`lib/services/rtdb_gps_listener_service.dart`

- Listens to Firebase RTDB bus GPS at `/buses/{busRtdbId}`.
- Converts POS bus numbers like `BUS-001` to RTDB IDs like `BUS_01`.
- Resolves nearest station from `fare_table_entries` coordinates cached in `FareTable` when the station set has complete coordinates.
- Falls back to `StationRegistry` only when the fare-table-backed station coordinate set is incomplete.
- Re-resolves against the last known bus coordinate when `FareTable.changes` fires so live station names/orders update after a fare-table refresh.

`lib/services/realtime_count_service.dart`

- Read-only engine for on-board count.
- Uses same rule as passenger screen: on-board booking/walk-in counts when `fromIdx <= currentIdx < toIdx`.
- Resolves the current stop from the live station name supplied by the GPS listener instead of translating route order back through the bundled registry.

`lib/services/rtdb_occupancy_publisher_service.dart`

- Starts GPS listener and publishes occupancy to RTDB `/occupancy/{busRtdbId}`.
- Code publishes every 10 seconds.
- Payload fields: `busNumber`, `currentStation`, `onBoardCount`, `updatedAt`.
- Stops and publishes final zero-count update on arrival.
- Skips publishing when no active trip/crew or trip cancellation lock is active.

`lib/services/trip_record_live_service.dart`

- Publishes live trip summaries to Firestore `trip_records/{scheduleTripId}`.
- The document ID must match the schedule trip ID, such as `ntb1234~` or `btn1234~`; generated `TRIP-*` IDs are refused.
- Uses the same current passenger count as RTDB occupancy via `RealtimeCountService`.
- Updates every 10 seconds while active and immediately after walk-in, QR booking, and drop-off events.
- Stores summary totals only: current passengers, total tickets, QR booking sales, walk-in/cash sales, and combined total amount.
- Adds `updatedAt` on every remote write.
- Marks the same document `completed` on arrival and adds final `arrival`, `summary`, and `ticketManifest` data instead of creating an `arrivalReports` document.

`lib/services/offline_qr_service.dart`

- Alternative/static offline QR validation/processing path. Not the main scanner path currently used by `QrScannerScreen`.

`lib/services/internet_connection_service.dart`

- Connectivity helper for dialogs and network-required actions.

`lib/services/scan_storage.dart`

- Small scan cache with transaction/booking duplicate helpers.
- Older duplicate flow; current scanner mainly uses `LocalStorage`/`QRValidationService` checks.

## Utilities

`lib/utils/fare_calculator.dart`

- `FareTable`: canonical fare table and km list for Nasugbu to Batangas.
- `FareCalculator`: walk-in fare calculation from fare table distance and passenger type.
- `BookingFareCalculator`: booking QR fare calculation using booking station names and km mapping.
- Non-regular passenger types use the discounted fare column.

`lib/utils/route_validator.dart`

- Canonical booking station order from Nasugbu Terminal to Batangas Terminal.
- Reverses the list for south-to-north routes.
- Normalizes station names and aliases.
- Valid route requires origin index before destination index in the active direction list.

`lib/utils/booking_station_mapping.dart`

- Maps booking app station aliases to `RouteValidator` canonical station names.
- Important for QR route validation and booking fare calculation.

`lib/utils/station_mapping.dart`

- Legacy/helper mapping from generic `Station N` names to fare table place names.

`lib/utils/stops.dart`

- Exposes `fareTableStops` from `FareTable.placeNamesWithKm`.

`lib/utils/dialogs.dart`

- Shared message dialog helper.

`lib/utils/firestore_export.dart`

- Runtime utility for exporting Firestore collections to JSON files.

## Widgets

`lib/widgets/location_selector.dart`

- Inline dropdown-style location selector.

`lib/widgets/location_selector_bottomsheet.dart`

- Searchable bottom-sheet location selector.

`lib/widgets/internet_connectivity_dialog.dart`

- Dialog for checking internet and opening Android Wi-Fi settings before arrival flow.

`lib/widgets/internet_connection_dialog.dart`

- Similar network-required dialog built around `InternetConnectionService`.

`lib/widgets/inspection_sync_status_widget.dart`

- Displays inspection sync status and manual sync button.

## Native Android Integration

Host activity: `android/app/src/main/kotlin/com/example/untitled/MainActivity.kt`

Package/namespace notes:

- Kotlin package is `com.batmanstarexpress.afcs`.
- Android Gradle namespace is `com.batmanstarexpress.afcs`.
- Android `applicationId` is still `com.example.untitled`.
- Method channel names still use `com.example.untitled/...`.

Native channels:

- `com.example.untitled/nfc`: enable/disable NFC ReaderMode.
- `com.example.untitled/nfc_tags`: emits NFC UID events to Flutter.
- `com.example.untitled/device`: returns Android ID, serial, manufacturer, model.
- `com.example.untitled/sms_alerts`: emits incoming SMS payloads.
- `com.example.untitled/sms_sender`: sends SMS messages.
- `senraise_printer`: local plugin printer channel.

Android permissions in `AndroidManifest.xml`:

- `CAMERA` for QR scanning.
- `SEND_SMS`, `RECEIVE_SMS`, `READ_SMS` for booking/status SMS flows.
- Camera feature is optional.

NFC behavior:

- `MainActivity` enables ReaderMode in `onResume()` and disables it in `onPause()`.
- Flutter also calls enable/disable through `NFCReaderModeService`.
- Tags are emitted as uppercase hex UID strings.

SMS behavior:

- Incoming SMS receiver is registered only while the SMS EventChannel has a listener.
- Sending uses `SmsManager`, including multipart messages.

## Local Printer Plugin

Plugin folder: `packages/flutter_senraise_printer_sdk/`

Dart API:

- `SenraisePrinter` in `lib/senraise_printer.dart`.
- Wraps service version, raw text/image/barcode/QR printing, alignment, text size, bold, line height, code page, table printing, and `printReceipt()`.

Android implementation:

- `android/src/main/java/com/senraise/senraise_printer/SenraisePrinterPlugin.java`.
- Binds to Senraise `recieptservice.com.recieptservice.service.PrinterService`.
- Uses AIDL-style `PrinterInterface` methods.

POS app wrapper:

- `lib/services/ticket_printer.dart` converts POS ticket maps into `SenraisePrinter.printReceipt()` calls.
- `ArrivalReportScreen` uses lower-level Senraise table/text APIs directly for report printing.

## Firebase and RTDB Data Model

Firestore collections used by code/rules:

- `schedules`: dispatch schedule documents. POS reads assigned bus schedules, claims pre-departure schedules, sets `departed`, and can set `cancelledAt`.
- `bookings_new`: newly created/waiting bookings from customer/booking side.
- `bookings`: active/on-board bookings.
- `bookings_archive`: dropped-off or archived bookings.
- `arrivalReports`: historical/legacy final uploaded arrival report payloads. Current POS code does not create new documents here.
- `trip_records`: live and final Firestore trip summaries keyed by the schedule trip ID. POS writes one active/completed document per trip so admins can monitor current passengers, issued tickets, total amount, and final arrival manifest data.
- `tripDetails`: trip dispatch detail uploads.
- `inspections`: inspection reports.
- `fare_table_entries`: active fare table rows. Each document has `km`, `fare`, `discount`, `place`, `isActive`, and `createdAt`, and may also include station coordinates. Rows with blank `place` are valid and required for distance fare lookup, but are not ticketable stations.
- `users`: Firebase role documents for dispatcher/POS auth.
- `user_accounts`: role/login and employee account documents. NFC employee lookup reads enabled employee docs either keyed by `employeeUidLower` or keyed by Firebase `authUid` with matching `employeeUidLower`/`employeeUid` fields.

Realtime Database paths:

- `/buses/{busRtdbId}`: GPS input for a bus, e.g. `BUS_01`.
- `/occupancy/{busRtdbId}`: POS-published occupancy output.

Firestore security rules:

- POS device is allowed when authenticated user has role `pos` or email matching `@example.com`.
- `arrivalReports` is retained for historical compatibility; current POS final-arrival writes go to `trip_records`.
- `bookings_archive`, `tripDetails`, `inspections`, `trip_records`, and POS schedule updates rely on POS role.
- `trip_records` allows POS create/update only when payload `tripId` and `scheduleTripId` match the document ID; signed-in users can read.
- `user_accounts` allows POS direct `get` for NFC UID-shaped employee doc IDs and limited one-result NFC employee lookup queries; POS cannot write accounts.
- `bookings` and `bookings_new` allow public reads and authenticated owner/POS writes.
- `fare_table_entries` allows authenticated reads and admin writes, including optional coordinate fields for station-location updates.

## Main Workflows

### 1. Startup and Session Restore

1. `main.dart` initializes storage, Firebase, device assignment, and services.
2. `SplashScreen` checks saved conductor, driver, current trip ID, and trip status.
3. If valid departed trip exists, restore `AppState`, load bookings, and open `HomeScreen`.
4. Otherwise clear session and open `LoginScreen`.

### 2. Schedule-Based Login

1. `LoginScreen` signs in the POS device through `POSDeviceAuthService`.
2. It gets assigned bus from `DeviceConfigService`.
3. It listens to Firestore `schedules` where bus matches and status is `pre-departure` or `departed`.
4. Login is allowed only when selected schedule status is `departed`.
5. Conductor and driver NFC cards must resolve to enabled Firebase `user_accounts` docs with matching `employeeUid`/`employeeUidLower` and role `conductor` or `driver`.
6. Retrieved employee details are cached locally and saved into session state.
7. Schedule trip/route is saved locally and `HomeScreen` opens.

### 3. Dispatch Schedule Claim

1. `DispatchScreen` or `NextDayDispatchScreen` listens for `pre-departure` schedule for assigned bus.
2. Driver NFC confirms deploy.
3. `FirebaseDispatchService.claimAndDispatchSchedule()` transaction changes schedule status to `departed`, sets route and dispatch time.
4. POS stores current trip, route, vehicle, and accepted schedule locally.
5. Previous conductor/bookings are cleared and app returns to login.

### 4. Walk-In Ticket

1. Conductor selects from/to, passenger type, and quantity on `HomeScreen`.
2. Fare is calculated by `FareCalculator` using fare-table distance.
3. Driver must be present in `AppState`.
4. Senraise receipt prints `WALK-IN TICKET`.
5. Walk-in record is saved in current-trip `walkins` storage.

### 5. QR Booking Ticket

1. `HomeScreen` opens `QrScannerScreen`.
2. QR JSON becomes `QRData`.
3. QR validation checks local durable consumed booking, trip duplicate, expiration, bus number, route, schedule metadata/match warnings, and online consumed status.
4. `BookingConfirmationScreen` assigns passenger type(s) and computes fare from route/station distance.
5. Booking status is queued/updated to `on-board`.
6. Ticket is printed.
7. Scanned ticket is saved, booking is marked consumed, trip booking is saved, and `BookingManager` is updated.

### 6. Booking Drop-Off

1. `BookingsScreen` shows booking passengers.
2. Drop-off button changes local status to `dropped-off`.
3. `BookingStatusOrchestratorService` tries Firestore first.
4. POS writes the status update only; Cloud Functions handles any collection move/archive behavior.
5. If offline/failing, update is queued and SMS fallback may be used.

### 7. Passenger Counts and Occupancy

1. Passenger count combines `BookingManager` bookings and current-trip walk-ins.
2. Count rule: `status == on-board` and route position satisfies `fromIdx <= currentIdx < toIdx`.
3. `PassengersScreen`, `InspectorScreen`, and `RealtimeCountService` use this rule.
4. `RtdbGpsListenerService` resolves current station from RTDB GPS.
5. `RtdbOccupancyPublisherService` publishes count and station to RTDB occupancy node.
6. `TripRecordLiveService` publishes the same current count plus live ticket and amount totals to Firestore `trip_records/{scheduleTripId}`.

### 8. Inspection

1. Inspector NFC card globally opens `InspectorScreen`.
2. Inspector chooses current location and enters manual passenger count.
3. Inspector and conductor NFC cards confirm signatures.
4. Inspection is saved locally.
5. `InspectionSyncService` tries Firestore and falls back to SMS.

### 9. Arrival Report

1. Dispatcher card authorizes Records from `HomeScreen` menu.
2. `RecordsScreen` aggregates trip data and requires connectivity before arrival.
3. `ArrivalReportScreen` prints report.
4. `TripRecordLiveService` marks `trip_records/{scheduleTripId}` as `completed` with final totals, zero current passengers, arrival metadata, ticket type counts, and ticket manifest data.
5. `FirebaseDispatchService.markScheduleArrived()` updates the schedule status to `arrived`.
6. Occupancy final zero count is published.
7. Trip is finalized and session/local transient data is cleared.

### 10. Emergency Cancel Trip

1. `ProfileScreen` sends cancellation signal via `FirebaseDispatchService.sendCancelTripSignal()`.
2. Firestore schedule gets `cancelledAt` when active/departed.
3. `AppState.tripCancelledLocked` is set.
4. Operational actions are blocked; Records/Arrival Report remain available.

## Fare and Route Rules

Important rule for future modifications:

- Booking/scanned pricing must not use the QR `fareAmount` as the source of truth for totals or discounts.
- Source of truth is route/station distance plus passenger type via `FareCalculator` or `BookingFareCalculator`.
- For multi-seat bookings, compute fare per seat by selected passenger type, then sum.
- Discount is `regular_total - computed_total`, clamped at zero.
- Keep QR fare parsing for compatibility/audit only.

Passenger types currently used:

- `REGULAR`
- `STUDENT`
- `SENIOR`
- `PWD`
- `CHILD`

Direction keys:

- `north_to_south`: Nasugbu to Batangas.
- `south_to_north`: Batangas to Nasugbu.

Station/fare source files:

- Firestore source collection: `fare_table_entries`.
- Local cache service: `lib/services/fare_table_cache_service.dart`.
- Fare table and fare calculation: `lib/utils/fare_calculator.dart`.
- Primary live station-coordinate source: hydrated `FareTable` station rows derived from `fare_table_entries`.
- Canonical booking station order and route validation: `lib/utils/route_validator.dart`.
- Booking station aliases: `lib/utils/booking_station_mapping.dart`.
- Legacy Station N mapping: `lib/utils/station_mapping.dart`.
- Bundled GPS fallback coordinates: `lib/services/station_registry.dart`.

Remote fare table rules:

- Keep all active km fare rows, including blank `place` rows.
- Blank `place` rows must not appear in station lists, but their `km`, `fare`, and `discount` are required for fare computation.
- Ticketable station lists only use active rows where `place` is not empty.
- Ticketable station rows should carry coordinates so live GPS station resolution updates whenever `fare_table_entries` is refreshed.
- Home FROM/TO, passenger count, inspector location, QR validation, and realtime count station lookups read from the hydrated `FareTable` data.
- If the remote table is empty or missing km coverage, the app keeps cached/bundled fallback data.
- If the remote ticketable station set is missing coordinates, GPS resolution falls back to `StationRegistry` as one whole source instead of mixing row-by-row data.

## Tests and Scripts

Flutter tests:

- `test/fare_calculator_test.dart`: verifies alias fare calculation such as Bilaran/Biliran to Pantay.
- `test/screens/booking_confirmation_screen_fare_test.dart`: verifies QR fare is ignored and per-seat booking fares are computed correctly.
- `test/widget_test.dart`: default counter smoke test appears stale for this app and may fail unless updated.

Helper scripts:

- `tools/export_bookings.dart`: Dart Firestore export helper, currently contains placeholder Firebase options.
- `export_firestore.js`: Node Firebase Admin export for `arrivalReports`; expects `serviceAccountKey.json`.
- `tools/check_paren.ps1` and `tools/check_paren.py`: parentheses/check helpers.
- `scripts/render_mermaid_with_id.js`: Mermaid rendering helper.

Common commands:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

For Node export helpers:

```bash
npm install
node export_firestore.js
```

## Future Modification Guide

Change assigned POS device or bus mapping:

- Edit `lib/services/device_config_service.dart` registry.
- Confirm native identifiers with `DeviceIdentifierService` logs.

Change fare table or discounts:

- Update Firestore collection `fare_table_entries` from the dashboard/admin side.
- Ensure blank-place km fare rows remain present for distance calculations.
- Edit `lib/utils/fare_calculator.dart` only for fare logic changes or bundled fallback changes.
- Check `lib/services/fare_table_cache_service.dart` for cache TTL/refresh behavior.
- Extend `lib/utils/booking_station_mapping.dart` only when new booking/mobile station aliases are introduced.
- Update tests in `test/fare_calculator_test.dart` and `test/screens/booking_confirmation_screen_fare_test.dart`.

Change booking QR validation:

- Main service: `lib/services/qr_validation_service.dart`.
- Scanner flow: `lib/screens/qr_scanner_screen.dart`.
- Station mapping: `lib/utils/booking_station_mapping.dart` and `lib/utils/route_validator.dart`.

Change walk-in ticket UI/printing:

- UI and record creation: `lib/screens/home_screen.dart`.
- Receipt formatting: `packages/flutter_senraise_printer_sdk/lib/senraise_printer.dart` or `lib/services/ticket_printer.dart` depending on scope.

Change booking confirmation fare behavior:

- `lib/screens/booking_confirmation_screen.dart`.
- `lib/utils/fare_calculator.dart` for underlying fare engine.
- Keep tests aligned with booking fare rules.

Change drop-off/status sync behavior:

- `lib/screens/bookings_screen.dart` for UI/local state.
- `lib/services/booking_status_orchestrator_service.dart` for Firestore status updates, queueing, and SMS fallback.
- `lib/services/sms_status_sender_service.dart` for SMS payloads.
 
Change SMS/Firebase booking alert behavior:

- `lib/services/sms_booking_alert_service.dart` for parsing, Firestore listeners, local alert store, and reconciliation.
- `lib/screens/home_screen.dart` and `lib/screens/booking_alerts_screen.dart` for alert filtering/display.

Change inspection behavior:

- `lib/screens/inspector_screen.dart` for UI/signatures/local save.
- `lib/models/inspection.dart` for payload shape.
- `lib/services/inspection_sync_service.dart` for Firestore/SMS sync.

Change arrival report:

- `lib/screens/records_screen.dart` for pre-report aggregation/navigation.
- `lib/screens/arrival_report_screen.dart` for report print and trip finalization.
- `lib/services/trip_record_live_service.dart` for final `trip_records` arrival data.
- `lib/services/firebase_dispatch_service.dart` for schedule `arrived` updates.
- `lib/services/arrival_report_sync_service.dart` only for understanding the legacy pending-report path.

Change RTDB occupancy/GPS:

- `lib/services/rtdb_gps_listener_service.dart` for GPS path and station resolution.
- `lib/utils/fare_calculator.dart` for fare-table-backed station names/order/coordinates.
- `lib/services/station_registry.dart` for bundled GPS fallback coordinates only.
- `lib/services/realtime_count_service.dart` for count calculation.
- `lib/services/rtdb_occupancy_publisher_service.dart` for publish cadence/payload/path.

Change native NFC/SMS bridge:

- Android side: `android/app/src/main/kotlin/com/example/untitled/MainActivity.kt`.
- Flutter NFC side: `lib/services/nfc_reader_mode_service.dart`.
- Flutter SMS alert side: `lib/services/sms_booking_alert_service.dart`.
- Flutter SMS send side: `lib/services/sms_status_sender_service.dart`.

Change printer implementation:

- App-level ticket wrapper: `lib/services/ticket_printer.dart`.
- Public printer API/receipt layout: `packages/flutter_senraise_printer_sdk/lib/senraise_printer.dart`.
- Android printer binding: `packages/flutter_senraise_printer_sdk/android/src/main/java/com/senraise/senraise_printer/SenraisePrinterPlugin.java`.

## Known Notes and Watch Points

- `theme.dart` is empty.
- `device_config_screen.dart` is empty.
- `test/widget_test.dart` is still the default counter test and does not match the current app behavior.
- Some comments mention older route names such as `forward`/`reverse`; active route keys are `north_to_south` and `south_to_north`.
- The app has two internet dialog widgets with overlapping purposes: `internet_connectivity_dialog.dart` and `internet_connection_dialog.dart`.
- `RtdbOccupancyPublisherService` comments mention 30 seconds, but the code interval is 10 seconds.
- Android `applicationId` remains `com.example.untitled`; changing it can affect Firebase config, native channels, installed app identity, and build setup.
- Native channel names still use `com.example.untitled/...`; keep Flutter and Android names synchronized if renaming.
- `QRValidationService.validateScheduleMetadata()` and `validateScheduleMatch()` can return invalid results, but `QrScannerScreen` currently treats those checks as warnings during transition.
- `consumed_bookings` is durable anti-replay storage. Avoid clearing it in normal logout/trip reset flows.
- `fare_table_entries` cache is durable reference data. Do not clear it during logout/trip reset flows.
- Remote `fare_table_entries` must include blank-place rows for intermediate km fares; do not filter them out before caching.
- Booking status remote flow only updates status from POS. Cloud Functions own document movement between `bookings_new`, `bookings`, and `bookings_archive`.
- Arrival report printing clears/finalizes the session only after `trip_records` completion and schedule `arrived` updates succeed. Be careful when changing report flow so records are not lost before persistence.
