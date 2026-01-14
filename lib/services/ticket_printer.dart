import 'package:flutter/foundation.dart';
import 'package:senraise_printer/senraise_printer.dart';

/// Print a complete thermal boarding ticket with all transaction details
class TicketPrinter {
  final SenraisePrinter _printer = SenraisePrinter();

  /// Print ticket using ticketData map with all required fields
  /// Expected keys:
  /// bookingId, transactionId, timestamp, busNumber, from, to, route,
  /// driverName, conductorName, passengerName, numberOfPassengers, passengerType,
  /// originalFare, discountAmount, finalFare
  Future<void> printTicket(Map<String, dynamic> ticketData) async {
    try {
      String singleLine(String? s) {
        if (s == null) return '';
        return s.replaceAll(RegExp(r"\s+"), ' ').trim();
      }

      String formatTimestamp(dynamic ts) {
        if (ts == null) return 'N/A';
        if (ts is DateTime) {
          final y = ts.year.toString().padLeft(4, '0');
          final m = ts.month.toString().padLeft(2, '0');
          final d = ts.day.toString().padLeft(2, '0');
          final hh = ts.hour.toString().padLeft(2, '0');
          final mm = ts.minute.toString().padLeft(2, '0');
          return '$y-$m-$d $hh:$mm';
        }
        final s = ts.toString();
        try {
          final dt = DateTime.parse(s);
          final y = dt.year.toString().padLeft(4, '0');
          final m = dt.month.toString().padLeft(2, '0');
          final d = dt.day.toString().padLeft(2, '0');
          final hh = dt.hour.toString().padLeft(2, '0');
          final mm = dt.minute.toString().padLeft(2, '0');
          return '$y-$m-$d $hh:$mm';
        } catch (_) {
          final epoch = int.tryParse(s);
          if (epoch != null) {
            final dt = DateTime.fromMillisecondsSinceEpoch(epoch);
            final y = dt.year.toString().padLeft(4, '0');
            final m = dt.month.toString().padLeft(2, '0');
            final d = dt.day.toString().padLeft(2, '0');
            final hh = dt.hour.toString().padLeft(2, '0');
            final mm = dt.minute.toString().padLeft(2, '0');
            return '$y-$m-$d $hh:$mm';
          }
          final m = RegExp(r"(\d{4}-\d{2}-\d{2}).*?(\d{2}:\d{2})").firstMatch(s);
          if (m != null) return '${m.group(1)} ${m.group(2)}';
          return singleLine(s);
        }
      }

      await _printer.setAlignment(1);
      await _printer.setTextBold(true);
      await _printer.setTextSize(24);
      final title = (ticketData['ticketTitle']?.toString() ?? 'BOARDING TICKET');
      await _printer.printText('$title\n');

      await _printer.setTextBold(false);
      await _printer.setTextSize(20);
      await _printer.nextLine(1);

      await _printer.setAlignment(0);

      // Header
      await _printer.printText('Booking ID : ${singleLine(ticketData['bookingId']?.toString() ?? 'N/A')}\n');
      await _printer.printText('Transaction : ${singleLine(ticketData['transactionId']?.toString() ?? 'N/A')}\n');
      await _printer.printText('Timestamp   : ${formatTimestamp(ticketData['timestamp'])}\n');

      // Bus & route
      await _printer.printText('Bus No.     : ${singleLine(ticketData['busNumber']?.toString() ?? 'N/A')}\n');
      await _printer.printText('Route       : ${singleLine(ticketData['route']?.toString() ?? 'N/A')}\n');
      await _printer.printText('From        : ${singleLine(ticketData['from']?.toString() ?? 'N/A')}\n');
      await _printer.printText('To          : ${singleLine(ticketData['to']?.toString() ?? 'N/A')}\n');

      // Crew
      await _printer.printText('Driver      : ${singleLine(ticketData['driverName']?.toString() ?? 'N/A')}\n');
      await _printer.printText('Conductor   : ${singleLine(ticketData['conductorName']?.toString() ?? 'N/A')}\n');

      // Passenger
      await _printer.printText('Passenger   : ${singleLine(ticketData['passengerName']?.toString() ?? 'N/A')}\n');
      await _printer.printText('Pax Count   : ${singleLine(ticketData['numberOfPassengers']?.toString() ?? '1')}\n');
      await _printer.printText('Type        : ${singleLine(ticketData['passengerType']?.toString() ?? 'REGULAR')}\n');

      // Fare
      await _printer.printText('Original    : ₱${singleLine(ticketData['originalFare']?.toString() ?? '0.00')}\n');
      final discountAmountStr = ticketData['discountAmount']?.toString() ?? '0';
      final discountAmount = double.tryParse(discountAmountStr) ?? 0.0;
      if (discountAmount > 0) {
        await _printer.printText('Discount    : -₱${singleLine(ticketData['discountAmount']?.toString() ?? '0.00')}\n');
      }
      await _printer.printText('Final Fare  : ₱${singleLine(ticketData['finalFare']?.toString() ?? '0.00')}\n');

      await _printer.setAlignment(1);
      await _printer.printText('Thank you for boarding!\n');
      await _printer.nextLine(3);
    } catch (e) {
      debugPrint('Ticket printing error: $e');
      rethrow;
    }  }
}