// Die Planung eines Bereichs (Konzept 3.2): Welche Kacheln ein Rahmen
// berührt, die Obergrenze, der Rand um die Trails, die Größenangabe.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';

void main() {
  test('Kachel einer Koordinate: bekannte Werte, Ränder geklemmt', () {
    // Der Ursprung der Karte liegt oben links; die Mitte ist Kachel n/2.
    expect(tileAt(0, 0, 1), (x: 1, y: 1));
    expect(tileAt(85, -180, 3), (x: 0, y: 0));
    expect(tileAt(-85, 179.999, 3), (x: 7, y: 7));
    // Ein Punkt im Alpenvorland bei Zoom 13 (nachgerechnet mit der
    // Slippy-Map-Formel).
    expect(tileAt(47.9, 11.6, 13), (x: 4359, y: 2851));
  });

  test('ein Rahmen berührt je Zoom ein Rechteck aus Kacheln; die Ids sind Hilbert-Ids', () {
    const bounds = AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7);
    final tiles = tilesCovering(bounds, minZoom: 12, maxZoom: 13);
    expect(tiles.where((t) => t.z == 12).length, greaterThanOrEqualTo(2));
    expect(tiles.where((t) => t.z == 13).length, greaterThan(tiles.where((t) => t.z == 12).length));
    expect(tiles.length, countTilesCovering(bounds, minZoom: 12, maxZoom: 13));
    for (final t in tiles) {
      expect(ZXY.fromTileId(tileIdOf(t)), ZXY(t.z, t.x, t.y));
    }
    // Bei Zoom 8 beginnt der Bereich: darunter liegt die Übersicht.
    expect(tilesCovering(bounds, maxZoom: 8).every((t) => t.z == kAreaMinZoom), isTrue);
  });

  test('ganz DACH überschreitet die Obergrenze, ein Wochenendgebiet nicht', () {
    const dach = AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5);
    expect(countTilesCovering(dach, maxZoom: 13), greaterThan(kAreaMaxTiles));
    const weekend = AreaBounds(south: 47.4, west: 11.0, north: 47.9, east: 11.8);
    expect(countTilesCovering(weekend, maxZoom: 13), lessThan(kAreaMaxTiles));
  });

  test('der Rahmen um Punkte trägt den Rand, und ohne Punkte gibt es keinen', () {
    final b = AreaBounds.around(const [LatLng(47.9, 11.6), LatLng(47.95, 11.7)])!;
    expect(b.south, lessThan(47.9));
    expect(b.north, greaterThan(47.95));
    expect(b.west, lessThan(11.6));
    expect(b.east, greaterThan(11.7));
    // 2 km sind ~0,018° Breite.
    expect(47.9 - b.south, closeTo(2 / 111, 1e-6));
    expect(b.contains(const LatLng(47.92, 11.65)), isTrue);
    expect(b.intersects(const AreaBounds(south: 48.5, west: 11, north: 49, east: 12)), isFalse);
    expect(AreaBounds.around(const []), isNull);
    expect(AreaBounds.fromJson(b.toJson()).north, b.north);
  });

  test('Größen lesbar, deutsch', () {
    expect(formatBytes(512000), '512 kB');
    expect(formatBytes(12400000), '12,4 MB');
    expect(formatBytes(2800000000), '2,80 GB');
  });
}
