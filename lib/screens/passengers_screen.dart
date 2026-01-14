import 'package:flutter/material.dart';
import '../models/booking.dart';
import '../utils/fare_calculator.dart';
import '../services/app_state.dart';
import '../local_storage.dart';

class PassengersScreen extends StatefulWidget {
  final String routeDirection; // 'forward' or 'reverse'
  const PassengersScreen({super.key, required this.routeDirection});

  @override
  State<PassengersScreen> createState() => _PassengersScreenState();
}

class _PassengersScreenState extends State<PassengersScreen> with WidgetsBindingObserver {
  late List<String> stops;
  String? currentLocation;
  late BookingManager _bookingManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bookingManager = BookingManager();
    
    // Load persisted bookings for the current conductor
    _loadBookings();
    
    // Get unique places from FareTable with km values: ["0|NASUGBU", "2|LIAN", ...]
    final forwardStops = FareTable.placeNamesWithKm;
    
    // For north_to_south route: Nasugbu → Batangas (forward direction)
    // For south_to_north route: Batangas → Nasugbu (reverse direction)
    stops = widget.routeDirection == 'north_to_south'
        ? List.from(forwardStops)
        : List.from(forwardStops.reversed);
    currentLocation = 'OVERVIEW';
    
    // Schedule a refresh after frame to ensure data is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBookings();
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh bookings when screen is resumed
      setState(() {
        _loadBookings();
      });
    }
  }

  void _loadBookings() {
    try {
      final conductor = AppState.instance.conductor;
      final uid = conductor?['uid']?.toString();
      if (uid != null && uid.isNotEmpty) {
        _bookingManager.loadForConductor(uid);
      }
    } catch (_) {
      // If loading fails, continue with in-memory bookings
    }
  }

  /// Get combined bookings (from bookingManager + walkins from storage)
  List<Booking> _getCombinedBookings() {
    var bookings = _bookingManager.getBookings().toList();
    // Include only walkins for the current trip so new trips start fresh
    final walkins = LocalStorage.loadWalkinsForTrip(LocalStorage.getCurrentTripId()).toList();

    for (final walkin in walkins) {
      final booking = Booking(
        id: walkin['id'] ?? '',
        passengerName: walkin['passengerName'] ?? 'Walk-in',
        route: walkin['route'] ?? '',
        date: walkin['date'] ?? '',
        time: walkin['time'] ?? '',
        passengers: walkin['passengers'] ?? 1,
        fromLocation: walkin['fromLocation'] ?? '',
        toLocation: walkin['toLocation'] ?? '',
        passengerType: walkin['passengerType'] ?? 'REGULAR',
        amount: walkin['amount'] ?? 0.0,
        status: 'on-board',
        passengerUid: null,
      );
      // Avoid duplicating if booking with same id already exists
      if (!bookings.any((b) => b.id == booking.id)) bookings.add(booking);
    }
    return bookings;
  }

  int getPassengersOnBoard() {
    final bookings = _getCombinedBookings();
    if (currentLocation == 'OVERVIEW') return 0; // No on-board for overview
    final currentIdx = stops.indexOf(currentLocation!);
    if (currentIdx == -1) return 0;
    int count = 0;
    for (final booking in bookings) {
      // Only count if booking is on-board (not dropped-off)
      if (booking.status != 'on-board') continue;
      
      // Find index of booking location in stops list using token-based matching
      // This handles cases where booking has descriptive info (e.g., "Mahayahay 7-11" vs stop "MAHAYAHAY")
      int fromIdx = -1, toIdx = -1;
      final originNormalized = _normalizeLocationName(booking.fromLocation);
      final destNormalized = _normalizeLocationName(booking.toLocation);
      final originWords = originNormalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final destWords = destNormalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      
      for (int i = 0; i < stops.length; i++) {
        final stopNormalized = _normalizeLocationName(stops[i]);
        final stopWords = stopNormalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        // Token-based match: all stop words must be in the booking location words
        if (stopWords.every((sw) => originWords.contains(sw))) fromIdx = i;
        if (stopWords.every((sw) => destWords.contains(sw))) toIdx = i;
      }

      // If either index not found, we skip this booking since bookings now use normal place names
      
      // Count only if: bus has reached/passed boarding point AND hasn't reached drop-off yet
      if (fromIdx != -1 && toIdx != -1 && fromIdx <= currentIdx && currentIdx < toIdx) {
        count += booking.passengers;
      }
    }
    return count;
  }

  /// Get a map of destinations and their passenger counts
  Map<String, int> getPassengersByDestination() {
    final bookings = _getCombinedBookings();
    // For OVERVIEW, show all destinations; otherwise filter by current location
    final currentIdx = currentLocation == 'OVERVIEW' ? -1 : stops.indexOf(currentLocation!);
    if (currentIdx == -2) return {}; // Invalid location (should not happen)
    
    final destinationMap = <String, int>{};
    for (final booking in bookings) {
      
      // Find index of booking destination in stops list using normalized location names
      int toIdx = -1;
      final destNormalized = _normalizeLocationName(booking.toLocation);
      for (int i = 0; i < stops.length; i++) {
        final stopNormalized = _normalizeLocationName(stops[i]);
        if (stopNormalized == destNormalized) {
          toIdx = i;
          break;
        }
      }
      
      // For OVERVIEW, show all destinations; otherwise filter by current location
      if (toIdx != -1 && (currentIdx == -1 || toIdx > currentIdx)) {
        // Use formatted location string with km for display
        final formattedLocation = FareTable.getFormattedLocation(booking.toLocation);
        destinationMap[formattedLocation] =
            (destinationMap[formattedLocation] ?? 0) + booking.passengers;
      }
    }
    return destinationMap;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;
    
    // Reload bookings on every build to ensure fresh data (especially on return from QR flow)
    _loadBookings();
    
    final passengersOnBoard = getPassengersOnBoard();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text(
          'PASSENGERS',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenW * 0.03, vertical: screenH * 0.015),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compact header row with location selector and small counters
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Current Location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 36,
                          child: DropdownButton<String>(
                            value: currentLocation,
                            isExpanded: true,
                            underline: Container(color: Colors.grey[300], height: 1),
                            items: _buildLocationDropdownItems(),
                            onChanged: (value) {
                              setState(() {
                                currentLocation = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Small summary box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      border: Border.all(color: Colors.green, width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text('On Board', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('$passengersOnBoard', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Destinations table (compact)
              const Text('Scheduled Drop-offs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(child: _buildDropoffsTableCompact()),

              // Bottom revenue bar
              const SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Trip Revenue', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('₱${_formatRevenue(_getTripRevenue())}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build dropdown items for current location with OVERVIEW at top and filtered stops
  List<DropdownMenuItem<String>> _buildLocationDropdownItems() {
    // Always show OVERVIEW followed by all route stops in travel order.
    final items = <DropdownMenuItem<String>>[];
    items.add(
      const DropdownMenuItem(
        value: 'OVERVIEW',
        child: Text('OVERVIEW', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    );

    for (final stop in stops) {
      items.add(
        DropdownMenuItem(
          value: stop,
          child: Text(stop, style: const TextStyle(fontSize: 13)),
        ),
      );
    }

    return items;
  }

  /// Helper to normalize location names for matching
  String _normalizeLocationName(String location) {
    return FareTable.normalizePlaceName(location);
  }

  Widget _buildDropoffsTableCompact() {
    // Build counts per stop but preserve route order and include only stops after current location
    final bookings = _getCombinedBookings();
    final currentIdx = currentLocation == 'OVERVIEW' ? -1 : stops.indexOf(currentLocation!);

    // Prepare ordered list of candidate stops according to the route order
    final orderedStops = currentIdx == -1 ? List<String>.from(stops) : stops.sublist(currentIdx + 1);

    // Initialize counts map keyed by stop (formatted display name)
    final countsByStop = <String, Map<String, int>>{};
    for (final stop in orderedStops) {
      countsByStop[stop] = {'walkin': 0, 'booking': 0};
    }

    for (final b in bookings) {
      // Determine the stop index for booking destination using token-based matching
      int toIdx = -1;
      final destNormalized = _normalizeLocationName(b.toLocation);
      final destWords = destNormalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

      for (int i = 0; i < stops.length; i++) {
        final stopNormalized = _normalizeLocationName(stops[i]);
        final stopWords = stopNormalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (stopWords.every((sw) => destWords.contains(sw))) {
          toIdx = i;
          break;
        }
      }

      if (toIdx == -1) continue; // destination not on route

      // Exclude destinations that are before or equal to current location
      if (currentIdx != -1 && toIdx <= currentIdx) continue;

      final formattedTo = stops[toIdx];
      final map = countsByStop[formattedTo];
      if (map == null) continue; // not in the forward-ordered stops

      if (b.passengerUid == null) {
        map['walkin'] = (map['walkin'] ?? 0) + b.passengers;
      } else {
        if (b.status == 'on-board') {
          map['booking'] = (map['booking'] ?? 0) + b.passengers;
        }
      }
    }

    // Filter out stops with zero total passengers
    final entries = countsByStop.entries.where((e) => ((e.value['walkin'] ?? 0) + (e.value['booking'] ?? 0)) > 0).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: const [
                Expanded(child: Text('Destination', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                SizedBox(width: 12),
                SizedBox(width: 80, child: Text('Walk-in', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                SizedBox(width: 12),
                SizedBox(width: 80, child: Text('Booking', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.grey),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: entries.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final location = entry.key; // formatted 'km|PLACE'
                final walkinCount = entry.value['walkin'] ?? 0;
                final bookingCount = entry.value['booking'] ?? 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(location, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 80,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
                          child: Text('$walkinCount', style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 80,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(6)),
                          child: Text('$bookingCount', style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _getTripRevenue() {
    final bookings = _getCombinedBookings();
    double total = 0.0;
    for (final b in bookings) {
      // Only count on-board bookings in revenue
      if (b.status == 'on-board') {
        total += b.amount * b.passengers;
      }
    }
    return total;
  }

  String _formatRevenue(double value) {
    return value.toStringAsFixed(2);
  }
}
