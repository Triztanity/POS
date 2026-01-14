# RouteValidationService Usage Guide

**Quick Reference** | **Complete Examples** | **Integration Patterns**

---

## Quick Start

### Import the Service
```dart
import 'services/route_validation_service.dart';
```

### Find a Station
```dart
final index = RouteValidationService.getStationIndex('Lian');
// Returns: 1 (the position in the 54-station sequence)
```

### Validate a Route
```dart
final result = RouteValidationService.validateRouteDirection(
  1,      // Origin index (Lian)
  6,      // Destination index (Palico)
  'North' // Route direction
);

if (result.success) {
  print('✓ Valid route');
} else {
  print('✗ ${result.message}');
}
```

### Check Destination
```dart
final isValid = RouteValidationService.isValidDestination(
  'PALICO',
  FareTable.placeNames, // Available destinations
);
```

---

## Complete API Reference

### Method: getStationIndex()

**Purpose**: Find a station's position in the route sequence

**Signature**:
```dart
static int getStationIndex(String? stationName)
```

**Parameters**:
- `stationName` (String?): The station name to look up. Can be partial or abbreviated.

**Returns**:
- `int`: Station index (0-53) if found, or **-1** if not found

**Examples**:
```dart
RouteValidationService.getStationIndex('Nasugbu Terminal')  // → 0
RouteValidationService.getStationIndex('Nasugbu')          // → 0 (fuzzy)
RouteValidationService.getStationIndex('Lian')             // → 1
RouteValidationService.getStationIndex('lian shed')        // → 1 (case-insensitive)
RouteValidationService.getStationIndex('Batangas')         // → 53
RouteValidationService.getStationIndex('Unknown Station')  // → -1
RouteValidationService.getStationIndex(null)               // → -1
```

**Fuzzy Matching**:
The method first tries exact match (after normalization), then substring match:
- Exact: "Lian Shed" (normalized) = "lian shed"
- Substring: "Lian" matches "Lian Shed"
- Case-insensitive: "NASUGBU" matches "Nasugbu Terminal"
- Whitespace-tolerant: "lian   shed" matches "lian shed"

---

### Method: validateRouteDirection()

**Purpose**: Check if origin→destination follows North/South route rules

**Signature**:
```dart
static ValidationResult validateRouteDirection(
  int originIndex,
  int destinationIndex,
  String routeDirection,
)
```

**Parameters**:
- `originIndex` (int): Station index where passenger boarded
- `destinationIndex` (int): Station index where passenger alights
- `routeDirection` (String): Route name ('North', 'north', 'north_to_south', 'South', 'south', 'south_to_north')

**Returns**:
- `ValidationResult`: Object with `.success` (bool) and `.message` (String?)

**Route Rules**:
- **North** (Nasugbu → Batangas): `originIndex < destinationIndex`
- **South** (Batangas → Nasugbu): `originIndex > destinationIndex`

**Examples**:
```dart
// North route: valid
final north = RouteValidationService.validateRouteDirection(1, 6, 'North');
// north.success == true (1 < 6)

// North route: invalid (passenger going backwards)
final north2 = RouteValidationService.validateRouteDirection(6, 1, 'North');
// north2.success == false (6 > 1)
// north2.message == 'Passenger is out of route and going to the wrong direction'

// South route: valid
final south = RouteValidationService.validateRouteDirection(53, 1, 'South');
// south.success == true (53 > 1)

// South route: invalid
final south2 = RouteValidationService.validateRouteDirection(1, 53, 'South');
// south2.success == false (1 < 53)

// Normalized route names
final alt1 = RouteValidationService.validateRouteDirection(1, 6, 'north_to_south');
// alt1.success == true

final alt2 = RouteValidationService.validateRouteDirection(53, 1, 'south_to_north');
// alt2.success == true
```

---

### Method: isValidDestination()

**Purpose**: Check if a destination is in the available dropdown list

**Signature**:
```dart
static bool isValidDestination(
  String? destination,
  List<String> availableDestinations,
)
```

**Parameters**:
- `destination` (String?): Destination name to validate
- `availableDestinations` (List<String>): Valid destinations from dropdown

**Returns**:
- `bool`: **true** if destination is in the list, **false** otherwise

**Examples**:
```dart
final places = FareTable.placeNames; // ['NASUGBU', 'LIAN', 'PALICO', ...]

// Valid destination
RouteValidationService.isValidDestination('PALICO', places)  // → true

// Case variation
RouteValidationService.isValidDestination('Palico', places)  // → true

// Extra whitespace
RouteValidationService.isValidDestination('  PALICO  ', places) // → true

// Invalid destination
RouteValidationService.isValidDestination('UNKNOWN', places)  // → false

// Null destination
RouteValidationService.isValidDestination(null, places)  // → false

// Empty destination
RouteValidationService.isValidDestination('', places)  // → false
```

