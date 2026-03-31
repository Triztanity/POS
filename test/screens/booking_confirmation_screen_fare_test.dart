import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/models/qr_data.dart';
import 'package:untitled/screens/booking_confirmation_screen.dart';

void main() {
  group('Booking Confirmation Fare Logic Tests', () {
    Widget createWidget(QRData qrData) {
      return MaterialApp(
        home: BookingConfirmationScreen(
          qrData: qrData,
          routeDirection: 'Northbound',
          conductorName: 'Test Conductor',
          driverName: 'Test Driver',
        ),
      );
    }

    testWidgets('Single passenger REGULAR with mismatched QR fare ignores QR fare', (WidgetTester tester) async {
      final qrData = QRData(
        bookingId: 'B1',
        userId: 'U1',
        transactionId: 'T1',
        origin: 'NASUGBU TERMINAL',
        destination: 'LIAN SHED', // Distance: 2km, fare 25/20
        fareAmount: 100.0, // Mismatched QR fare
        assignedBusNumber: 'BUS001',
        passengerName: 'John Doe',
        numberOfPassengers: 1,
        bookingDate: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await tester.pumpWidget(createWidget(qrData));
      await tester.pumpAndSettle();

      // Original fare should be 25.0, final fare 25.0
      expect(find.text('₱25.00'), findsNWidgets(2)); // Original Fare and Final Fare
    });

    testWidgets('Single passenger discounted type should match route table discounted fare', (WidgetTester tester) async {
      final qrData = QRData(
        bookingId: 'B2',
        userId: 'U2',
        transactionId: 'T2',
        origin: 'NASUGBU TERMINAL',
        destination: 'LIAN SHED', 
        fareAmount: 20.0, 
        assignedBusNumber: 'BUS001',
        passengerName: 'Student Doe',
        numberOfPassengers: 1,
        bookingDate: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await tester.pumpWidget(createWidget(qrData));
      await tester.pumpAndSettle();

      // Original fare 25.0 as it defaults to REGULAR
      expect(find.text('₱25.00'), findsNWidgets(2));

      // Open Dropdown
      await tester.tap(find.text('REGULAR'));
      await tester.pumpAndSettle();
      
      // Select STUDENT (the last one usually is the dropdown item)
      await tester.tap(find.text('STUDENT').last);
      await tester.pumpAndSettle();

      // Original fare 25.0, Final fare 20.0, Discount 5.0
      expect(find.text('₱25.00'), findsOneWidget); // Original Fare
      expect(find.text('₱20.00'), findsOneWidget); // Final Fare
      expect(find.text('-₱5.00'), findsOneWidget); // Discount
    });

    testWidgets('Multi-passenger mixed types should compute per seat then sum', (WidgetTester tester) async {
      final qrData = QRData(
        bookingId: 'B3',
        userId: 'U3',
        transactionId: 'T3',
        origin: 'NASUGBU TERMINAL',
        destination: 'LIAN SHED', 
        fareAmount: 50.0,
        assignedBusNumber: 'BUS001',
        passengerName: 'Family',
        numberOfPassengers: 2,
        bookingDate: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await tester.pumpWidget(createWidget(qrData));
      await tester.pumpAndSettle();

      // Default is 2 REGULAR, so 50.0 total
      expect(find.text('₱50.00'), findsNWidgets(2)); // Original and Final

      // Change passenger 2 to STUDENT
      final dropdowns = find.byType(DropdownButton<String>);
      expect(dropdowns, findsNWidgets(2));
      
      await tester.tap(dropdowns.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('STUDENT').last);
      await tester.pumpAndSettle();

      // Original 50.0, Final 45.0 (25 + 20), Discount 5.0
      expect(find.text('₱50.00'), findsOneWidget); // Original
      expect(find.text('₱45.00'), findsOneWidget); // Final
      expect(find.text('-₱5.00'), findsOneWidget); // Discount
    });

    testWidgets('Multi-passenger all REGULAR should ignore inflated QR fare', (WidgetTester tester) async {
      final qrData = QRData(
        bookingId: 'B4',
        userId: 'U4',
        transactionId: 'T4',
        origin: 'NASUGBU TERMINAL',
        destination: 'LIAN SHED', 
        fareAmount: 1000.0, // Inflated
        assignedBusNumber: 'BUS001',
        passengerName: 'Group',
        numberOfPassengers: 3,
        bookingDate: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      await tester.pumpWidget(createWidget(qrData));
      await tester.pumpAndSettle();

      // 3 REGULAR passengers: 3 * 25 = 75.00
      expect(find.text('₱75.00'), findsNWidgets(2)); // Original and Final
    });
  });
}
