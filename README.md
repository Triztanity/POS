# 🌟 StarExpress POS (Automated Fare Collection System)

Welcome to the **StarExpress POS** repository! 🚌💨 

This is a high-performance Flutter application built specifically for modern bus transit systems. It’s designed to run on Android POS hardware (like **Senraise** devices) that come with built-in thermal printers and NFC readers.

If you're looking for a robust, offline-first solution to handle bus dispatching, ticketing, and real-time inspections—you've come to the right place!

---

## ✨ What Does It Do?

The StarExpress POS App is the trusty sidekick for bus conductors and drivers. It handles the entire lifecycle of a bus trip, from the moment the engine starts to the final arrival report. 

And the best part? It doesn't freak out when the bus drives through a dead zone. It's built with a strict **Offline-First** philosophy!

### 🎯 Key Features:
* **📶 Offline-First Magic:** Issue tickets, validate QR bookings, and record inspections with absolutely zero internet connection. The app saves everything locally and syncs when you're back online.
* **🖨️ Hardware Harmony:** Talks directly to built-in thermal printers, NFC readers (ISO/IEC 14443), and hardware QR scanners. No clunky Bluetooth pairing required.
* **☁️ Cloud & Local Sync:** Seamlessly syncs to **Firebase Firestore** when the internet is back up. It also chats with a local on-board **Raspberry Pi Gateway** for instant local event processing.
* **💳 Tap-to-Go Workflows:** Conductors, drivers, and inspectors just tap their physical NFC IDs to log in, assign buses, or trigger surprise inspections.

---

## 🛠️ How It Works (Under the Hood)

### 1. The Data Vault (`local_storage.dart`)
We use **Hive** (a super-fast NoSQL database for Flutter) to make sure no ticket is left behind, even if the device dies. 
* **Outboxes:** Queues up trips, arrival reports, and gateway events.
* **State Boxes:** Remembers who is logged in and what bus they are driving.
* **Cache Boxes:** Stores successfully scanned QR tickets to prevent double-scanning.

### 2. Staying Connected
* **Cloud Sync:** Background services quietly push your queues to Firebase whenever they catch a signal.
* **Pi Gateway:** Pings local events to an on-board Raspberry Pi (default IP: `192.168.4.2`).
* **SMS Bridge:** Believe it or not, it can receive passenger bookings via silent SMS! Because sometimes, texting is the only thing that gets through the mountains. 🏔️📱

### 3. Hardware Services
* **`TicketPrinter`:** Formats and prints gorgeous 58mm thermal tickets using the `flutter_senraise_printer_sdk`.
* **NFC Transformers:** Background services that listen for ID cards to automate logins, assign buses, and let inspectors do their job instantly.

---

## 🏗️ The Validation Pipeline

How does the app know a passenger's QR code is valid? We use a smart **Index-Based Validation** system:

1. **Station Sequencing:** We have a master list of 54 stations in order (e.g., from Nasugbu to Batangas).
2. **Direction Check:** It compares the passenger's origin and destination against the bus's current travel direction. If the bus is heading North, you can't scan a ticket going South!
3. **Fuzzy Matching:** "Lian" and "Lian Shed"? Handled. The app cleans up typos and naming variations.
4. **Duplicate Prevention:** Checks the local database in milliseconds to stop screenshot-sharers in their tracks.

---

## 🚀 Getting Started

Want to poke around the code? Here's what you need:

### What You'll Need
* **Hardware:** An Android POS device (Android 5.0+, preferably Senraise or Sunmi) with NFC and a 58mm thermal printer. 
* **Software:** Flutter SDK installed and ready to go.

### Spin It Up
1. **Get Dependencies:** 
   ```bash
   flutter pub get
   ```
2. **Firebase Magic:** Drop your `google-services.json` file into the `android/app/` folder.
3. **Build the APK:**
   ```bash
   flutter build apk --release
   ```

---

## 🗺️ Project Navigation Map

* 🧠 **`lib/services/`**: The brains of the operation. Hardware control, syncing, app state, and route validation live here.
* 📱 **`lib/screens/`**: What the user sees. Includes the `home_screen.dart` (dashboard), `qr_scanner_screen.dart` (the fast scanner), and `inspector_screen.dart` (the auditor's view).
* 🧱 **`lib/models/`**: The blueprints for our data (bookings, trips, inspections).

---

*Built with ❤️ for better, smoother, and safer daily commutes.*