/// Inspection model for auditing passenger counts
class Inspection {
  final String id;
  final String timestamp; // ISO 8601 format
  final String busNumber;
  final String tripSession;
  final String? inspectorUid;
  final String conductorUid;
  final String driverUid;
  final int manualPassengerCount;
  final int systemPassengerCount;
  final bool isCleared; // true if counts match
  final String? discrepancyResolved; // 'Resolved', 'Not Resolved', or null if cleared
  final String? resolutionReason; // Reason from dropdown (if resolved)
  final String? customExplanation; // Custom text if 'Other' selected
  final String? comments; // Inspector comments
  final bool isSynced; // true if successfully synced to server
  final String? syncError; // error message if sync failed

  Inspection({
    required this.id,
    required this.timestamp,
    required this.busNumber,
    required this.tripSession,
    this.inspectorUid,
    required this.conductorUid,
    required this.driverUid,
    required this.manualPassengerCount,
    required this.systemPassengerCount,
    required this.isCleared,
    this.discrepancyResolved,
    this.resolutionReason,
    this.customExplanation,
    this.comments,
    this.isSynced = false,
    this.syncError,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'busNumber': busNumber,
      'tripSession': tripSession,
      'inspectorUid': inspectorUid,
      'conductorUid': conductorUid,
      'driverUid': driverUid,
      'manualPassengerCount': manualPassengerCount,
      'systemPassengerCount': systemPassengerCount,
      'isCleared': isCleared,
      'discrepancyResolved': discrepancyResolved,
      'resolutionReason': resolutionReason,
      'customExplanation': customExplanation,
      'comments': comments,
      'isSynced': isSynced,
      'syncError': syncError,
    };
  }

  factory Inspection.fromMap(Map<String, dynamic> m) {
    return Inspection(
      id: m['id']?.toString() ?? '',
      timestamp: m['timestamp']?.toString() ?? '',
      busNumber: m['busNumber']?.toString() ?? '',
      tripSession: m['tripSession']?.toString() ?? '',
      inspectorUid: m['inspectorUid']?.toString(),
      conductorUid: m['conductorUid']?.toString() ?? '',
      driverUid: m['driverUid']?.toString() ?? '',
      manualPassengerCount: (m['manualPassengerCount'] is int) ? m['manualPassengerCount'] : int.tryParse(m['manualPassengerCount']?.toString() ?? '0') ?? 0,
      systemPassengerCount: (m['systemPassengerCount'] is int) ? m['systemPassengerCount'] : int.tryParse(m['systemPassengerCount']?.toString() ?? '0') ?? 0,
      isCleared: (m['isCleared'] is bool) ? m['isCleared'] : (m['isCleared']?.toString() == 'true'),
      discrepancyResolved: m['discrepancyResolved']?.toString(),
      resolutionReason: m['resolutionReason']?.toString(),
      customExplanation: m['customExplanation']?.toString(),
      comments: m['comments']?.toString(),
      isSynced: (m['isSynced'] is bool) ? m['isSynced'] : (m['isSynced']?.toString() == 'true'),
      syncError: m['syncError']?.toString(),
    );
  }
}
