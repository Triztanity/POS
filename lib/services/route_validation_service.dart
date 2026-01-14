/// Central station list in route sequence order (Nasugbu Terminal → Batangas Terminal).
/// This is the canonical order used for all route validation.
class RouteValidationService {
  static const List<String> stationSequence = [
    'Nasugbu Terminal',
    'Lian Shed',
    'Sagbat',
    'Central',
    'Irrigation Waiting Shed/Toda',
    'Bilaran Elem School Waiting Shed',
    'Palico Terminal',
    'Pahinante Waiting Shed',
    'Luntal Waiting Shed',
    'Talon Waiting Shed',
    'Tuy',
    'Obispo',
    'Brgy Putol Waiting Shed',
    'Brgy Guinhawa Waiting Shed',
    'Flying V Munting Tubig',
    'Brgy. Hall Lanatan',
    'Balayan Waltermart',
    'Spyder Fuel Gumamela',
    'Gimalas',
    'Alfamart Caybunga',
    'Brgy. Hall/Waiting Shed Sampaga',
    'Dacanlao Waiting Shed',
    'Alfamart Pantay',
    'Robinsons Calaca/Bayan',
    'Flamingo Gas Station Salong',
    'Puting Bato Calaca',
    'Sinisian Elem. School',
    'Mataas na Bayan Brgy. Hall',
    'Mahayahay 7 11',
    'Matingain Mahal na Poon',
    'Bukal The Black Tea Project',
    'Tubigan Ice Plant',
    'Malinis Wilcon Depot',
    'Lemery Xentro Mall',
    'Laguile Food House',
    'Halang Flying V',
    'Latag Waiting Shed',
    'Tulo Waiting Shed',
    'Jollibee Taal',
    'Buli Brgy. Hall',
    'Tawilisan 7 11',
    'Mohon Elem School',
    'Sta. Teresita Church',
    'San Luis Intersection',
    'Muzon',
    'Cupang Waiting Shed / School',
    'As-Is Brgy. Hall',
    'Balayong Clean Fuel',
    'Manghinao',
    'Citimart Bauan',
    'San Antonio',
    'San Pascual',
    'Sta. Rita Brgy. Hall',
    'Complex',
    'Diversion NTC',
    'Batangas Terminal',
  ];

  /// Normalize station names: trim, lowercase, remove extra whitespace.
  /// Used for fuzzy matching against the canonical station list.
  static String _normalizeStationName(String? name) {
    if (name == null) return '';
    return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Find a station's index in the canonical sequence by fuzzy name matching.
  /// Returns the index if found (0-based), or -1 if not found.
  static int getStationIndex(String? stationName) {
    if (stationName == null || stationName.isEmpty) return -1;

    final normalized = _normalizeStationName(stationName);

    // First try exact match (after normalization)
    int exactIndex = stationSequence.indexWhere(
      (s) => _normalizeStationName(s) == normalized,
    );
    if (exactIndex >= 0) return exactIndex;

    // Fallback: substring match (if partial name provided)
    int partialIndex = stationSequence.indexWhere(
      (s) => _normalizeStationName(s).contains(normalized) ||
          normalized.contains(_normalizeStationName(s)),
    );
    return partialIndex >= 0 ? partialIndex : -1;
  }

  /// Validate if the origin and destination follow the correct route direction.
  /// - For 'North': origin index must be < destination index (Nasugbu → Batangas)
  /// - For 'South': origin index must be > destination index (Batangas → Nasugbu)
  /// Returns a ValidationResult with success status and optional error message.
  static ValidationResult validateRouteDirection(
    int originIndex,
    int destinationIndex,
    String routeDirection, // 'North' or 'South' (or 'north_to_south' / 'south_to_north')
  ) {
    // Normalize route direction
    final normalized = routeDirection.toLowerCase();
    final isNorth = normalized == 'north' || normalized == 'north_to_south';

    if (isNorth) {
      // North route: Nasugbu (low index) → Batangas (high index)
      if (originIndex < destinationIndex) {
        return ValidationResult(success: true);
      }
      return ValidationResult(
        success: false,
        message: 'Passenger is out of route and going to the wrong direction',
      );
    } else {
      // South route: Batangas (high index) → Nasugbu (low index)
      if (originIndex > destinationIndex) {
        return ValidationResult(success: true);
      }
      return ValidationResult(
        success: false,
        message: 'Passenger is out of route and going to the wrong direction',
      );
    }
  }

  /// Check if a destination is valid (exists in the destination dropdown).
  /// For now, destinations come from the fare table / home_screen dropdown.
  /// This is a placeholder; in production, this should be populated from
  /// the actual dropdown list used on home_screen.
  static bool isValidDestination(String? destination, List<String> availableDestinations) {
    if (destination == null || destination.isEmpty) return false;
    final norm = _normalizeStationName(destination);
    return availableDestinations.any(
      (d) => _normalizeStationName(d) == norm,
    );
  }
}

/// Result object for route validation.
class ValidationResult {
  final bool success;
  final String? message;

  ValidationResult({required this.success, this.message});
}
