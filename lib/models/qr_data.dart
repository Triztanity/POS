import 'dart:convert';

/// QR Data Model - Represents the structure of QR code data from the booking application
class QRData {
  final String bookingId;
  final String userId;
  final String transactionId;
  final String origin;
  final String destination;
  final double fareAmount;
  final String assignedBusNumber;
  final String passengerName;
  final int numberOfPassengers;
  final DateTime bookingDate;
  final DateTime expiresAt;

  QRData({
    required this.bookingId,
    required this.userId,
    required this.transactionId,
    required this.origin,
    required this.destination,
    required this.fareAmount,
    required this.assignedBusNumber,
    required this.passengerName,
    required this.numberOfPassengers,
    required this.bookingDate,
    required this.expiresAt,
  });

  /// Parse QR data from raw JSON string
  factory QRData.fromJson(String jsonString) {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString);
      return QRData.fromMap(json);
    } catch (e) {
      throw FormatException('Invalid QR JSON format: $e');
    }
  }

  /// Parse QR data from Map
  factory QRData.fromMap(Map<String, dynamic> map) {
    return QRData(
      bookingId: map['bookingId']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      transactionId: map['transactionId']?.toString() ?? '',
      origin: map['origin']?.toString() ?? '',
      destination: map['destination']?.toString() ?? '',
      // Accept multiple possible field names for fare amount
      fareAmount: _parseFareAmount(map),
      // Accept several possible field names produced by different QR generators
      // Normalize bus number to avoid mismatch due to casing/whitespace/control chars
      assignedBusNumber: _normalizeBusNumber(
        (map['assignedBusNumber'] ?? map['busNumber'] ?? map['busNo'] ?? map['vehicleNo'])?.toString() ?? '',
      ),
      passengerName: map['passengerName']?.toString() ?? '',
      numberOfPassengers: (map['numberOfPassengers'] is int) ? map['numberOfPassengers'] as int : int.tryParse(map['numberOfPassengers']?.toString() ?? '1') ?? 1,
      bookingDate: map['bookingDate'] is DateTime ? map['bookingDate'] as DateTime : DateTime.tryParse(map['bookingDate']?.toString() ?? '') ?? DateTime.now(),
      expiresAt: map['expiresAt'] is DateTime ? map['expiresAt'] as DateTime : DateTime.tryParse(map['expiresAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  static double _parseFareAmount(Map<String, dynamic> map) {
    // Try multiple field names with various formats
    // First, normalize all keys to lowercase for comparison
    final normalizedMap = <String, dynamic>{};
    map.forEach((k, v) {
      final normalizedKey = k.toString().toLowerCase().replaceAll(RegExp(r'[_\s]'), '');
      normalizedMap[normalizedKey] = v;
    });
    
    // Try to find fare value with different key names
    final fareValue = 
      normalizedMap['fareAmount'] ?? 
      normalizedMap['fare'] ?? 
      normalizedMap['amount'] ?? 
      normalizedMap['price'] ?? 
      normalizedMap['fareamount'] ??
      map['fareAmount'] ?? 
      map['fare'] ?? 
      map['amount'] ?? 
      map['price'];
    
    if (fareValue is num) {
      return fareValue.toDouble();
    }
    return double.tryParse(fareValue?.toString() ?? '0') ?? 0.0;
  }

  static String _normalizeBusNumber(String raw) {
    // Trim and uppercase
    var s = raw.trim().toUpperCase();
    // Remove surrounding quotes if present
    if (s.length > 1 && ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'")))) {
      s = s.substring(1, s.length - 1);
    }
    // Remove invisible/control characters
    s = s.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    return s;
  }

  /// Convert to Map for storage
  Map<String, dynamic> toMap() {
    return {
      'bookingId': bookingId,
      'userId': userId,
      'transactionId': transactionId,
      'origin': origin,
      'destination': destination,
      'fareAmount': fareAmount,
      'assignedBusNumber': assignedBusNumber,
      'passengerName': passengerName,
      'numberOfPassengers': numberOfPassengers,
      'bookingDate': bookingDate.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'QRData(bookingId: $bookingId, transactionId: $transactionId, origin: $origin, destination: $destination, fare: $fareAmount, bus: $assignedBusNumber)';
  }
}
