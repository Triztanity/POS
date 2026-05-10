import 'package:flutter/foundation.dart';

class ArrivalReportSyncService {
  static final ArrivalReportSyncService _instance =
      ArrivalReportSyncService._internal();

  factory ArrivalReportSyncService() => _instance;

  ArrivalReportSyncService._internal() {
    debugPrint(
        '[ArrivalReportSyncService] Legacy arrivalReports sync disabled.');
  }

  void dispose() {}
}
