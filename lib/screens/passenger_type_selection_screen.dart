import 'package:flutter/material.dart';
import '../models/qr_data.dart';
import '../utils/fare_calculator.dart';

/// Passenger Type Selection Screen
/// After QR validation, conductor selects passenger type and confirms fare
class PassengerTypeSelectionScreen extends StatefulWidget {
  final QRData qrData;
  final String routeDirection;
  final String conductorName;
  final String driverName;

  const PassengerTypeSelectionScreen({
    super.key,
    required this.qrData,
    required this.routeDirection,
    required this.conductorName,
    required this.driverName,
  });

  @override
  State<PassengerTypeSelectionScreen> createState() => _PassengerTypeSelectionScreenState();
}

class _PassengerTypeSelectionScreenState extends State<PassengerTypeSelectionScreen> {
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
    // Calculate actual fare based on origin, destination, and passenger type
    final calculatedFare = FareCalculator.calculateFare(
      origin: widget.qrData.origin.replaceAll(RegExp(r'^\d+\.\s*'), '').trim().toUpperCase(),
      destination: widget.qrData.destination.replaceAll(RegExp(r'^\d+\.\s*'), '').trim().toUpperCase(),
      passengerType: selectedPassengerType,
    );
    
    finalFare = calculatedFare.toDouble();
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
          'SELECT PASSENGER TYPE',
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
                  padding: EdgeInsets.all(screenW * 0.04),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green[700]),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow('Passenger:', widget.qrData.passengerName),
                      _buildInfoRow('User ID:', widget.qrData.userId),
                      _buildInfoRow('Booking ID:', widget.qrData.bookingId),
                      _buildInfoRow('From:', widget.qrData.origin),
                      _buildInfoRow('To:', widget.qrData.destination),
                      _buildInfoRow('Passengers:', '${widget.qrData.numberOfPassengers}'),
                    ],
                  ),
                ),

                SizedBox(height: screenH * 0.03),

                // Passenger Type Selection
                Text(
                  'Passenger Type',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: screenW * 0.03),
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

                SizedBox(height: screenH * 0.03),

                // Fare Breakdown
                Container(
                  padding: EdgeInsets.all(screenW * 0.04),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Original Fare:', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                          Text(
                            '₱${originalFare.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (discountAmount > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Discount/Change:', style: TextStyle(fontSize: 13, color: Colors.red[600])),
                            Text(
                              '-₱${discountAmount.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(color: Colors.blue[300]),
                        const SizedBox(height: 8),
                      ] else if (discountAmount < 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Additional Charge:', style: TextStyle(fontSize: 13, color: Colors.orange[600])),
                            Text(
                              '+₱${(-discountAmount).toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(color: Colors.blue[300]),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Final Fare:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                          Text(
                            '₱${finalFare.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: screenH * 0.05),

                // Confirm Button
                SizedBox(
                  width: double.infinity,
                  height: screenH * 0.065,
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: screenH * 0.02),

                // Cancel Button
                SizedBox(
                  width: double.infinity,
                  height: screenH * 0.055,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'CANCEL',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[600],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }
}
