// fare_calculator.dart
// Contains fare table and fare calculation logic for the POS app.

class FareEntry {
  final String place;
  final int km;
  final int fare;
  final int discount;

  FareEntry({required this.place, required this.km, required this.fare, required this.discount});
}

class FareTable {
  static final List<FareEntry> entries = [
    FareEntry(place: 'NASUGBU', km: 0, fare: 25, discount: 20),
    FareEntry(place: '', km: 1, fare: 25, discount: 20),
    FareEntry(place: 'LIAN', km: 2, fare: 25, discount: 20),
    FareEntry(place: 'SAGBAT', km: 3, fare: 25, discount: 20),
    FareEntry(place: '', km: 4, fare: 25, discount: 20),
    FareEntry(place: 'CENTRAL', km: 5, fare: 25, discount: 20),
    FareEntry(place: 'IRRIGATION', km: 6, fare: 25, discount: 20),
    FareEntry(place: 'BILARAN', km: 7, fare: 25, discount: 20),
    FareEntry(place: '', km: 8, fare: 25, discount: 20),
    FareEntry(place: 'PALICO', km: 9, fare: 25, discount: 20),
    FareEntry(place: 'PAHINANTE', km: 10, fare: 25, discount: 20),
    FareEntry(place: 'LUNTAL', km: 11, fare: 25, discount: 20),
    FareEntry(place: 'TALON', km: 12, fare: 27, discount: 22),
    FareEntry(place: '', km: 13, fare: 29, discount: 23),
    FareEntry(place: 'TUY', km: 14, fare: 32, discount: 26),
    FareEntry(place: '', km: 15, fare: 34, discount: 27),
    FareEntry(place: 'OBISPO', km: 16, fare: 36, discount: 29),
    FareEntry(place: '', km: 17, fare: 38, discount: 31),
    FareEntry(place: 'PUTOL', km: 18, fare: 41, discount: 33),
    FareEntry(place: 'GUINHAWA', km: 19, fare: 43, discount: 34),
    FareEntry(place: 'MUNTING TUBIG', km: 20, fare: 45, discount: 36),
    FareEntry(place: 'LANATAN', km: 21, fare: 47, discount: 38),
    FareEntry(place: '', km: 22, fare: 50, discount: 40),
    FareEntry(place: 'BALAYAN', km: 23, fare: 52, discount: 42),
    FareEntry(place: 'GUMAMELA', km: 24, fare: 54, discount: 43),
    FareEntry(place: 'GIMALAS', km: 25, fare: 56, discount: 45),
    FareEntry(place: 'CAYBUNGA', km: 26, fare: 59, discount: 47),
    FareEntry(place: 'SAMPAGA', km: 27, fare: 61, discount: 49),
    FareEntry(place: '', km: 28, fare: 63, discount: 50),
    FareEntry(place: 'DACANLAO', km: 29, fare: 65, discount: 52),
    FareEntry(place: 'PAG-ASA/PANTAY', km: 30, fare: 68, discount: 54),
    FareEntry(place: '', km: 31, fare: 70, discount: 56),
    FareEntry(place: 'CALACA/BAYAN', km: 32, fare: 72, discount: 58),
    FareEntry(place: 'SALONG', km: 33, fare: 74, discount: 59),
    FareEntry(place: '', km: 34, fare: 77, discount: 62),
    FareEntry(place: 'PUTING BATO', km: 35, fare: 79, discount: 63),
    FareEntry(place: '', km: 36, fare: 81, discount: 65),
    FareEntry(place: 'SINISIAN', km: 37, fare: 83, discount: 67),
    FareEntry(place: 'MATAAS NA BAYAN', km: 38, fare: 86, discount: 69),
    FareEntry(place: 'MAHAYAHAY', km: 39, fare: 88, discount: 71),
    FareEntry(place: '', km: 40, fare: 90, discount: 72),
    FareEntry(place: 'MATINGAIN', km: 41, fare: 92, discount: 74),
    FareEntry(place: 'BUKAL', km: 42, fare: 95, discount: 76),
    FareEntry(place: 'TUBIGAN', km: 43, fare: 97, discount: 78),
    FareEntry(place: 'MALINIS', km: 44, fare: 99, discount: 79),
    FareEntry(place: 'LEMERY XENTRO MALL', km: 45, fare: 101, discount: 81),
    FareEntry(place: 'LAGUILE', km: 46, fare: 104, discount: 83),
    FareEntry(place: 'HALANG', km: 47, fare: 106, discount: 85),
    FareEntry(place: 'LATAG', km: 48, fare: 108, discount: 86),
    FareEntry(place: 'TULO', km: 49, fare: 110, discount: 88),
    FareEntry(place: 'JOLLIBEE TAAL', km: 50, fare: 113, discount: 90),
    FareEntry(place: 'BULI', km: 51, fare: 115, discount: 92),
    FareEntry(place: 'TAWILISAN', km: 52, fare: 117, discount: 94),
    FareEntry(place: 'MOHON', km: 53, fare: 119, discount: 95),
    FareEntry(place: 'STA. TERESITA', km: 54, fare: 122, discount: 98),
    FareEntry(place: 'SAN LUIS', km: 55, fare: 124, discount: 99),
    FareEntry(place: 'MUZON', km: 56, fare: 126, discount: 101),
    FareEntry(place: '', km: 57, fare: 128, discount: 102),
    FareEntry(place: 'CUPANG', km: 58, fare: 131, discount: 105),
    FareEntry(place: '', km: 59, fare: 133, discount: 106),
    FareEntry(place: 'AS-IS', km: 60, fare: 135, discount: 108),
    FareEntry(place: '', km: 61, fare: 137, discount: 110),
    FareEntry(place: 'BALAYONG', km: 62, fare: 140, discount: 112),
    FareEntry(place: '', km: 63, fare: 142, discount: 114),
    FareEntry(place: 'MANGHINAO', km: 64, fare: 144, discount: 115),
    FareEntry(place: 'BAUAN', km: 65, fare: 146, discount: 117),
    FareEntry(place: 'SAN ANTONIO', km: 66, fare: 149, discount: 119),
    FareEntry(place: 'SAN PASCUAL', km: 67, fare: 151, discount: 121),
    FareEntry(place: '', km: 68, fare: 153, discount: 122),
    FareEntry(place: 'STA. RITA', km: 69, fare: 155, discount: 124),
    FareEntry(place: 'COMPLEX', km: 70, fare: 158, discount: 126),
    FareEntry(place: 'DIVERSION', km: 70, fare: 158, discount: 126),
    FareEntry(place: 'BOLBOK', km: 70, fare: 158, discount: 126),
    FareEntry(place: 'BATANGAS TERMINAL', km: 70, fare: 158, discount: 126),
  ];

