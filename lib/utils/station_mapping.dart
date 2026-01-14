/// Station Mapping
/// Maps generic "Station N" identifiers to actual place names used in the fare table
/// This handles QR codes that use placeholder station numbers instead of place names
library;

final Map<String, String> stationMapping = {
  'Station 1': 'BATANGAS TERMINAL',
  'Station 2': 'BOLBOK',
  'Station 3': 'STA. RITA',
  'Station 4': 'STA. RITA',
  'Station 5': 'STA. RITA',
  'Station 6': 'SAN PASCUAL',
  'Station 7': 'SAN PASCUAL',
  'Station 8': 'BAUAN',
  'Station 9': 'BALAYONG',
  'Station 10': 'AS-IS',
  'Station 11': 'CUPANG',
  'Station 12': 'MUZON',
  'Station 13': 'STA.TERESITA',
  'Station 14': 'TAWILISAN',
  'Station 15': 'TAAL',
  'Station 16': 'TAAL',
  'Station 17': 'LEMERY XENTRO MALL',
  'Station 18': 'TUBIGAN',
  'Station 19': 'MAHAYAHAY',
  'Station 20': 'SINISIAN',
  'Station 21': 'SINISIAN',
  'Station 22': 'CALACA/BAYAN',
  'Station 23': 'CALACA/BAYAN',
  'Station 24': 'CALACA/BAYAN',
  'Station 25': 'SAMPAGA',
  'Station 26': 'CAYBUNGA',
  'Station 27': 'BALAYAN',
  'Station 28': 'BALAYAN',
  'Station 29': 'GUINHAWA',
  'Station 30': 'PUTOL',
  'Station 31': 'TUY',
  'Station 32': 'TUY',
  'Station 33': 'TUY',
  'Station 34': 'TUY',
  'Station 35': 'BILARAN',
  'Station 36': 'IRRIGATION',
  'Station 37': 'NASUGBU',
  'Station 38': 'NASUGBU',
  'Station 39': 'NASUGBU',
  'Station 40': 'NASUGBU',
  'Station 41': 'NASUGBU',
  'Station 42': 'NASUGBU',
  'Station 43': 'NASUGBU',
};

/// Resolve station name from either direct place name or Station N format
String resolveStationName(String input) {
  final trimmed = input.trim();
  
  // Check if it's a "Station N" format
  if (trimmed.toLowerCase().startsWith('station ')) {
    return stationMapping[trimmed] ?? trimmed;
  }
  
  // Otherwise, return as-is (assume it's already a place name)
  return trimmed;
}
