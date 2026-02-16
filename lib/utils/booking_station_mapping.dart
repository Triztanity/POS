/// Booking Station Mapping
/// Maps the station names from the booking system QR codes to the RouteValidator station names
class BookingStationMapping {
  /// Maps booking system station names to RouteValidator stations
  /// The booking system uses the same names as RouteValidator now
  static const Map<String, String> bookingToRouteValidator = {
    // Stations 1-5
    'NASUGBU': 'NASUGBU TERMINAL',
    'LIAN': 'LIAN SHED',
    'SAGBAT': 'SAGBAT',
    'CENTRAL': 'CENTRAL',
    'IRRIGATION': 'IRRIGATION WAITING SHED/TODA',
    
    // Stations 6-10
    'BILARAN': 'BILARAN ELEM SCHOOL WAITING SHED',
    'PALICO': 'PALICO TERMINAL',
    'PAHINANTE': 'PAHINANTE WAITING SHED',
    'LUNTAL': 'LUNTAL WAITING SHED',
    'TALON': 'TALON WAITING SHED',
    
    // Stations 11-15
    'TUY': 'TUY',
    'OBISPO': 'OBISPO',
    'PUTOL': 'BRGY PUTOL WAITING SHED',
    'GUINHAWA': 'BRGY GUINHAWA WAITING SHED',
    'MUNTING TUBIG': 'FLYING V MUNTING TUBIG',
    
    // Stations 16-20
    'LANATAN': 'BRGY HALL LANATAN',
    'BALAYAN': 'BALAYAN WALTERMART',
    'GUMAMELA': 'SPYDER FUEL GUMAMELA',
    'GIMALAS': 'GIMALAS',
    'CAYBUNGA': 'ALFAMART CAYBUNGA',
    
    // Stations 21-25
    'SAMPAGA': 'BRGY HALL/WAITING SHED SAMPAGA',
    'DACANLAO': 'DACANLAO WAITING SHED',
    'PAG-ASA/PANTAY': 'ALFAMART PANTAY',
    'CALACA/BAYAN': 'ROBINSONS CALACA/BAYAN',
    'SALONG': 'FLAMINGO GAS STATION SALONG',
    
    // Stations 26-30
    'PUTING BATO': 'PUTING BATO CALACA',
    'SINISIAN': 'SINISIAN ELEM SCHOOL',
    'MATAAS NA BAYAN': 'MATAAS NA BAYAN BRGY. HALL',
    'MAHAYAHAY': 'MAHAYAHAY 7 11',
    'MATINGAIN': 'MATINGAIN MALL NA POON',
    
    // Stations 31-35
    'BUKAL': 'BUKAL THE BLACK TEA PROJECT',
    'TUBIGAN': 'TUBIGAN ICE PLANT',
    'MALINIS': 'MALINIS WILCON DEPOT',
    'LEMERY XENTRO MALL': 'LEMERY XENTRO MALL',
    'LAGUILE': 'LAGUILE FOOD HOUSE',
    
    // Stations 36-40
    'HALANG': 'HALANG FLYING V',
    'LATAG': 'LATAG WAITING SHED',
    'TULO': 'TULO WAITING SHED',
    'JOLLIBEE TAAL': 'JOLLIBEE TAAL',
    'BULI': 'BULI BRGY. HALL',
    
    // Stations 41-45
    'TAWILISAN': 'TAWILISAN 7 11',
    'MOHON': 'MOHON ELEM SCHOOL',
    'STA. TERESITA': 'STA. TERESITA CHURCH',
    'SAN LUIS': 'SAN LUIS INTERSECTION',
    'MUZON': 'MUZON',
    'CUPANG': 'CUPANG WAITING SHED/ SCHOOL',
    'AS-IS': 'AS-IS BRGY. HALL',
    'AS IS': 'AS-IS BRGY. HALL',
    'BALAYONG': 'BALAYONG CLEAN FUEL',
    'MANGHINAO': 'MANGHINAO',
    'BAUAN': 'CITIMART BAUAN',
    'DIVERSION': 'DIVERSION NTC',
    'STA RITA': 'STA. RITA BRGY. HALL',
    'STA. RITA': 'STA. RITA BRGY. HALL',
  };

  /// Resolve a booking system station name to the RouteValidator station name
  static String resolveStation(String bookingStation) {
    final cleaned = bookingStation.trim().toUpperCase();
    
    // Try exact match first
    if (bookingToRouteValidator.containsKey(cleaned)) {
      return bookingToRouteValidator[cleaned]!;
    }
    
    // If not found, return the cleaned name as-is
    // Most names should match directly now since they're standardized
    return cleaned;
  }
}
