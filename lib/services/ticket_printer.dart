import 'package:flutter/foundation.dart';
import 'package:senraise_printer/senraise_printer.dart';

/// Print a complete thermal boarding ticket with all transaction details
class TicketPrinter {
  final SenraisePrinter _printer = SenraisePrinter();

  String _singleLine(String? s) {
    if (s == null) return '';
    return s.replaceAll(RegExp(r"\s+"), ' ').trim();
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return 'N/A';
    DateTime dt;
    if (ts is DateTime) {
      dt = ts;
    } else {
      final s = ts.toString();
      final epoch = int.tryParse(s);
      if (epoch != null) {
        dt = DateTime.fromMillisecondsSinceEpoch(epoch);
      } else {
        try {
          dt = DateTime.parse(s);
        } catch (_) {
          return _singleLine(s);
        }
      }
    }

    const wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday =
        (dt.weekday >= 1 && dt.weekday <= 7) ? wk[dt.weekday - 1] : '';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$weekday $y-$m-$d $hh:$mm';
  }

  Future<void> printTicket(Map<String, dynamic> ticketData) async {
    try {
      final title = ticketData['ticketTitle']?.toString() ?? 'BOARDING TICKET';
      final passengerType =
          _singleLine(ticketData['passengerType']?.toString() ?? 'REGULAR');
      final route = _singleLine(ticketData['route']?.toString() ?? 'N/A');
      final vehicleNo =
          _singleLine(ticketData['busNumber']?.toString() ?? 'N/A');
      final date = ticketData['date']?.toString() ??
          _formatTimestamp(ticketData['timestamp'])
              .split(' ')
              .sublist(0, 2)
              .join(' ');
      final time = ticketData['time']?.toString() ??
          _formatTimestamp(ticketData['timestamp']).split(' ').last;
      var from = _singleLine(ticketData['from']?.toString() ?? 'N/A');
      var to = _singleLine(ticketData['to']?.toString() ?? 'N/A');
      if (from.contains('|')) from = from.split('|').last.trim();
      if (to.contains('|')) to = to.split('|').last.trim();
      // Remove leading numeric prefixes from station names (e.g., "1. NASUGBU", "23. TUY")
      from = from.replaceAll(RegExp(r'^\s*\d+[\.|\)]?\s*'), '').trim();
      to = to.replaceAll(RegExp(r'^\s*\d+[\.|\)]?\s*'), '').trim();
      final distance = ticketData['distance']?.toString() ?? '0';
      final quantity = ticketData['quantity']?.toString() ??
          ticketData['numberOfPassengers']?.toString() ??
          '1';
      final driver = _singleLine(ticketData['driverName']?.toString() ?? 'N/A');
      final conductor =
          _singleLine(ticketData['conductorName']?.toString() ?? 'N/A');
      final payment = _singleLine(ticketData['payment']?.toString() ?? 'CASH');
      final originalFare =
          _singleLine(ticketData['originalFare']?.toString() ?? '0.00');
      final discountAmount =
          _singleLine(ticketData['discountAmount']?.toString() ?? '0.00');
      final finalFare =
          _singleLine(ticketData['finalFare']?.toString() ?? originalFare);

      await _printer.printReceipt(
        title: title,
        vehicleNo: vehicleNo,
        date: date,
        time: time,
        from: from,
        to: to,
        distance: distance,
        passengerType: passengerType,
        route: route,
        driverName: driver,
        conductorName: conductor,
        payment: payment,
        quantity: quantity,
        amount: finalFare,
        originalFare: originalFare,
        discountAmount: discountAmount,
      );
    } on Exception catch (e) {
      debugPrint('Ticket printing error: $e');
      rethrow;
    }
  }
}
