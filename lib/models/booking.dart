// Shared booking data model and manager
import '../local_storage.dart';
import '../services/app_state.dart';
import '../services/scan_storage.dart';

class Booking {
  final String id;
  final String passengerName;
  final String? passengerUid;
  final String route;
  final String date;
  final String time;
  final int passengers;
  final String fromLocation;
  final String toLocation;
  final String passengerType; // REGULAR, STUDENT, SENIOR, PWD, BAGGAGE
  final double amount;
  late String status; // 'on-board' or 'dropped-off'
  String? dropoffTimestamp;

  Booking({
    required this.id,
    required this.passengerName,
    required this.route,
    required this.date,
    required this.time,
    required this.passengers,
    required this.fromLocation,
    required this.toLocation,
    this.passengerUid,
    this.passengerType = 'REGULAR',
    this.amount = 0.0,
    this.status = 'on-board',
    this.dropoffTimestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'passengerName': passengerName,
      'passengerUid': passengerUid,
      'route': route,
      'date': date,
      'time': time,
      'passengers': passengers,
      'fromLocation': fromLocation,
      'toLocation': toLocation,
      'passengerType': passengerType,
      'amount': amount,
      'status': status,
      'dropoffTimestamp': dropoffTimestamp,
    };
  }

  factory Booking.fromMap(Map<String, dynamic> m) {
    return Booking(
      id: m['id']?.toString() ?? '',
      passengerName: m['passengerName']?.toString() ?? '',
      passengerUid: m['passengerUid']?.toString(),
      route: m['route']?.toString() ?? '',
      date: m['date']?.toString() ?? '',
      time: m['time']?.toString() ?? '',
      passengers: (m['passengers'] is int) ? m['passengers'] as int : int.tryParse(m['passengers']?.toString() ?? '0') ?? 0,
      fromLocation: m['fromLocation']?.toString() ?? '',
      toLocation: m['toLocation']?.toString() ?? '',
      passengerType: m['passengerType']?.toString() ?? 'REGULAR',
      amount: (m['amount'] is num) ? (m['amount'] as num).toDouble() : double.tryParse(m['amount']?.toString() ?? '0') ?? 0.0,
      status: m['status']?.toString() ?? 'on-board',
      dropoffTimestamp: m['dropoffTimestamp']?.toString(),
    );
  }
}

class BookingManager {
  static final BookingManager _instance = BookingManager._internal();

  factory BookingManager() {
    return _instance;
  }

  BookingManager._internal();

  // Start with an empty list; persisted bookings for the current conductor
  // will be loaded via `loadForConductor` and confirmed bookings are
  // persisted when added via `addBooking`.
  final List<Booking> _bookings = [];

  List<Booking> getBookings() => _bookings;

  void addBooking(Booking booking) {
    _bookings.add(booking);
    // Persist bookings for current logged-in conductor (if any)
    try {
      final conductor = AppState.instance.conductor;
      final uid = conductor?['uid']?.toString();
      if (uid != null && uid.isNotEmpty) {
        LocalStorage.saveBookingsForConductor(uid, _bookings.map((b) => b.toMap()).toList());
      }
    } catch (_) {}
  }

  void updateBooking(Booking booking) {
    final index = _bookings.indexWhere((b) => b.id == booking.id);
    if (index != -1) {
      _bookings[index] = booking;
      // Persist updated bookings
      try {
        final conductor = AppState.instance.conductor;
        final uid = conductor?['uid']?.toString();
        if (uid != null && uid.isNotEmpty) {
          LocalStorage.saveBookingsForConductor(uid, _bookings.map((b) => b.toMap()).toList());
        }
      } catch (_) {}
    }
  }



  /// Load persisted bookings for a conductor UID (merge with existing in-memory bookings)
  void loadForConductor(String conductorUid) {
    try {
      final saved = LocalStorage.loadBookingsForConductor(conductorUid);
      if (saved != null && saved.isNotEmpty) {
        // Merge persisted bookings with in-memory bookings
        // Only add persisted bookings that don't already exist in memory
        for (final savedMap in saved) {
          final savedId = savedMap['id']?.toString();
          if (savedId != null && !_bookings.any((b) => b.id == savedId)) {
            _bookings.add(Booking.fromMap(savedMap));
          }
        }
      }
    } catch (_) {}
  }

  /// Clear all in-memory bookings (used on logout)
  void clearBookings() {
    _bookings.clear();
  }

  /// Delete persisted bookings for the currently logged-in conductor
  /// and clear in-memory bookings.
  Future<void> deleteBookingsForCurrentConductor() async {
    try {
      final conductor = AppState.instance.conductor;
      final uid = conductor?['uid']?.toString();
      if (uid != null && uid.isNotEmpty) {
        await LocalStorage.deleteBookingsForConductor(uid);
      }
    } catch (_) {}
    // Also clear scanned tickets saved in LocalStorage and ScanStorage
    try {
      await LocalStorage.clearScannedTickets();
    } catch (_) {}
    try {
      await ScanStorage.clearAll();
    } catch (_) {}
    _bookings.clear();
  }
}
