import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/utils/fare_calculator.dart';

void main() {
  tearDown(() {
    FareTable.resetToBundledDefaults();
  });

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

  test('remote blank-place rows compute fares but do not display as stops', () {
    final remoteEntries = [
      FareEntry(place: 'NASUGBU', km: 0, fare: 25, discount: 20),
      FareEntry(place: '', km: 1, fare: 25, discount: 20),
      FareEntry(place: 'LIAN', km: 2, fare: 25, discount: 20),
      FareEntry(place: '', km: 3, fare: 25, discount: 20),
      FareEntry(place: '', km: 4, fare: 30, discount: 24),
      FareEntry(place: 'CENTRAL', km: 5, fare: 35, discount: 28),
    ];

    FareTable.loadEntries(remoteEntries);

    expect(FareTable.placeNames, isNot(contains('')));
    expect(FareTable.placeNamesWithKm, isNot(contains('4|')));

    final fare = FareCalculator.calculateFare(
      origin: 'NASUGBU',
      destination: 'CENTRAL',
      passengerType: 'STUDENT',
    );

    expect(fare, 28);
  });

  test('invalid remote fare table keeps current entries', () {
    final originalEntryCount = FareTable.entries.length;

    FareTable.loadEntries([
      FareEntry(place: 'NASUGBU', km: 0, fare: 25, discount: 20),
      FareEntry(place: 'CENTRAL', km: 5, fare: 35, discount: 28),
    ]);

    expect(FareTable.entries.length, originalEntryCount);
  });

  test('remote fare table coordinates become the primary station list', () {
    FareTable.loadEntries([
      FareEntry.fromMap({
        'place': 'Nasugbu',
        'km': 0,
        'fare': 25,
        'discount': 20,
        'coordinates': {
          'latitude': 14.07307,
          'longitude': 120.63197,
        },
      }),
      FareEntry(place: '', km: 1, fare: 25, discount: 20),
      FareEntry.fromMap({
        'place': 'Lian',
        'km': 2,
        'fare': 25,
        'discount': 20,
        'latitude': 14.05514,
        'longitude': 120.64694,
      }),
    ]);

    expect(FareTable.hasCompleteStationCoordinates, isTrue);
    expect(FareTable.stationCount, 2);
    expect(FareTable.getStationNameByRouteOrder(0), 'NASUGBU');
    expect(FareTable.getStationNameByRouteOrder(1), 'LIAN');

    final stations = FareTable.stationLocationsWithCoordinates;
    expect(stations, hasLength(2));
    expect(stations[0].routeOrder, 0);
    expect(stations[0].name, 'NASUGBU');
    expect(stations[1].routeOrder, 1);
    expect(stations[1].name, 'LIAN');
  });

  test('missing station coordinates keep fare-table station source incomplete',
      () {
    FareTable.loadEntries([
      FareEntry(
        place: 'NASUGBU',
        km: 0,
        fare: 25,
        discount: 20,
        latitude: 14.07307,
        longitude: 120.63197,
      ),
      FareEntry(place: '', km: 1, fare: 25, discount: 20),
      FareEntry(place: 'LIAN', km: 2, fare: 25, discount: 20),
    ]);

    expect(FareTable.stationCount, 2);
    expect(FareTable.hasCompleteStationCoordinates, isFalse);
    expect(FareTable.stationLocationsWithCoordinates, hasLength(1));
  });
}
