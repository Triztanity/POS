/// Scanned Ticket Model - Represents a completed transaction after QR scanning
class ScannedTicket {
  final String id;
  final String bookingId;
  final String transactionId;
  final String passengerName;
  final int numberOfPassengers;
  final String origin;
  final String destination;
  final String busNumber;
  final String routeDirection; // 'north_to_south' or 'south_to_north'
  final String passengerType; // REGULAR, STUDENT, SENIOR, PWD
  final double originalFare;
  final double discountAmount;
  final double finalFare;
  final DateTime scannedAt;
  final String conductorName;
  final String driverName;
  bool printed; // true if ticket was printed

  ScannedTicket({
    required this.id,
    required this.bookingId,
    required this.transactionId,
    required this.passengerName,
    required this.numberOfPassengers,
    required this.origin,
    required this.destination,
    required this.busNumber,
    required this.routeDirection,
    required this.passengerType,
    required this.originalFare,
    required this.discountAmount,
    required this.finalFare,
    required this.scannedAt,
    required this.conductorName,
    required this.driverName,
    this.printed = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookingId': bookingId,
      'transactionId': transactionId,
      'passengerName': passengerName,
      'numberOfPassengers': numberOfPassengers,
      'origin': origin,
      'destination': destination,
      'busNumber': busNumber,
      'routeDirection': routeDirection,
      'passengerType': passengerType,
      'originalFare': originalFare,
      'discountAmount': discountAmount,
      'finalFare': finalFare,
      'scannedAt': scannedAt.toIso8601String(),
      'conductorName': conductorName,
      'driverName': driverName,
      'printed': printed,
    };
  }

  factory ScannedTicket.fromMap(Map<String, dynamic> map) {
    return ScannedTicket(
      id: map['id']?.toString() ?? '',
      bookingId: map['bookingId']?.toString() ?? '',
      transactionId: map['transactionId']?.toString() ?? '',
      passengerName: map['passengerName']?.toString() ?? '',
      numberOfPassengers: (map['numberOfPassengers'] is int) ? map['numberOfPassengers'] as int : int.tryParse(map['numberOfPassengers']?.toString() ?? '1') ?? 1,
      origin: map['origin']?.toString() ?? '',
      destination: map['destination']?.toString() ?? '',
      busNumber: map['busNumber']?.toString() ?? '',
      routeDirection: map['routeDirection']?.toString() ?? '',
      passengerType: map['passengerType']?.toString() ?? 'REGULAR',
      originalFare: (map['originalFare'] is num) ? (map['originalFare'] as num).toDouble() : double.tryParse(map['originalFare']?.toString() ?? '0') ?? 0.0,
      discountAmount: (map['discountAmount'] is num) ? (map['discountAmount'] as num).toDouble() : double.tryParse(map['discountAmount']?.toString() ?? '0') ?? 0.0,
      finalFare: (map['finalFare'] is num) ? (map['finalFare'] as num).toDouble() : double.tryParse(map['finalFare']?.toString() ?? '0') ?? 0.0,
      scannedAt: map['scannedAt'] is DateTime ? map['scannedAt'] as DateTime : DateTime.tryParse(map['scannedAt']?.toString() ?? '') ?? DateTime.now(),
      conductorName: map['conductorName']?.toString() ?? '',
      driverName: map['driverName']?.toString() ?? '',
      printed: (map['printed'] is bool) ? map['printed'] as bool : false,
    );
  }
}
