// Die Hervorhebung gespeicherter Kacheln (Stufe B), pur: eine Maske über
// dem Ausschnitt mit Rand, die gespeicherten Kacheln als Löcher, der
// Zoom zwei Stufen über der Kamera und nie über dem des Bereichs.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_overlay.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';

StoredArea _area(String id, AreaShape shape, {int maxZoom = 13}) => StoredArea(
      id: id,
      name: id,
      bounds: shape.hull,
      shape: shape,
      minZoom: 8,
      maxZoom: maxZoom,
      build: '20260928',
      tiles: 1,
      bytes: 1,
      savedAt: DateTime.utc(2026, 9, 28),
    );

const _view = MapViewBounds(south: 47.90, west: 11.60, north: 47.95, east: 11.70);

void main() {
  test('der Zoom liegt zwei Stufen über der Kamera, zwischen 8 und 13', () {
    expect(offlineOverlayZoom(4.2), 8);
    expect(offlineOverlayZoom(9.7), 11);
    expect(offlineOverlayZoom(13.9), 13);
  });

  test('die Maske deckt den Ausschnitt mit Rand, die Löcher sind die gespeicherten Kacheln', () {
    final rect = const RectShape(AreaBounds(south: 47.91, west: 11.62, north: 47.93, east: 11.66));
    final mask = offlineCoverageMask([_area('r', rect)], _view, cameraZoom: 11)!;
    expect(mask.fillColor, kOfflineDimColor);
    final box = offlineOverlayBox(_view);
    expect(mask.points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b), closeTo(box.north, 1e-9));
    expect(box.west, closeTo(11.50, 1e-9), reason: 'eine Fensterbreite Rand');
    // Jedes Loch ist eine Zoom-13-Kachel, die den Rahmen berührt.
    expect(mask.holes.length, rect.tilesWithin(box, 13).length);
    for (final hole in mask.holes) {
      expect(hole, hasLength(4));
      expect(rect.bounds.intersects(AreaBounds(
          south: hole[2].latitude, west: hole[0].longitude, north: hole[0].latitude, east: hole[1].longitude)), isTrue);
    }
  });

  test('zwei Bereiche: dieselbe Kachel nur einmal, und ein alter Bereich zeigt seine feinsten', () {
    final a = const RectShape(AreaBounds(south: 47.91, west: 11.62, north: 47.93, east: 11.66));
    final b = const RectShape(AreaBounds(south: 47.92, west: 11.64, north: 47.94, east: 11.68));
    final both = offlineCoverageMask([_area('a', a), _area('b', b)], _view, cameraZoom: 11)!;
    final union = {...a.tilesWithin(offlineOverlayBox(_view), 13), ...b.tilesWithin(offlineOverlayBox(_view), 13)};
    expect(both.holes.length, union.length);
    // Ein Bereich nur bis Zoom 10 hat keine 13er-Kacheln — seine 10er
    // sind die Löcher.
    final coarse = offlineCoverageMask([_area('c', a, maxZoom: 10)], _view, cameraZoom: 11)!;
    expect(coarse.holes.length, a.tilesWithin(offlineOverlayBox(_view), 10).length);
  });

  test('ohne Bereiche ist alles dunkel; ein leerer Ausschnitt gibt nichts', () {
    final mask = offlineCoverageMask(const [], _view, cameraZoom: 11)!;
    expect(mask.holes, isEmpty);
    expect(offlineCoverageMask(const [], const MapViewBounds(south: 1, west: 1, north: 1, east: 1), cameraZoom: 11),
        isNull);
  });

  test('eine Kachelmenge zeigt nur ihre Kacheln, nicht die Hülle', () {
    final line = [for (var i = 0; i <= 10; i++) LatLng(47.90 + i * 0.004, 11.62)];
    final far = [for (var i = 0; i <= 10; i++) LatLng(47.90 + i * 0.004, 11.69)];
    final shape = AreaShape.alongLines([line, far])!;
    final mask = offlineCoverageMask([_area('t', shape)], _view, cameraZoom: 11)!;
    expect(mask.holes.length, lessThan(RectShape(shape.hull).tilesWithin(offlineOverlayBox(_view), 13).length));
    expect(mask.holes.length, shape.tilesWithin(offlineOverlayBox(_view), 13).length);
  });

  test('zu viele Löcher ⇒ eine Stufe gröber', () {
    // Ganz DACH bei Zoom 13 wären zehntausende Löcher; die Maske weicht
    // auf einen Zoom aus, der unter der Grenze bleibt.
    const dach = RectShape(AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5));
    const wide = MapViewBounds(south: 46, west: 6, north: 55, east: 17);
    final mask = offlineCoverageMask([_area('d', dach)], wide, cameraZoom: 11)!;
    expect(mask.holes.length, lessThanOrEqualTo(kOfflineOverlayMaxHoles));
    expect(mask.holes, isNotEmpty);
  });
}
