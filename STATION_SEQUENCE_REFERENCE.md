# Station Sequence Reference

**Route Order**: Nasugbu Terminal (Index 0) → Batangas Terminal (Index 53)

## Full Sequence

| Index | Station Name | Index | Station Name |
|-------|--------------|-------|--------------|
| 0 | Nasugbu Terminal | 27 | Sinisian Elem. School |
| 1 | Lian Shed | 28 | Mataas na Bayan Brgy. Hall |
| 2 | Sagbat | 29 | Mahayahay 7 11 |
| 3 | Central | 30 | Matingain Mahal na Poon |
| 4 | Irrigation Waiting Shed/Toda | 31 | Bukal The Black Tea Project |
| 5 | Bilaran Elem School Waiting Shed | 32 | Tubigan Ice Plant |
| 6 | Palico Terminal | 33 | Malinis Wilcon Depot |
| 7 | Pahinante Waiting Shed | 34 | Lemery Xentro Mall |
| 8 | Luntal Waiting Shed | 35 | Laguile Food House |
| 9 | Talon Waiting Shed | 36 | Halang Flying V |
| 10 | Tuy | 37 | Latag Waiting Shed |
| 11 | Obispo | 38 | Tulo Waiting Shed |
| 12 | Brgy Putol Waiting Shed | 39 | Jollibee Taal |
| 13 | Brgy Guinhawa Waiting Shed | 40 | Buli Brgy. Hall |
| 14 | Flying V Munting Tubig | 41 | Tawilisan 7 11 |
| 15 | Brgy. Hall Lanatan | 42 | Mohon Elem School |
| 16 | Balayan Waltermart | 43 | Sta. Teresita Church |
| 17 | Spyder Fuel Gumamela | 44 | San Luis Intersection |
| 18 | Gimalas | 45 | Muzon |
| 19 | Alfamart Caybunga | 46 | Cupang Waiting Shed / School |
| 20 | Brgy. Hall/Waiting Shed Sampaga | 47 | As-Is Brgy. Hall |
| 21 | Dacanlao Waiting Shed | 48 | Balayong Clean Fuel |
| 22 | Alfamart Pantay | 49 | Manghinao |
| 23 | Robinsons Calaca/Bayan | 50 | Citimart Bauan |
| 24 | Flamingo Gas Station Salong | 51 | San Antonio |
| 25 | Puting Bato Calaca | 52 | San Pascual |
| 26 | Robinsons Calaca/Bayan | 53 | Sta. Rita Brgy. Hall / Complex / Batangas Terminal |

## Validation Rules

### North Route (Nasugbu → Batangas)
- Passenger **originIndex < destinationIndex**
- Example: Lian (1) → Batangas Terminal (53) ✓ Valid
- Example: Batangas Terminal (53) → Lian (1) ✗ Invalid

### South Route (Batangas → Nasugbu)
- Passenger **originIndex > destinationIndex**
- Example: Batangas Terminal (53) → Lian (1) ✓ Valid
- Example: Lian (1) → Batangas Terminal (53) ✗ Invalid

## Fuzzy Matching Examples

The system handles common abbreviations:

| User Input | Matched Station | Index |
|------------|-----------------|-------|
| "Nasugbu" | Nasugbu Terminal | 0 |
| "Lian" | Lian Shed | 1 |
| "Palico" | Palico Terminal | 6 |
| "Balayan" | Balayan Waltermart | 16 |
| "Batangas" | Batangas Terminal | 53 |
| "Lemery Xentro" | Lemery Xentro Mall | 34 |
| "Sta Rita" | Sta. Rita Brgy. Hall | 52 |

## FareTable Places (Available Destinations)

These are the valid destinations shown in the home_screen dropdown:

```
NASUGBU, LIAN, SAGBAT, CENTRAL, IRRIGATION, BILARAN,
PALICO, PAHINANTE, LUNTAL, TALON, TUY, OBISPO, PUTOL,
GUINHAWA, MUNTING TUBIG, LANATAN, BALAYAN, GUMAMELA,
GIMALAS, CAYBUNGA, SAMPAGA, DACANLAO, PANTAY, CALACA,
SALONG, PUTING BATO, SINISIAN, MATAAS NA BAYAN,
MAHAYAHAY, MATINGGAIN, BUKAL, TUBIGAN, MALINIS,
LEMERY XENTRO MALL, LAGUILE, HALANG, LATAG, TULO,
JOLLIBEE TAAL, BULI, TAWILISAN, MOHON, STA. TERESITA,
SAN LUIS, MUZON, CUPANG, AS-IS, BALAYONG, MANGHINAO,
BAUAN, SAN ANTONIO, SAN PASCUAL, STA. RITA, COMPLEX,
DIVERSION, BOLBOK, BATANGAS TERMINAL
```

## Route Validation Examples

### North Route (North-to-South)

**Valid Journeys:**
- Nasugbu (0) → Palico (6): 0 < 6 ✓
- Lian (1) → Batangas (53): 1 < 53 ✓
- Tuy (10) → Lemery (34): 10 < 34 ✓

**Invalid Journeys:**
- Palico (6) → Nasugbu (0): 6 > 0 ✗
- Batangas (53) → Lian (1): 53 > 1 ✗
- Lemery (34) → Tuy (10): 34 > 10 ✗

### South Route (South-to-North)

**Valid Journeys:**
- Batangas (53) → Nasugbu (0): 53 > 0 ✓
- Batangas (53) → Lian (1): 53 > 1 ✓
- Lemery (34) → Tuy (10): 34 > 10 ✓

**Invalid Journeys:**
- Nasugbu (0) → Batangas (53): 0 < 53 ✗
- Lian (1) → Batangas (53): 1 < 53 ✗
- Tuy (10) → Lemery (34): 10 < 34 ✗

---

## Usage in Code

```dart
import 'services/route_validation_service.dart';

// Find station index
final originIdx = RouteValidationService.getStationIndex('Lian');    // Returns 1
final destIdx = RouteValidationService.getStationIndex('Palico');   // Returns 6

// Validate North route
final result = RouteValidationService.validateRouteDirection(
  1,      // Origin (Lian)
  6,      // Destination (Palico)
  'North' // Route direction
);
// result.success == true (1 < 6 for North route)

// Validate invalid South route
final result2 = RouteValidationService.validateRouteDirection(
  1,      // Origin (Lian)
  6,      // Destination (Palico)
  'South' // Route direction
);
// result2.success == false (1 < 6 but South route requires 1 > 6)
```

---

**Reference**: QR_VALIDATION_REFACTOR.md  
**Last Updated**: January 5, 2025
