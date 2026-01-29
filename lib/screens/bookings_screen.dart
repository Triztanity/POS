import 'package:flutter/material.dart';
import '../models/booking.dart';
import '../utils/fare_calculator.dart';
import '../services/internet_connection_service.dart';
import '../services/esp32_gateway_service.dart';
import '../widgets/internet_connection_dialog.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  late BookingManager _bookingManager;
  late InternetConnectionService _internetService;
  late ESP32GatewayService _esp32Gateway;

  @override
  void initState() {
    super.initState();
    _bookingManager = BookingManager();
    _internetService = InternetConnectionService();
    _esp32Gateway = ESP32GatewayService();

    // Initialize internet monitoring
    _internetService.initialize();
  }

  @override
  void dispose() {
    _internetService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;

    final bookings = _bookingManager.getBookings();
    // Show all bookings (both booking passengers and regular walk-ins)
    final bookingPassengers =
        bookings.where((b) => b.passengerUid != null).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text(
          'BOOKINGS',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Clear saved bookings',
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete saved bookings'),
                  content: const Text(
                      'This will remove all saved bookings and scanned QR records for the current conductor. Continue?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (confirm == true) {
                await _bookingManager.deleteBookingsForCurrentConductor();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved bookings cleared')));
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenW * 0.03,
            vertical: screenH * 0.01,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Full-width On Board counter
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[50],
                    foregroundColor: Colors.green[800],
                    padding: EdgeInsets.symmetric(vertical: screenH * 0.015),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {},
                  child: Column(
                    children: [
                      const Text('ON BOARD',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('${_countOnBoard(bookingPassengers)}',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Bookings list or empty state
              Expanded(
                child: bookingPassengers.isEmpty
                    ? Center(
                        child: Text(
                          'No bookings available',
                          style:
                              TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        itemCount: bookingPassengers.length,
                        itemBuilder: (context, index) {
                          final booking = bookingPassengers[index];
                          return _buildBookingCard(
                              booking, screenW, screenH, context);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _countOnBoard(List<Booking> bookings) {
    int total = 0;
    for (final b in bookings) {
      if (b.status == 'on-board') total += b.passengers;
    }
    return total;
  }

  Widget _buildBookingCard(
    Booking booking,
    double screenW,
    double screenH,
    BuildContext context,
  ) {
    final Color statusColor = booking.status == 'on-board'
        ? Colors.green.shade700
        : Colors.red.shade600;

    return Container(
      margin: EdgeInsets.symmetric(vertical: screenH * 0.01),
      padding: EdgeInsets.all(screenW * 0.04),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: statusColor, width: 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Passenger name + label
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (booking.passengerUid != null)
                Text('Booking Passenger',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
              if (booking.passengerUid != null &&
                  booking.passengerName.isNotEmpty)
                SizedBox(height: 2),
              if (booking.passengerName.isNotEmpty)
                Text(booking.passengerName,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              if (booking.passengerName.isNotEmpty) const SizedBox(height: 4),
              Text(
                  '${booking.passengerType} • ₱${booking.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500)),
            ],
          ),
          SizedBox(height: 4),

          // Origin
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.place, size: 16, color: Colors.grey[600]),
              SizedBox(width: screenW * 0.02),
              Expanded(
                  child: Text(
                      FareTable.extractPlaceName(
                          FareTable.getFormattedLocation(booking.fromLocation)),
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center)),
            ],
          ),
          SizedBox(height: screenH * 0.006),
          // Destination
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.green[700]),
              SizedBox(width: screenW * 0.02),
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      FareTable.extractPlaceName(
                          FareTable.getFormattedLocation(booking.toLocation)),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800]),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center),
                ),
              ),
            ],
          ),

          SizedBox(height: screenH * 0.008),
          // Date & Time
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
              SizedBox(width: screenW * 0.02),
              Text(booking.date,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              SizedBox(width: screenW * 0.05),
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              SizedBox(width: screenW * 0.02),
              Text(booking.time,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            ],
          ),

          SizedBox(height: screenH * 0.008),
          // Passenger count
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people, size: 16, color: Colors.green[700]),
              SizedBox(width: screenW * 0.02),
              Text('${booking.passengers} passenger(s)',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500)),
            ],
          ),

          SizedBox(height: screenH * 0.01),

          if (booking.status == 'dropped-off' &&
              booking.dropoffTimestamp != null) ...[
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                SizedBox(width: screenW * 0.02),
                Expanded(
                    child: Text('Dropped off at: ${booking.dropoffTimestamp}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        overflow: TextOverflow.ellipsis)),
              ],
            ),
            SizedBox(height: screenH * 0.01),
          ],

          // Action button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: booking.status == 'on-board'
                    ? Colors.green[700]
                    : Colors.grey[300],
                foregroundColor: booking.status == 'on-board'
                    ? Colors.white
                    : Colors.black87,
                padding: EdgeInsets.symmetric(vertical: screenH * 0.014),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: booking.status == 'on-board'
                  ? () => _handleDropoffClick(booking)
                  : null,
              child: Text(booking.status == 'on-board'
                  ? 'MARK DROPPED-OFF'
                  : 'DROPPED-OFF'),
            ),
          ),
        ],
      ),
    );
  }

  /// Send booking dropoff update to ESP32 Gateway
  void _handleDropoffClick(Booking booking) async {
    try {
      debugPrint('[Bookings] Drop-off button clicked for: ${booking.id}');

      // Check if ESP32 gateway is reachable
      final isConnected = await _internetService.isConnectedToGateway();

      if (!isConnected) {
        debugPrint(
            '[Bookings] No connection to ESP32 gateway. Showing dialog...');
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => InternetConnectionDialog(
              onConnected: () {
                debugPrint(
                    '[Bookings] Gateway connected. Proceeding with drop-off...');
                _proceedWithDropoff(booking);
              },
            ),
          );
        }
        return;
      }

      // Gateway is connected, proceed with drop-off
      _proceedWithDropoff(booking);
    } catch (e) {
      debugPrint('[Bookings] Error in drop-off: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Proceed with marking booking as dropped-off
  void _proceedWithDropoff(Booking booking) async {
    try {
      // Show confirmation dialog
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Drop-off'),
          content: Text('Mark ${booking.passengerName} as dropped-off?\n\n'
              'Booking ID: ${booking.id}\n'
              'Time: ${DateTime.now().toString().split('.')[0]}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Update local state
      booking.status = 'dropped-off';
      booking.dropoffTimestamp = DateTime.now().toString();
      _bookingManager.updateBooking(booking);

      // Send to ESP32 Gateway
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending to ESP32...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final result = await _esp32Gateway.sendDropoffToESP32(
        bookingId: booking.id,
        status: 'dropped-off',
        dropoffTimestamp: DateTime.now().toIso8601String(),
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '✅ ${result['message'] ?? 'Successfully sent to ESP32'}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result['message'] ?? 'Failed to send'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        setState(() {});
      }
    } catch (e) {
      debugPrint('[Bookings] Error in proceed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
