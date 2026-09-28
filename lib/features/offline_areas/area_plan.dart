// Die Planung eines Bereichs (Konzept 3.2), pur: welche Kacheln ein
// Rahmen von Zoom [kAreaMinZoom] bis zum Zoom des Archivs berührt, und
// welche Kachel-Ids das im Archiv sind. Die Größe kommt später aus dem
// Verzeichnis des Archivs (jede Kachel nennt dort ihre Bytes) — hier
// wird nur GEZÄHLT, nicht geschätzt.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart' show ZXY;

/// Unter Zoom 8 liegt die mitgelieferte Übersicht (Zoom 0–7), die hat
/// jedes Gerät. Ein Bereich beginnt darüber.
const kAreaMinZoom = 8;

/// Mehr Kacheln als das speichert die App nicht in EINEM Bereich: Bei
/// Zoom 13 sind das rund 1 000 km × 400 km, weit mehr als ein
/// Wochenende, und die Kachelliste selbst (Nachschlagen jeder Kachel im
/// Verzeichnis) würde spürbar. Wer mehr will, speichert zwei Bereiche.
const kAreaMaxTiles = 40000;

/// Der Rand um „meine Trails" (Konzept 3.2: „ein Rahmen um die eigenen
/// Trails mit Rand").
const kAreaTrailsMarginKm = 2.0;

/// Ein Rahmen in Grad, Süden/Westen/Norden/Osten.
class AreaBounds {
  const AreaBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  /// Um die Punkte, mit [marginKm] Rand. Null ohne Punkte.
  static AreaBounds? around(Iterable<LatLng> points, {double marginKm = kAreaTrailsMarginKm}) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    var any = false;
    for (final p in points) {
      any = true;
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
    if (!any) return null;
    final dLat = marginKm / 111.0;
    final midLat = (s + n) / 2;
    final dLon = marginKm / (111.0 * math.max(0.2, math.cos(midLat * math.pi / 180)));
    return AreaBounds(
      south: math.max(-85.0, s - dLat),
      west: math.max(-180.0, w - dLon),
      north: math.min(85.0, n + dLat),
      east: math.min(180.0, e + dLon),
    );
  }

  bool contains(LatLng p) =>
      p.latitude >= south && p.latitude <= north && p.longitude >= west && p.longitude <= east;

  /// Berührt der Rahmen [other]?
  bool intersects(AreaBounds other) =>
      other.west <= east && other.east >= west && other.south <= north && other.north >= south;

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  Map<String, dynamic> toJson() => {'s': south, 'w': west, 'n': north, 'e': east};

  factory AreaBounds.fromJson(Map<String, dynamic> j) => AreaBounds(
        south: (j['s'] as num).toDouble(),
        west: (j['w'] as num).toDouble(),
        north: (j['n'] as num).toDouble(),
        east: (j['e'] as num).toDouble(),
      );
}

/// Eine Kachel im Web-Mercator-Raster.
typedef TileXYZ = ({int z, int x, int y});

/// Spalte und Zeile der Kachel, in der [lon]/[lat] bei Zoom [z] liegt.
({int x, int y}) tileAt(double lat, double lon, int z) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final latRad = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n)
      .floor()
      .clamp(0, n - 1);
  return (x: x, y: y);
}

/// Alle Kacheln, die [bounds] von [minZoom] bis [maxZoom] berühren, nach
/// Zoom und Zeile — die Reihenfolge ist egal, der Schreiber sortiert.
List<TileXYZ> tilesCovering(AreaBounds bounds, {int minZoom = kAreaMinZoom, required int maxZoom}) {
  final out = <TileXYZ>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final nw = tileAt(bounds.north, bounds.west, z);
    final se = tileAt(bounds.south, bounds.east, z);
    for (var x = nw.x; x <= se.x; x++) {
      for (var y = nw.y; y <= se.y; y++) {
        out.add((z: z, x: x, y: y));
      }
    }
  }
  return out;
}

/// Wie viele Kacheln [tilesCovering] liefern würde — ohne die Liste zu
/// bauen (für die Obergrenze, bevor jemand 40 000 Einträge anlegt).
int countTilesCovering(AreaBounds bounds, {int minZoom = kAreaMinZoom, required int maxZoom}) {
  var count = 0;
  for (var z = minZoom; z <= maxZoom; z++) {
    final nw = tileAt(bounds.north, bounds.west, z);
    final se = tileAt(bounds.south, bounds.east, z);
    count += (se.x - nw.x + 1) * (se.y - nw.y + 1);
  }
  return count;
}

int tileIdOf(TileXYZ t) => ZXY(t.z, t.x, t.y).toTileId();

/// Lesbare Größe, wie sie das Blatt und die Liste zeigen.
String formatBytes(int bytes) {
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} kB';
  if (bytes < 1000 * 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(bytes / 1e9).toStringAsFixed(2).replaceAll('.', ',')} GB';
}