---

### Constant: stationSequence

**Purpose**: The canonical list of all 54 stations in route order

**Type**: `List<String>` (const)

**Length**: 54 stations (index 0-53)

**Order**: Nasugbu Terminal → Batangas Terminal

**Usage**:
```dart
// Get all stations
final allStations = RouteValidationService.stationSequence;
// allStations.length == 54
// allStations[0] == 'Nasugbu Terminal'
// allStations[53] == 'Batangas Terminal'

// Iterate stations
for (int i = 0; i < RouteValidationService.stationSequence.length; i++) {
  print('$i: ${RouteValidationService.stationSequence[i]}');
}

// Get station by index
final station = RouteValidationService.stationSequence[15]; // 'Brgy. Hall Lanatan'
```

---

## Integration Patterns

### Pattern 1: QR Validation (Offline Service)

**Use Case**: Validate QR code payload during scanning

```dart
import 'services/offline_qr_service.dart';
import 'utils/fare_calculator.dart';

// After QR is scanned
final result = await OfflineQrService.validateAndProcess(
  rawQr: qrCodeData,
  currentBusNumber: 'BUS-002',
  currentRoute: 'North',
  availableDestinations: FareTable.placeNames,
);

if (result.success) {
  // Show booking confirmation screen
  final qrData = result.data;
  print('Passenger: ${qrData['origin']} → ${qrData['destination']}');
  print('Fare: ₱${qrData['fare']}');
} else {
  // Show error to operator
  showErrorDialog(result.message);
}
```

---

### Pattern 2: Manual Station Entry

**Use Case**: User manually enters origin/destination

```dart
import 'services/route_validation_service.dart';

String userOrigin = 'Lian';
String userDestination = 'Palico';

// Find indices
final originIndex = RouteValidationService.getStationIndex(userOrigin);
final destIndex = RouteValidationService.getStationIndex(userDestination);

if (originIndex < 0 || destIndex < 0) {
  showErrorDialog('Invalid station entered');
  return;
}

// Validate route
final validation = RouteValidationService.validateRouteDirection(
  originIndex,
  destIndex,
  currentRoute, // 'North' or 'South'
);

if (!validation.success) {
  showErrorDialog('Invalid route: ${validation.message}');
  return;
}

// Proceed with booking
processBooking(originIndex, destIndex);
```

---

### Pattern 3: Destination Dropdown Building

**Use Case**: Populate destination dropdown based on selected origin

```dart
import 'services/route_validation_service.dart';

String selectedOrigin = 'Lian'; // User selected this
int originIndex = RouteValidationService.getStationIndex(selectedOrigin);

if (originIndex < 0) return;

// Get all valid destinations based on route direction
List<String> validDestinations = [];

if (currentRoute == 'North') {
  // For North route: destinations must have index > origin
  for (int i = originIndex + 1; i < RouteValidationService.stationSequence.length; i++) {
    validDestinations.add(RouteValidationService.stationSequence[i]);
  }
} else {
  // For South route: destinations must have index < origin
  for (int i = 0; i < originIndex; i++) {
    validDestinations.add(RouteValidationService.stationSequence[i]);
  }
}

// Use validDestinations in dropdown
buildDropdown(validDestinations);
```

---

### Pattern 4: Station Autocomplete

**Use Case**: Filter station list as user types

```dart
import 'services/route_validation_service.dart';

String userInput = 'lia'; // User typing "lia..."

List<String> suggestions = [];
final normalized = userInput.toLowerCase();

for (final station in RouteValidationService.stationSequence) {
  if (station.toLowerCase().contains(normalized)) {
    suggestions.add(station);
  }
}

// Show suggestions: ['Lian Shed', 'Brgy. Hall Lanatan', ...]
showSuggestions(suggestions);
```

---

### Pattern 5: Route Validation with Error Handling

**Use Case**: Complete validation with user feedback

```dart
import 'services/route_validation_service.dart';

String origin = 'Nasugbu';
String destination = 'Lemery Xentro';
String route = 'North';

// Step 1: Validate origin exists
final originIdx = RouteValidationService.getStationIndex(origin);
if (originIdx < 0) {
  showError('Origin station not found: $origin');
  return;
}

// Step 2: Validate destination exists
final destIdx = RouteValidationService.getStationIndex(destination);
if (destIdx < 0) {
  showError('Destination station not found: $destination');
  return;
}

// Step 3: Validate route direction
final validation = RouteValidationService.validateRouteDirection(
  originIdx,
  destIdx,
  route,
);

if (!validation.success) {
  showError(validation.message ?? 'Invalid route');
  return;
}

// Step 4: All valid, proceed
showSuccess('Valid route: $origin → $destination ($route)');
```

---

### Pattern 6: Station Index Calculation

