import 'package:flutter/material.dart';
import '../models/qr_data.dart';
import '../services/booking_status_orchestrator_service.dart';
import '../utils/fare_calculator.dart';
import '../local_storage.dart';

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
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  String? selectedPassengerType;
  late double originalFare;
  double discountAmount = 0;
  double finalFare = 0;

  final List<String> passengerTypes = [
    'REGULAR',
    'STUDENT',
    'SENIOR',
    'PWD',
    'OTHER'
  ];

  @override
  void initState() {
    super.initState();
    originalFare = widget.qrData.fareAmount;
    finalFare = originalFare;
  }

  void _updateFare() {
    if (selectedPassengerType == null) return;
    final normalizedPassengerType = selectedPassengerType!.trim().toUpperCase();
    final passengerCount = widget.qrData.numberOfPassengers > 0
        ? widget.qrData.numberOfPassengers
        : 1;
    final qrFareRaw = widget.qrData.fareAmount;
    final normalizedOrigin = widget.qrData.origin
        .replaceAll(RegExp(r'^\d+\.\s*'), '')
        .trim()
        .toUpperCase();
    final normalizedDestination = widget.qrData.destination
        .replaceAll(RegExp(r'^\d+\.\s*'), '')
        .trim()
        .toUpperCase();

    // Always compute a regular baseline first so selecting REGULAR never applies discounts.
    final regularFare = BookingFareCalculator.calculateFare(
      origin: normalizedOrigin,
      destination: normalizedDestination,
      passengerType: 'REGULAR',
      quantity: passengerCount,
    ).toDouble();

    final selectedFare = BookingFareCalculator.calculateFare(
      origin: normalizedOrigin,
      destination: normalizedDestination,
      passengerType: normalizedPassengerType,
      quantity: passengerCount,
    ).toDouble();

    // Keep QR fare as the booking's original amount whenever available.
    // This prevents the displayed "Original Fare" from changing (e.g., 64 -> 50)
    // when passenger type is selected.
    final baselineRegularFare = qrFareRaw > 0 ? qrFareRaw : regularFare;

    // Resolve a fare table row from the baseline's per-seat value when possible.
    final perSeatBaseline = passengerCount > 0
        ? (baselineRegularFare / passengerCount)
        : baselineRegularFare;
    final baselineEntry = FareTable.getEntryByFare(perSeatBaseline);

    // Regular must never be discounted.
    if (normalizedPassengerType == 'REGULAR') {
      originalFare = baselineRegularFare > 0 ? baselineRegularFare : qrFareRaw;
      finalFare = originalFare;
      discountAmount = 0;
      return;
    }

    if (baselineRegularFare <= 0) {
      originalFare = 0;
      finalFare = 0;
      discountAmount = 0;
      return;
    }

    // For discounted types, compute from the baseline amount and never exceed regular.
    double computedDiscountedFare = 0;
    if (baselineEntry != null) {
      computedDiscountedFare =
          baselineEntry.discount.toDouble() * passengerCount;
    } else if (selectedFare > 0 && regularFare > 0) {
      final discountRatio = (selectedFare / regularFare).clamp(0.0, 1.0);
      computedDiscountedFare = baselineRegularFare * discountRatio;
    } else {
      // Conservative fallback: 20% discount for non-regular when no fare row is found.
      computedDiscountedFare = baselineRegularFare * 0.80;
    }

    originalFare = baselineRegularFare;
    if (computedDiscountedFare > 0) {
      finalFare = computedDiscountedFare < originalFare
          ? computedDiscountedFare
          : originalFare;
    } else {
      finalFare = originalFare;
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
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700]),
                      ),
                      const SizedBox(height: 6),
                      _buildInfoRow('User ID:', widget.qrData.userId),
                      _buildInfoRow('Booking ID:', widget.qrData.bookingId),
                      _buildInfoRow('From:', widget.qrData.origin),
                      _buildInfoRow('To:', widget.qrData.destination),
                      _buildInfoRow(
                          'Passengers:', '${widget.qrData.numberOfPassengers}'),
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
                    border: Border.all(
                      color: selectedPassengerType == null
                          ? Colors.red
                          : Colors.black54,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    underline: const SizedBox(),
                    value: selectedPassengerType,
                    hint: const Text('Select Type',
                        style: TextStyle(color: Colors.grey)),
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
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700]),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Original Fare:',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[700])),
                          Text(
                            '₱${originalFare.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (discountAmount > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Discount/Change:',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.red[600])),
                            Text(
                              '-₱${discountAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red[600]),
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
                            Text('Additional Charge:',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.orange[600])),
                            Text(
                              '+₱${(-discountAmount).toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange[600]),
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
                          Text('Final Fare:',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
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
                    onPressed: selectedPassengerType == null
                        ? null
                        : () async {
                            // Queue on-board status for Raspberry Pi gateway
                            final bookingId = widget.qrData.bookingId;
                            try {
                              final result =
                                  await BookingStatusOrchestratorService()
                                      .updateStatus(
                                bookingId: bookingId,
                                tripId: LocalStorage.getCurrentTripId(),
                                status: 'on-board',
                                passengerUid: widget.qrData.userId,
                              );
                              if (result['success'] == true) {
                                // Optionally show success dialog
                              } else {
                                // Optionally show error dialog
                              }
                            } catch (e) {
                              // Optionally show error dialog
                            }
                            Navigator.pop(context, {
                              'passengerType': selectedPassengerType!,
                              'originalFare': originalFare,
                              'discountAmount': discountAmount,
                              'finalFare': finalFare,
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
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
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
