// station_registry.dart
// Phase 1: Station coordinate registry for GPS-assisted on-board count.
// Source: "For POS - STATION Coordinates.txt"
// Route: Nasugbu Terminal → Batangas Grand Terminal (north_to_south, index 0→55)
//        Batangas Grand Terminal → Nasugbu Terminal (south_to_north, reversed)

class StationCoordinate {
  final int routeOrder; // 0-based, north-to-south direction
  final String name;
  final double latitude;
  final double longitude;

  const StationCoordinate({
    required this.routeOrder,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class StationRegistry {
  StationRegistry._();

  /// All stations in north-to-south order (index 0 = Nasugbu Terminal).
  static const List<StationCoordinate> stations = [
    StationCoordinate(routeOrder: 0,  name: 'Nasugbu Terminal',                     latitude: 14.073070458681942, longitude: 120.63197559155604),
    StationCoordinate(routeOrder: 1,  name: 'Lian shed',                            latitude: 14.055141972114212, longitude: 120.64694459997712),
    StationCoordinate(routeOrder: 2,  name: 'Sagbat',                               latitude: 14.051181364285101, longitude: 120.65056155068831),
    StationCoordinate(routeOrder: 3,  name: 'Central',                              latitude: 14.051671656948882, longitude: 120.66409464836671),
    StationCoordinate(routeOrder: 4,  name: 'Irrigation Waiting Shed/Toda',         latitude: 14.052371960697128, longitude: 120.67404736801211),
    StationCoordinate(routeOrder: 5,  name: 'Bilaran Elem School Waiting Shed',     latitude: 14.050325693249619, longitude: 120.68071010871739),
    StationCoordinate(routeOrder: 6,  name: 'Palico Terminal',                      latitude: 14.048426781937678, longitude: 120.69883857896765),
    StationCoordinate(routeOrder: 7,  name: 'Pahinante Waiting Shed',              latitude: 14.043049913732013, longitude: 120.70308067244765),
    StationCoordinate(routeOrder: 8,  name: 'Luntal Waiting Shed',                  latitude: 14.031394102395180, longitude: 120.71275544032837),
    StationCoordinate(routeOrder: 9,  name: 'Talon Waiting Shed',                   latitude: 14.026081284209397, longitude: 120.72139065108155),
    StationCoordinate(routeOrder: 10, name: 'Tuy',                                  latitude: 14.009062245387963, longitude: 120.72861592851156),
    StationCoordinate(routeOrder: 11, name: 'Kingdom Hall of Jehovah\'s Witnessess',latitude: 14.000183118247508, longitude: 120.72972547681276),
    StationCoordinate(routeOrder: 12, name: 'Brgy Putol Waiting shed',              latitude: 13.986315095838615, longitude: 120.72712630818391),
    StationCoordinate(routeOrder: 13, name: 'Brgy Guinhawa Waiting shed',           latitude: 13.982302894957925, longitude: 120.72673835294088),
    StationCoordinate(routeOrder: 14, name: 'Flying V Munting Tubig',               latitude: 13.965007353989503, longitude: 120.72714320428967),
    StationCoordinate(routeOrder: 15, name: 'Brgy Hall Lanatan',                    latitude: 13.963275786806083, longitude: 120.72721153897410),
    StationCoordinate(routeOrder: 16, name: 'Waltermart',                           latitude: 13.949491719185836, longitude: 120.73031370215853),
    StationCoordinate(routeOrder: 17, name: 'Spyder Fuel Gumamela',                 latitude: 13.945509543108338, longitude: 120.74354169000694),
    StationCoordinate(routeOrder: 18, name: 'Brgy Hall Langgangan',                 latitude: 13.945257516211425, longitude: 120.75249845996632),
    StationCoordinate(routeOrder: 19, name: 'Alfamart Caybunga',                    latitude: 13.944842302437898, longitude: 120.76111976741765),
    StationCoordinate(routeOrder: 20, name: 'Brgy Hall/Waiting shed Sampaga',       latitude: 13.941221402150230, longitude: 120.77026110265585),
    StationCoordinate(routeOrder: 21, name: 'Dacanlao Waiting shed',                latitude: 13.939838706375197, longitude: 120.79121121908840),
    StationCoordinate(routeOrder: 22, name: 'Alfamart Pantay',                      latitude: 13.938470847956518, longitude: 120.79772432529735),
    StationCoordinate(routeOrder: 23, name: 'Robinsons Calaca Bayan',               latitude: 13.927983343747824, longitude: 120.81126594141516),
    StationCoordinate(routeOrder: 24, name: 'Flamingo Gas Station Salong',          latitude: 13.926057914919943, longitude: 120.81801002263529),
    StationCoordinate(routeOrder: 25, name: 'Puting Bato Calaca',                   latitude: 13.919475007068742, longitude: 120.83729469150717),
    StationCoordinate(routeOrder: 26, name: 'Sinisian Elem School',                 latitude: 13.914286671945037, longitude: 120.84451201279838),
    StationCoordinate(routeOrder: 27, name: 'Sinisian Elem School - Lemery',        latitude: 13.910160448688467, longitude: 120.85966656207862),
    StationCoordinate(routeOrder: 28, name: 'Mataas na bayan Brgy. Hall',           latitude: 13.911763963226953, longitude: 120.86798416696558),
    StationCoordinate(routeOrder: 29, name: 'Mahayahay 7 11',                       latitude: 13.912974994235583, longitude: 120.87856616136365),
    StationCoordinate(routeOrder: 30, name: 'Matingain Mahal na Poon',              latitude: 13.907353859158965, longitude: 120.88904776713045),
    StationCoordinate(routeOrder: 31, name: 'Bukal The Black Tea Project',          latitude: 13.907601644260248, longitude: 120.89049789596605),
    StationCoordinate(routeOrder: 32, name: 'Tubigan Ice Plant',                    latitude: 13.904743493372923, longitude: 120.89486589093401),
    StationCoordinate(routeOrder: 33, name: 'Malinis Wilcon Depot',                 latitude: 13.902158082537033, longitude: 120.89827272207334),
    StationCoordinate(routeOrder: 34, name: 'Xentro Mall Caltex',                   latitude: 13.897208453249082, longitude: 120.90428285335514),
    StationCoordinate(routeOrder: 35, name: 'Laguile Food House',                   latitude: 13.897077993269678, longitude: 120.91545879220234),
    StationCoordinate(routeOrder: 36, name: 'Halang Flying V',                      latitude: 13.895711487650441, longitude: 120.92673462480163),
    StationCoordinate(routeOrder: 37, name: 'Latag Waiting Shed',                   latitude: 13.892805000000000, longitude: 120.93017510000000),
    StationCoordinate(routeOrder: 38, name: 'Tulo Waiting Shed',                    latitude: 13.887144900000000, longitude: 120.93905900000000),
    StationCoordinate(routeOrder: 39, name: 'Jolibee Taal',                         latitude: 13.884018893687000, longitude: 120.94425665108648),
    StationCoordinate(routeOrder: 40, name: 'Buli Brgy. Hall',                      latitude: 13.883351019393007, longitude: 120.95307925108628),
    StationCoordinate(routeOrder: 41, name: 'Tawilisam 7 11',                       latitude: 13.880775319655388, longitude: 120.96445856345854),
    StationCoordinate(routeOrder: 42, name: 'Mohon Elem School',                    latitude: 13.878759549055012, longitude: 120.96681811244726),
    StationCoordinate(routeOrder: 43, name: 'Sta. Teresita Church',                 latitude: 13.870934484302700, longitude: 120.97758098176469),
    StationCoordinate(routeOrder: 44, name: 'San Luis Intersection',                latitude: 13.861983900000000, longitude: 120.98459560000000),
    StationCoordinate(routeOrder: 45, name: 'Muzon',                                latitude: 13.854885053125715, longitude: 120.98846460505910),
    StationCoordinate(routeOrder: 46, name: 'Cupang Waiting Shed/ School',          latitude: 13.836799400000000, longitude: 120.99332850000000),
    StationCoordinate(routeOrder: 47, name: 'As-Is Brgy. Hall',                     latitude: 13.824413888154169, longitude: 120.99330737765712),
    StationCoordinate(routeOrder: 48, name: 'Balayong Clean Fuel',                  latitude: 13.812388596451019, longitude: 120.99568647270985),
    StationCoordinate(routeOrder: 49, name: 'Manghinao',                            latitude: 13.796396207586719, longitude: 121.00030099274306),
    StationCoordinate(routeOrder: 50, name: 'Bauan BPI',                            latitude: 13.792573554358533, longitude: 121.00720503320959),
    StationCoordinate(routeOrder: 51, name: 'San Pascual',                          latitude: 13.788683516611012, longitude: 121.02009513643017),
    StationCoordinate(routeOrder: 52, name: 'Sta. Rita Brgy. Hall',                 latitude: 13.780134444112546, longitude: 121.03914215995678),
    StationCoordinate(routeOrder: 53, name: 'Complex',                              latitude: 13.775754457026675, longitude: 121.04476499533557),
    StationCoordinate(routeOrder: 54, name: 'Diversion NTC',                        latitude: 13.772001556832095, longitude: 121.05148179957962),
    StationCoordinate(routeOrder: 55, name: 'Batangas Grand Terminal',              latitude: 13.790663174402377, longitude: 121.06168415902447),
  ];

  /// Total number of stations on the route.
  static int get count => stations.length;

  /// Get station by 0-based route order.
  static StationCoordinate? byOrder(int order) {
    if (order < 0 || order >= stations.length) return null;
    return stations[order];
  }

  /// Haversine distance in metres between two lat/lng pairs.
  static double haversineMetres(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const r = 6371000.0; // Earth radius in metres
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = _sin2(dLat / 2) +
        _cos(_deg2rad(lat1)) * _cos(_deg2rad(lat2)) * _sin2(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return r * c;
  }

  // --- trig helpers (avoid dart:math import at package level) ---
  static double _deg2rad(double d) => d * 3.141592653589793 / 180.0;
  static double _sin2(double x) {
    final s = _sin(x);
    return s * s;
  }

  static double _sin(double x) {
    // Taylor series good enough for small angles; use dart:math via indirect.
    // Actually just use the real dart:math — importing it here is fine.
    return _mathSin(x);
  }

  static double _cos(double x) => _mathCos(x);
  static double _sqrt(double x) => _mathSqrt(x > 0 ? x : 0);
  static double _atan2(double y, double x) => _mathAtan2(y, x);

  // Delegate to dart:math via top-level functions.
  static double _mathSin(double x) {
    // inline via dart math
    var s = 0.0;
    var term = x;
    var sign = 1.0;
    for (var n = 1; n <= 15; n += 2) {
      s += sign * term;
      sign = -sign;
      term *= x * x / ((n + 1) * (n + 2));
    }
    return s;
  }

  static double _mathCos(double x) => _mathSin(x + 1.5707963267948966);

  static double _mathSqrt(double x) {
    if (x == 0) return 0;
    var r = x;
    for (var i = 0; i < 20; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }

  static double _mathAtan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 1.5707963267948966;
    if (x == 0 && y < 0) return -1.5707963267948966;
    return 0.0;
  }

  static double _atan(double x) {
    // Abramowitz & Stegun approximation
    const a1 = 0.99997726;
    const a3 = -0.33262347;
    const a5 = 0.19354346;
    const a7 = -0.11643287;
    const a9 = 0.05265332;
    const a11 = -0.01172120;
    final x2 = x * x;
    return x * (a1 + x2 * (a3 + x2 * (a5 + x2 * (a7 + x2 * (a9 + x2 * a11)))));
  }
}
