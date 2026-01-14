class DispatchDetails {
  final String tripId;
  final String? driverName;
  final String? conductorName;
  final String dispatchTime;
  final String status; // 'dispatched', 'pre-departure', etc.

  DispatchDetails({
    required this.tripId,
    this.driverName,
    this.conductorName,
    required this.dispatchTime,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'tripId': tripId,
      'driverName': driverName,
      'conductorName': conductorName,
      'dispatchTime': dispatchTime,
      'status': status,
    };
  }

  factory DispatchDetails.fromMap(Map<String, dynamic> map) {
    return DispatchDetails(
      tripId: map['tripId'] ?? '',
      driverName: map['driverName'],
      conductorName: map['conductorName'],
      dispatchTime: map['dispatchTime'] ?? '',
      status: map['status'] ?? 'dispatched',
    );
  }
}