  static List<String> get placeNames =>
      entries.where((e) => e.place.isNotEmpty).map((e) => e.place).toSet().toList();

  static FareEntry? getEntryByPlace(String place) {
    try {
      final normalizedInput = normalizePlaceName(place);
      
      // Try exact match with normalized names
      var entry = entries.firstWhere(
        (e) => normalizePlaceName(e.place) == normalizedInput && e.place.isNotEmpty,
        orElse: () => FareEntry(place: '', km: 0, fare: 0, discount: 0),
      );
      if (entry.place.isNotEmpty) return entry;
      // Tokenize for safer matching (avoid false positives from substring checks)
      final cleanPlace = normalizedInput;
      final inputWords = cleanPlace.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

      // Match where all words of the fare table place appear in the input (e.g., "NASUGBU TERMINAL" -> "NASUGBU")
      entry = entries.firstWhere(
        (e) {
          if (e.place.isEmpty) return false;
          final candidate = normalizePlaceName(e.place);
          final candWords = candidate.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
          // all candidate words must be present in inputWords
          return candWords.every((cw) => inputWords.contains(cw));
        },
        orElse: () => FareEntry(place: '', km: 0, fare: 0, discount: 0),
      );
      if (entry.place.isNotEmpty) return entry;

      // Reverse: input is short and may match part of a fare place
      entry = entries.firstWhere(
        (e) {
          if (e.place.isEmpty) return false;
          final candidate = normalizePlaceName(e.place);
          // check if inputWords are all contained in candidate words
          final candWords = candidate.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
          return inputWords.every((iw) => candWords.contains(iw));
        },
        orElse: () => FareEntry(place: '', km: 0, fare: 0, discount: 0),
      );
      return entry.place.isNotEmpty ? entry : null;
    } catch (_) {
      return null;
    }
  }

