import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/utils/fare_calculator.dart';

void main() {
  test('Bilaran to Pantay should calculate non-zero fare', () {
    final fareA = BookingFareCalculator.calculateFare(
      origin: 'BILARAN',
      destination: 'PAG-ASA/PANTAY',
      passengerType: 'REGULAR',
    );

    final fareB = BookingFareCalculator.calculateFare(
      origin: 'BILIRAN',
      destination: 'PANTAY',
      passengerType: 'REGULAR',
    );

    expect(fareA, greaterThan(0));
    expect(fareB, greaterThan(0));
    expect(fareA, equals(fareB));
  });
}