**Use Case**: Calculate distance or fare based on station indices

```dart
import 'services/route_validation_service.dart';

String origin = 'Lian';
String destination = 'Batangas Terminal';

final originIdx = RouteValidationService.getStationIndex(origin);
final destIdx = RouteValidationService.getStationIndex(destination);

// Calculate distance as number of stops
final stops = (destIdx - originIdx).abs();
print('Number of stops: $stops');

// Example: ₱5 per stop
final fare = 50 + (stops * 5);
print('Estimated fare: ₱$fare');
```

---

## Error Handling

### Handling Invalid Stations

```dart
final index = RouteValidationService.getStationIndex('Invalid Station');

if (index == -1) {
  // Station not found
  showErrorDialog('Station not recognized. Please check spelling.');
} else {
  // Station found, proceed
  useStation(index);
}
```

### Handling Invalid Routes

```dart
final result = RouteValidationService.validateRouteDirection(
  6,      // Palico
  1,      // Lian
  'North' // Wrong direction for this pair
);

if (!result.success) {
  // Show specific error
  showErrorDialog(result.message ?? 'Route validation failed');
  
  // Log for debugging
  print('Failed validation:');
  print('  Origin: 6 (Palico)');
  print('  Destination: 1 (Lian)');
  print('  Route: North');
  print('  Error: ${result.message}');
}
```

---

## Testing Examples

### Unit Test: Station Lookup

```dart
import 'package:flutter_test/flutter_test.dart';
import 'services/route_validation_service.dart';

void main() {
  group('RouteValidationService', () {
    test('Should find station index for exact match', () {
      expect(RouteValidationService.getStationIndex('Lian Shed'), 1);
    });

    test('Should find station with fuzzy match', () {
      expect(RouteValidationService.getStationIndex('Lian'), 1);
    });

    test('Should be case-insensitive', () {
      expect(RouteValidationService.getStationIndex('NASUGBU'), 0);
      expect(RouteValidationService.getStationIndex('nasugbu'), 0);
    });

    test('Should return -1 for unknown station', () {
      expect(RouteValidationService.getStationIndex('Unknown'), -1);
    });

    test('Should handle null input', () {
      expect(RouteValidationService.getStationIndex(null), -1);
    });
  });
}
```

### Unit Test: Route Validation

```dart
test('North route: should accept origin < destination', () {
  final result = RouteValidationService.validateRouteDirection(1, 6, 'North');
  expect(result.success, true);
});

test('North route: should reject origin > destination', () {
  final result = RouteValidationService.validateRouteDirection(6, 1, 'North');
  expect(result.success, false);
  expect(result.message, contains('out of route'));
});

test('South route: should accept origin > destination', () {
  final result = RouteValidationService.validateRouteDirection(53, 1, 'South');
  expect(result.success, true);
});

test('South route: should reject origin < destination', () {
  final result = RouteValidationService.validateRouteDirection(1, 53, 'South');
  expect(result.success, false);
  expect(result.message, contains('out of route'));
});
```

---

## Performance Considerations

- **getStationIndex()**: O(n) but n=54, negligible (~microseconds)
- **validateRouteDirection()**: O(1) - simple integer comparison
- **isValidDestination()**: O(n) for list search, but lists are typically small
- **Memory**: Constant 54-element list is shared, no copies created

---

## Common Mistakes

### ❌ Using wrong direction string
```dart
// WRONG - not recognized
RouteValidationService.validateRouteDirection(1, 6, 'NORTH');

// RIGHT - use 'North', 'north', or 'north_to_south'
RouteValidationService.validateRouteDirection(1, 6, 'North');
```

### ❌ Not checking return value
```dart
// WRONG - doesn't check if found
final index = RouteValidationService.getStationIndex('Unknown');
processStation(index); // Will use -1!

// RIGHT - always check
final index = RouteValidationService.getStationIndex('Unknown');
if (index == -1) {
  showError('Station not found');
  return;
}
processStation(index);
```

### ❌ Comparing stations by name
```dart
// WRONG - string comparison fails due to variations
if (origin == 'Lian Shed') { ... } // What if user entered "Lian"?

// RIGHT - use getStationIndex and compare indices
final originIdx = RouteValidationService.getStationIndex(origin);
if (originIdx == 1) { ... } // Works for "Lian", "lian shed", "LIAN", etc.
```

---

## Station List Reference

See [STATION_SEQUENCE_REFERENCE.md](STATION_SEQUENCE_REFERENCE.md) for:
- Complete 54-station table with indices
- Validation rule examples
- Fuzzy matching patterns
- FareTable places mapping

---

**Version**: 1.0  
**Last Updated**: January 5, 2025  
**Related Docs**: [QR_VALIDATION_REFACTOR.md](QR_VALIDATION_REFACTOR.md) | [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md)