  /// Get formatted location string with km: "70|Bolbok"
  static String getFormattedLocation(String place) {
    final entry = getEntryByPlace(place);
    if (entry != null) {
      return '${entry.km}|${entry.place}';
    }
    return place;
  }

  /// Get list of places with km values: ["0|NASUGBU", "2|LIAN", ...]
  /// Uses normalized place names to ensure consistency
  static List<String> get placeNamesWithKm {
    final uniquePlaces = <String, int>{};
    for (var entry in entries) {
      if (entry.place.isNotEmpty) {
        final normalized = normalizePlaceName(entry.place);
        // Use the normalized name as key to avoid duplicates with different formatting
        if (!uniquePlaces.containsKey(normalized)) {
          uniquePlaces[normalized] = entry.km;
        }
      }
    }
    return uniquePlaces.entries
        .map((e) => '${e.value}|${e.key}')
        .toList();
  }

  /// Extract place name from formatted string "km|Place"
  static String extractPlaceName(String formattedLocation) {
    if (formattedLocation.contains('|')) {
      return formattedLocation.split('|')[1];
    }
    return formattedLocation;
  }

  /// Get km as string for a given place. Returns empty string when unknown.
  static String getKmString(String place) {
    final entry = getEntryByPlace(place);
    if (entry != null) return entry.km.toString();
    // If getFormattedLocation returned a pipe-separated value, try parsing the km part
    final formatted = getFormattedLocation(place);
    if (formatted.contains('|')) {
      final parts = formatted.split('|');
      final kmPart = parts[0];
      final kmInt = int.tryParse(kmPart);
      if (kmInt != null) return kmInt.toString();
    }
    return '';
  }

  /// Normalize place name by removing numbers, pipes, dots, and extra whitespace
  /// Handles leading numbers, mid-string hyphens/dashes, and collapses multiple spaces
  /// Examples: "1. LIAN" -> "LIAN", "2|LIAN" -> "LIAN", "MAHAYAHAY 7-11" -> "MAHAYAHAY 711", "LIAN" -> "LIAN"
  static String normalizePlaceName(String place) {
    return place
        .replaceAll(RegExp(r'^[\d\.\|\s]+'), '') // Remove leading numbers, dots, pipes, spaces
        .replaceAll('-', ' ') // Convert hyphens to spaces for token-based matching
        .replaceAll(RegExp(r'\s+'), ' ') // Collapse multiple spaces to single space
        .trim()
        .toUpperCase();
  }

  static FareEntry? getEntryByKm(int km) {
    try {
      return entries.firstWhere((e) => e.km == km);
    } catch (_) {
      return null;
    }
  }
  
  /// Find a fare table entry by its exact fare value (uses rounded int match)
  static FareEntry? getEntryByFare(double fare) {
    try {
      final intFare = fare.round();
      return entries.firstWhere((e) => e.fare == intFare);
    } catch (_) {
      return null;
    }
  }
}

class FareCalculator {
  static int calculateFare({
    required String origin,
    required String destination,
    required String passengerType,
    int quantity = 1,
  }) {
    final originEntry = FareTable.getEntryByPlace(origin);
    final destEntry = FareTable.getEntryByPlace(destination);
    if (originEntry == null || destEntry == null) return 0;
    final kmTraveled = (originEntry.km - destEntry.km).abs();
    final fareEntry = FareTable.getEntryByKm(kmTraveled);
    if (fareEntry == null) return 0;
    final farePerPassenger =
        passengerType.toLowerCase() == 'regular' ? fareEntry.fare : fareEntry.discount;
    return farePerPassenger * quantity;
  }
}

