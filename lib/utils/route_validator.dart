/// Route Validator
/// Provides direction-aware validation for passenger routes based on the master station list.
/// The list is ordered from Nasugbu Terminal → Batangas Grand Terminal.
/// For South routes, the list is reversed automatically.
library;

class RouteValidator {
  /// Master station list ordered from Nasugbu → Batangas Grand Terminal
  /// Based on the official booking system station list
  static const List<String> northStations = [
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
    'BRGY HALL/WAITING SHED SAMPAGA',
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
    'STA. RITA BRGY. HALL COMPLEX',
    'COMPLEX',
    'DIVERSION NTC',
    'BATANGAS GRAND TERMINAL',
  ];

  /// Get the appropriate station list for the given route direction
  /// North (Nasugbu → Batangas): use northStations as-is
  /// South (Batangas → Nasugbu): use northStations reversed
  static List<String> getStationListForDirection(String direction) {
    final dir = direction.toLowerCase().trim();
    if (dir == 'north' || dir == 'north_to_south') {
      return northStations;
    } else if (dir == 'south' || dir == 'south_to_north') {
      return List.from(northStations.reversed);
    }
    // Default to north
    return northStations;
  }

  /// Normalize a station name for comparison
  /// - Strip station number prefixes (e.g., "1. Nasugbu" → "Nasugbu")
  /// - Convert to uppercase
  /// - Remove extra whitespace
  /// - Handle common abbreviations/typos
  static String normalizeStationName(String name) {
    var normalized = name.trim();
    
    // Remove station number prefix (e.g., "1. Nasugbu Terminal" → "Nasugbu Terminal")
    normalized = normalized.replaceAll(RegExp(r'^\d+\.\s*'), '');
    
    normalized = normalized.toUpperCase();
    
    // Remove punctuation (dots, slashes, commas, parentheses, etc.) to normalize variants
    normalized = normalized.replaceAll(RegExp(r'[\p{P}\p{S}]', unicode: true), '');

    // Remove extra whitespace
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    
    // Handle common aliases/variations
    final aliases = {
      'NASUGBU': 'NASUGBU TERMINAL',
      'BATANGAS': 'BATANGAS GRAND TERMINAL',
      'BATANGAS TERMINAL': 'BATANGAS GRAND TERMINAL',
      'BATANGAS GRAND': 'BATANGAS GRAND TERMINAL',
      'IRRIGATION': 'IRRIGATION WAITING SHED/TODA',
      'PALICO': 'PALICO TERMINAL',
      'PAHINANTE': 'PAHINANTE WAITING SHED',
      'BILARAN': 'BILARAN ELEM SCHOOL WAITING SHED',
      'LANATAN': 'BRGY. HALL LANATAN',
      'SAMPAGA': 'BRGY HALL/WAITING SHED SAMPAGA',
      'CALACA': 'ROBINSONS CALACA/BAYAN',
      'TAAL': 'JOLLIBEE TAAL',
      'BULI': 'BULI BRGY. HALL',
      'TAWILISAN': 'TAWILISAN 7 11',
      'MAHAYAHAY': 'MAHAYAHAY 7 11',
      'MATAAS': 'MATAAS NA BAYAN BRGY. HALL',
    };
    
    if (aliases.containsKey(normalized)) {
      return aliases[normalized]!;
    }
    
    return normalized;
  }

  /// Extract the place name from a full station description
  /// e.g., "BRGY. HALL LANATAN" → "LANATAN", "MAHAYAHAY 7 11" → "MAHAYAHAY"
  static String extractPlaceName(String station) {
    const descriptors = [
      'BRGY. HALL', 'BRGY HALL', 'WAITING SHED', 'ELEM SCHOOL', 'SCHOOL',
      'TERMINAL', 'SHED', 'CHURCH', 'INTERSECTION', 'MALL', 'FUEL',
      'GAS STATION', 'CLEAN FUEL', 'FOOD HOUSE', 'ICE PLANT', 'DEPOT',
      'XENTRO', 'TEA PROJECT', 'COMPLEX', 'STATION', 'PROJECT',
    ];
    
    var name = station.trim().toUpperCase();
    name = name.replaceAll(RegExp(r'^\d+\.\s*'), ''); // Remove number prefix
    
    // Remove known descriptors from start and end
    for (final desc in descriptors) {
      name = name.replaceAll(RegExp('^$desc\\s*'), '');
      name = name.replaceAll(RegExp('\\s*$desc\$'), '');
    }
    
    // Remove extra spaces and slashes
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    name = name.replaceAll(RegExp(r'/.*$'), ''); // Remove everything after /
    
    return name.isNotEmpty ? name : station.trim();
  }

  /// Find the index of a station in the given direction list
  /// Returns -1 if not found
  static int findStationIndex(String stationName, List<String> directionList) {
    final normalized = normalizeStationName(stationName);
    
    for (int i = 0; i < directionList.length; i++) {
      if (normalizeStationName(directionList[i]) == normalized) {
        return i;
      }
    }
    
    return -1;
  }

  /// Validate a route in a given direction
  /// Returns a ValidationResult with isValid and message
  static ValidationResult validateRoute(
    String origin,
    String destination,
    String routeDirection,
  ) {
    final stationList = getStationListForDirection(routeDirection);
    
    final originIndex = findStationIndex(origin, stationList);
    final destIndex = findStationIndex(destination, stationList);
    
    // Check if both stations exist
    if (originIndex == -1 || destIndex == -1) {
      // Use extracted place names for error display
      final originPlace = extractPlaceName(origin);
      final destPlace = extractPlaceName(destination);
      return ValidationResult(
        isValid: false,
        message: 'Invalid passenger route:\n$originPlace → $destPlace\n\nPassenger boarded the wrong bus or selected an invalid route.',
        errorType: 'OUT_OF_ROUTE',
      );
    }
    
    // Check if origin comes before destination
    if (originIndex >= destIndex) {
      // Use extracted place names for error display
      final originPlace = extractPlaceName(origin);
      final destPlace = extractPlaceName(destination);
      return ValidationResult(
        isValid: false,
        message: 'Invalid passenger route:\n$originPlace → $destPlace\n\nPassenger boarded the wrong bus or selected an invalid route.',
        errorType: 'OUT_OF_ROUTE',
      );
    }
    
    return ValidationResult(
      isValid: true,
      message: 'Route validated.',
    );
  }
}

/// Validation result object
class ValidationResult {
  final bool isValid;
  final String message;
  final String? errorType; // 'OUT_OF_ROUTE', null if valid

  ValidationResult({
    required this.isValid,
    required this.message,
    this.errorType,
  });
}
