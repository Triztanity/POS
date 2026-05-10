import 'package:untitled/utils/fare_calculator.dart';

// This file provides a list of all valid stops for the dropdowns, matching the fare table.
// Now includes km values in format "km|Place"
List<String> get fareTableStops => FareTable.placeNamesWithKm;