/// Booking Fare Calculator
/// Uses the exact station names from RouteValidator for accurate fare calculation in booking confirmation
class BookingFareCalculator {
  /// Master station list from RouteValidator - same order and naming as booking system
  static const List<String> bookingStations = [
    'NASUGBU TERMINAL',
    'LIAN SHED',
    'SAGBAT',
    'CENTRAL',
    'IRRIGATION WAITING SHED/TODA',
    'BILARAN ELEM SCHOOL WAITING SHED',
    'PALICO TERMINAL',
    'PAHINANTE WAITING SHED',
    'LUNTAL WAITING SHED',
    'TALON WAITING SHED',
    'TUY',
    'OBISPO',
    'BRGY PUTOL WAITING SHED',
    'BRGY GUINHAWA WAITING SHED',
    'FLYING V MUNITING TUBIG',
    'BRGY. HALL LANATAN',
    'BALAYAN WALTERMART',
    'SPYDER FUEL GUMAMELA',
    'GIMALAS',
    'ALFAMART CAYBUNGA',
    'BRGY. HALL/WAITING SHED SAMPAGA',
    'DACANLAO WAITING SHED',
    'ALFAMART PANTAY',
    'ROBINSONS CALACA/BAYAN',
    'FLAMINGO GAS STATION SALONG',
    'PUTING BATO CALACA',
    'SINISIAN ELEM. SCHOOL',
    'MATAAS NA BAYAN BRGY. HALL',
    'MAHAYAHAY 7 11',
    'MATINGAIN MALL NA POON',
    'BUKAL THE BLACK TEA PROJECT',
    'TUBIGAN ICE PLANT',
    'MALINIS WILCON DEPOT',
    'LEMERY XENTRO MALL',
    'LAGUILE FOOD HOUSE',
    'HALANG FLYING V',
    'LATAG WAITING SHED',
    'TULO WAITING SHED',
    'JOLLIBEE TAAL',
    'BULI BRGY. HALL',
    'TAWILISAN 7 11',
    'MOHON ELEM SCHOOL',
    'STA. TERESITA CHURCH',
    'SAN LUIS INTERSECTION',
    'MUZON',
    'CUPANG WAITING SHED/ SCHOOL',
    'AS-IS BRGY. HALL',
    'BALAYONG CLEAN FUEL',
    'MANGHINAO',
    'CITIMART BAUAN',
    'SAN ANTONIO',
    'SAN PASCUAL',
    'STA. RITA BRGY. HALL'
    'COMPLEX',
    'DIVERSION NTC',
    'BATANGAS GRAND TERMINAL',
  ];

  /// Calculate fare based on booking station names
  /// Returns the fare amount based on passenger type and distance
  static int calculateFare({
    required String origin,
    required String destination,
    required String passengerType,
    int quantity = 1,
  }) {
    final cleanOrigin = origin.trim().toUpperCase();
    final cleanDestination = destination.trim().toUpperCase();
    
    // Find indices using fuzzy matching (handles formatting differences)
    final originIndex = _findStationIndex(cleanOrigin);
    final destIndex = _findStationIndex(cleanDestination);
    
    if (originIndex == -1 || destIndex == -1) {
      // Stations not found
      return 0;
    }
    
    // Calculate KM distance
    final kmTraveled = (originIndex - destIndex).abs();
    
    // Get fare entry for this distance
    final fareEntry = FareTable.getEntryByKm(kmTraveled);
    if (fareEntry == null) return 0;
    
    // Calculate based on passenger type
    final farePerPassenger = 
        passengerType.toLowerCase() == 'regular' ? fareEntry.fare : fareEntry.discount;
    
    return farePerPassenger * quantity;
  }

  /// Find a station index with fuzzy matching to handle formatting differences
  static int _findStationIndex(String stationName) {
    // Normalize the input: replace hyphens with spaces, remove extra spaces
    final normalizedInput = stationName
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Try exact match first after normalization
    for (int i = 0; i < bookingStations.length; i++) {
      final normalizedStation = bookingStations[i]
          .replaceAll('-', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (normalizedStation == normalizedInput) {
        return i;
      }
    }
    
    // Try partial/substring matches for partial station names
    // e.g., "BATANGAS TERMINAL" should match "BATANGAS GRAND TERMINAL"
    for (int i = 0; i < bookingStations.length; i++) {
      final normalizedStation = bookingStations[i]
          .replaceAll('-', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toUpperCase();
      
      // Check if the station contains all the words from the input
      final inputWords = normalizedInput.split(' ');
      bool allWordsMatch = true;
      for (var word in inputWords) {
        if (word.isNotEmpty && !normalizedStation.contains(word)) {
          allWordsMatch = false;
          break;
        }
      }
      
      if (allWordsMatch && inputWords.isNotEmpty) {
        return i;
      }
    }
    
    // No match found
    return -1;
  }
}
