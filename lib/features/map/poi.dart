import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Orte auf der Karte (Issue #12): Einkehr, Wasser, Rad-Service und
/// Sonstiges aus OpenStreetMap, abgefragt über die Overpass-API.
///
/// Reine Daten und reine Funktionen — Abfrage bauen, Antwort lesen,
/// Raster rechnen. Das Netz steckt in `poi_source.dart`, die Anzeige in
/// `poi_layer.dart`.

/// Die Gruppen, die man im Filter an- und ausschaltet.
enum PoiGroup {
  food('Einkehr', 'Café, Biergarten, Hütte, Gasthaus', Color(0xFF8D5524)),
  water('Wasser', 'Trinkwasser, Wasserstellen, Quellen', Color(0xFF0277BD)),
  bikeService('Rad-Service', 'Reparaturstation, Radladen, E-Bike-Laden',
      Color(0xFF455A64)),
  other('Sonstiges', 'Unterstand, Toilette, Aussichtspunkt, Parkplatz',
      Color(0xFF6D4C9F));

  const PoiGroup(this.label, this.examples, this.color);

  final String label;
  final String examples;

  /// Die Farbe der Stecknadel. Bewusst keine der Trail-Farben (Grün,
  /// Blau, Orange): Die sagen auf dieser Karte, was ICH mit einem Trail
  /// zu tun habe, und ein Ort soll nie wie ein Trail aussehen.
  final Color color;

  /// Beim ersten Start: nur Wasser (Entscheidung des Betreibers) — das,
  /// was man unterwegs am ehesten sucht, ohne die Karte in der Stadt mit
  /// Gasthäusern zu fluten.
  static const initial = {PoiGroup.water};
}

/// Was ein Ort ist. Die Reihenfolge zählt: Ein Objekt mit mehreren
/// passenden Merkmalen bekommt die ERSTE passende Art.
enum PoiKind {
  cafe(PoiGroup.food, 'Café', Icons.cake, 'amenity', 'cafe'),
  biergarten(PoiGroup.food, 'Biergarten', Icons.sports_bar, 'amenity',
      'biergarten'),
  pub(PoiGroup.food, 'Kneipe', Icons.sports_bar, 'amenity', 'pub'),
  restaurant(PoiGroup.food, 'Gasthaus', Icons.restaurant, 'amenity',
      'restaurant'),
  hut(PoiGroup.food, 'Hütte', Icons.cabin, 'tourism', 'alpine_hut'),
  drinkingWater(PoiGroup.water, 'Trinkwasser', Icons.water_drop, 'amenity',
      'drinking_water'),
  waterPoint(PoiGroup.water, 'Wasserstelle', Icons.water_drop, 'amenity',
      'water_point'),
  spring(PoiGroup.water, 'Quelle', Icons.water, 'natural', 'spring'),
  repairStation(PoiGroup.bikeService, 'Reparaturstation', Icons.build,
      'amenity', 'bicycle_repair_station'),
  bikeShop(PoiGroup.bikeService, 'Radladen', Icons.pedal_bike, 'shop',
      'bicycle'),
  // Ladesäulen gibt es an jedem Supermarkt — hier nur die fürs Rad.
  eBikeCharging(PoiGroup.bikeService, 'E-Bike-Ladestation',
      Icons.electric_bike, 'amenity', 'charging_station',
      extra: {'bicycle': 'yes'}),
  shelter(PoiGroup.other, 'Unterstand', Icons.roofing, 'amenity', 'shelter'),
  toilets(PoiGroup.other, 'Toilette', Icons.wc, 'amenity', 'toilets'),
  viewpoint(PoiGroup.other, 'Aussichtspunkt', Icons.landscape, 'tourism',
      'viewpoint'),
  // Private Parkplätze (Firmen, Anwohner) helfen niemandem.
  parking(PoiGroup.other, 'Parkplatz', Icons.local_parking, 'amenity',
      'parking',
      excludeAccess: true);

  const PoiKind(this.group, this.label, this.icon, this.key, this.value,
      {this.extra = const {}, this.excludeAccess = false});

  final PoiGroup group;
  final String label;
  final IconData icon;
  final String key;
  final String value;
  final Map<String, String> extra;
  final bool excludeAccess;

  bool matches(Map<String, String> tags) {
    if (tags[key] != value) return false;
    for (final e in extra.entries) {
      if (tags[e.key] != e.value) return false;
    }
    if (excludeAccess && _closedAccess.contains(tags['access'])) return false;
    return true;
  }

  /// Der Overpass-Filter für diese Art, ohne Rahmen (der steht global).
  String get selector {
    final b = StringBuffer('nwr["$key"="$value"]');
    for (final e in extra.entries) {
      b.write('["${e.key}"="${e.value}"]');
    }
    if (excludeAccess) b.write('["access"!~"^(private|no)\$"]');
    return b.toString();
  }

  static PoiKind? of(Map<String, String> tags) {
    for (final k in values) {
      if (k.matches(tags)) return k;
    }
    return null;
  }
}

const _closedAccess = {'private', 'no'};

/// Ein Ort, so weit die Anzeige ihn braucht.
class Poi {
  const Poi({
    required this.id,
    required this.kind,
    required this.position,
    this.name,
    this.openingHours,
    this.drinkable,
  });

  /// `node/123`, `way/456` — zugleich der Pfad auf openstreetmap.org.
  final String id;
  final PoiKind kind;
  final LatLng position;
  final String? name;
  final String? openingHours;

  /// `drinking_water=yes/no` aus OSM, sonst null. Eine Quelle ist nicht
  /// von selbst Trinkwasser — das Blatt sagt es dazu.
  final bool? drinkable;

  PoiGroup get group => kind.group;
}

/// Unterhalb dieser Zoomstufe fragt die Karte nicht an und zeigt nichts:
/// Ein Ausschnitt über halb Bayern wäre eine Abfrage über zehntausende
/// Orte, und lesbar wären sie ohnehin nicht.
const kPoiMinZoom = 12.0;

/// Höchstens so viele Orte je Abfrage — schützt Speicher und Karte, wenn
/// jemand in der Stadt „Einkehr" einschaltet.
const kPoiMaxResults = 3000;

/// Höchstens so viele Rasterzellen in einer Abfrage. Ein Tablet quer auf
/// Zoom 12 braucht etwa neun; mehr heißt, es wird gerade herausgezoomt.
const kPoiMaxCells = 16;

// Das Raster, in dem geladen und gemerkt wird: 0,1° × 0,15°, in
// Mitteleuropa etwa 11 × 11 km. Fest statt am Ausschnitt ausgerichtet,
// damit Verschieben nicht jedes Mal neu fragt.
const _cellLat = 0.1;
const _cellLon = 0.15;

/// Eine Rasterzelle, als `"zeile,spalte"`.
typedef PoiCell = String;

PoiCell poiCellOf(LatLng p) =>
    '${(p.latitude / _cellLat).floor()},${(p.longitude / _cellLon).floor()}';

/// Alle Zellen, die das Rechteck berühren (Süden, Westen, Norden, Osten).
List<PoiCell> poiCellsCovering(double s, double w, double n, double e) {
  final r0 = (s / _cellLat).floor(), r1 = (n / _cellLat).floor();
  final c0 = (w / _cellLon).floor(), c1 = (e / _cellLon).floor();
  return [
    for (var r = r0; r <= r1; r++)
      for (var c = c0; c <= c1; c++) '$r,$c',
  ];
}

/// Der Rahmen um eine Menge Zellen: (Süden, Westen, Norden, Osten).
({double s, double w, double n, double e}) poiCellsBounds(
    Iterable<PoiCell> cells) {
  var r0 = 1 << 30, r1 = -(1 << 30), c0 = 1 << 30, c1 = -(1 << 30);
  for (final cell in cells) {
    final parts = cell.split(',');
    final r = int.parse(parts[0]), c = int.parse(parts[1]);
    r0 = math.min(r0, r);
    r1 = math.max(r1, r);
    c0 = math.min(c0, c);
    c1 = math.max(c1, c);
  }
  return (
    s: r0 * _cellLat,
    w: c0 * _cellLon,
    n: (r1 + 1) * _cellLat,
    e: (c1 + 1) * _cellLon,
  );
}

/// Die Overpass-Abfrage für die Gruppen im Rahmen. `out center` gibt
/// Flächen (Biergärten, Parkplätze) als Mittelpunkt zurück.
String overpassQuery(
    ({double s, double w, double n, double e}) box, Set<PoiGroup> groups) {
  String f(double v) => v.toStringAsFixed(5);
  final bbox = '${f(box.s)},${f(box.w)},${f(box.n)},${f(box.e)}';
  final selectors = [
    for (final k in PoiKind.values)
      if (groups.contains(k.group)) '${k.selector};',
  ];
  return '[out:json][timeout:25][bbox:$bbox];'
      '(${selectors.join()});'
      'out center $kPoiMaxResults;';
}

/// Liest eine Overpass-Antwort. Was keiner Art zugeordnet werden kann
/// oder keine Lage hat, fällt still heraus.
List<Poi> parseOverpass(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  final out = <Poi>[];
  for (final el in (json['elements'] as List? ?? const [])) {
    if (el is! Map<String, dynamic>) continue;
    final rawTags = el['tags'];
    if (rawTags is! Map) continue;
    final tags = {
      for (final e in rawTags.entries) '${e.key}': '${e.value}',
    };
    final kind = PoiKind.of(tags);
    if (kind == null) continue;
    final center = el['center'];
    final lat = (el['lat'] ?? (center is Map ? center['lat'] : null)) as num?;
    final lon = (el['lon'] ?? (center is Map ? center['lon'] : null)) as num?;
    if (lat == null || lon == null) continue;
    final dw = tags['drinking_water'];
    out.add(Poi(
      id: '${el['type']}/${el['id']}',
      kind: kind,
      position: LatLng(lat.toDouble(), lon.toDouble()),
      name: tags['name'],
      openingHours: tags['opening_hours'],
      drinkable: dw == 'yes' ? true : (dw == 'no' ? false : null),
    ));
  }
  return out;
}
