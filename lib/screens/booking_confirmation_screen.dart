import 'package:flutter/material.dart';
import '../models/qr_data.dart';
import '../utils/fare_calculator.dart';

/// Booking Confirmation Screen
/// After QR validation, conductor reviews booking and confirms fare for printing
class BookingConfirmationScreen extends StatefulWidget {
  final QRData qrData;
  final String routeDirection;
  final String conductorName;
  final String driverName;

  const BookingConfirmationScreen({
    super.key,
    required this.qrData,
    required this.routeDirection,
    required this.conductorName,
    required this.driverName,
  });

  @override
  State<BookingConfirmationScreen> createState() => _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  late String selectedPassengerType;
  late double originalFare;
  late double discountAmount;
  late double finalFare;

  final List<String> passengerTypes = ['REGULAR', 'STUDENT', 'SENIOR', 'PWD', 'OTHER'];

  @override
  void initState() {
    super.initState();
    selectedPassengerType = 'REGULAR';
    originalFare = widget.qrData.fareAmount;
    _updateFare();
  }

  void _updateFare() {
    // Use the QR code's fare as the reference (original fare) when possible.
    // This finds the fare table entry that matches the QR `fare` and derives
    // the discounted fare for non-regular passenger types. Falls back to
    // distance-based calculation when no matching fare entry is found.
    final qrFare = widget.qrData.fareAmount;
    // Attempt to find a fare table row with the same (rounded) fare.
    FareEntry? fareEntry;
    try {
      fareEntry = FareTable.getEntryByFare(qrFare);
    } catch (e) {
      // In some hot-reload/runtime states the static method may not be available;
      // fall back cleanly to distance-based computation below.
      fareEntry = null;
    }

    if (fareEntry != null) {
      originalFare = qrFare;
      if (selectedPassengerType.toUpperCase() == 'REGULAR') {
        finalFare = originalFare;
      } else {
        finalFare = fareEntry.discount.toDouble();
      }
      discountAmount = originalFare - finalFare;
      return;
    }

    // Fallback: calculate fare via station indices when we can't map by fare value
    final calculatedFare = BookingFareCalculator.calculateFare(
      origin: widget.qrData.origin.replaceAll(RegExp(r'^\d+\.\s*'), '').trim().toUpperCase(),
      destination: widget.qrData.destination.replaceAll(RegExp(r'^\d+\.\s*'), '').trim().toUpperCase(),
      passengerType: selectedPassengerType,
    );
    finalFare = calculatedFare.toDouble();
    // Keep originalFare as the QR fare if present, otherwise use calculated
    if (widget.qrData.fareAmount > 0) {
      originalFare = widget.qrData.fareAmount;
    } else {
      originalFare = finalFare;
    }
    discountAmount = originalFare - finalFare;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text(
          'BOOKING CONFIRMATION',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenW * 0.05,
            vertical: screenH * 0.02,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // QR Info Display
                Container(
                  padding: EdgeInsets.all(screenW * 0.03),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[700]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking Information',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[700]),
                      ),
                      const SizedBox(height: 6),
                      _buildInfoRow('User ID:', widget.qrData.userId),
                      _buildInfoRow('Booking ID:', widget.qrData.bookingId),
                      _buildInfoRow('From:', widget.qrData.origin),
                      _buildInfoRow('To:', widget.qrData.destination),
                      _buildInfoRow('Passengers:', '${widget.qrData.numberOfPassengers}'),
                    ],
                  ),
                ),
                SizedBox(height: screenH * 0.02),

                // Passenger Type Selection
                Text(
                  'Passenger Type',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: screenW * 0.02),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black54),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    underline: const SizedBox(),
                    value: selectedPassengerType,
                    items: passengerTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedPassengerType = value;
                          _updateFare();
                        });
                      }
                    },
                  ),
                ),

                SizedBox(height: screenH * 0.02),

                // Fare Breakdown
                Container(
                  padding: EdgeInsets.all(screenW * 0.03),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fare Breakdown',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Original Fare:', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                          Text(
                            '₱${originalFare.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (discountAmount > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Discount/Change:', style: TextStyle(fontSize: 12, color: Colors.red[600])),
                            Text(
                              '-₱${discountAmount.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Divider(color: Colors.blue[300]),
                        const SizedBox(height: 6),
                      ] else if (discountAmount < 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Additional Charge:', style: TextStyle(fontSize: 12, color: Colors.orange[600])),
                            Text(
                              '+₱${(-discountAmount).toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Divider(color: Colors.blue[300]),
                        const SizedBox(height: 6),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Final Fare:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                          Text(
                            '₱${finalFare.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: screenH * 0.04),

                // Confirm Button
                SizedBox(
                  width: double.infinity,
                  height: screenH * 0.055,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, {
                        'passengerType': selectedPassengerType,
                        'originalFare': originalFare,
                        'discountAmount': discountAmount,
                        'finalFare': finalFare,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'CONFIRM & PRINT TICKET',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: screenH * 0.015),

                // Cancel Button
                SizedBox(
                  width: double.infinity,
                  height: screenH * 0.05,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'CANCEL',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[600],
                      ),
                    ),
                  ),
                ),

                SizedBox(height: screenH * 0.015),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
