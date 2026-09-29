// Bereiche zeichnen (Stufe C), pur: aus einem Strich die Kacheln, die er
// umschließt oder berührt; der Entwurf, der Striche addiert und abzieht,
// sich zurücknehmen lässt und nach dem Speichern verschwindet; und die
// Anzeige, die eine Zeile Kacheln zu EINEM Rechteck zieht.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_draw.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';

const _z = kAreaShapeZoom;

int _key(int x, int y) => TileSetShape.keyOf(x, y, _z);

/// Ein Ring knapp INNERHALB der Kacheln x0..x1 × y0..y1.
List<LatLng> _ringInside(int x0, int y0, int x1, int y1) {
  final nw = tileBounds(_z, x0, y0), se = tileBounds(_z, x1, y1);
  const e = 1e-5;
  return [
    LatLng(nw.north - e, nw.west + e),
    LatLng(nw.north - e, se.east - e),
    LatLng(se.south + e, se.east - e),
    LatLng(se.south + e, nw.west + e),
  ];
}

void main() {
  // Eine Kachel mitten in Oberbayern.
  final origin = tileAt(47.9, 11.6, _z);
  final x = origin.x, y = origin.y;

  test('ein Ring innerhalb eines Kachelblocks: genau dieser Block, samt Innerem', () {
    final keys = tilesTouchedByRing(_ringInside(x, y, x + 4, y + 3))!;
    expect(keys, {
      for (var i = x; i <= x + 4; i++)
        for (var j = y; j <= y + 3; j++) _key(i, j),
    });
  });

  test('berührt heißt dabei: ein Ring über die Kachelgrenze nimmt die Nachbarn mit', () {
    final nw = tileBounds(_z, x, y), se = tileBounds(_z, x + 1, y + 1);
    // Ein Zehntel Kachel über den Block hinaus, nach Osten.
    final spill = (se.east - nw.west) / 20;
    final keys = tilesTouchedByRing([
      LatLng(nw.north - 1e-5, nw.west + 1e-5),
      LatLng(nw.north - 1e-5, se.east + spill),
      LatLng(se.south + 1e-5, se.east + spill),
      LatLng(se.south + 1e-5, nw.west + 1e-5),
    ])!;
    expect(keys, containsAll([_key(x + 2, y), _key(x + 2, y + 1)]));
    expect(keys, hasLength(6));
  });

  test('ein L: die Ecke, die der Strich ausspart, bleibt draußen', () {
    // Block 4 × 4, oben rechts 2 × 2 ausgespart.
    final a = tileBounds(_z, x, y), b = tileBounds(_z, x + 3, y + 3);
    final mid = tileBounds(_z, x + 2, y + 2); // Ecke der Aussparung: NW von (x+2, y+2)
    const e = 1e-5;
    final keys = tilesTouchedByRing([
      LatLng(a.north - e, a.west + e),
      LatLng(a.north - e, mid.west - e),
      LatLng(mid.north - e, mid.west - e),
      LatLng(mid.north - e, b.east - e),
      LatLng(b.south + e, b.east - e),
      LatLng(b.south + e, a.west + e),
    ])!;
    expect(keys, hasLength(16 - 4));
    for (final k in [_key(x + 2, y), _key(x + 3, y), _key(x + 2, y + 1), _key(x + 3, y + 1)]) {
      expect(keys, isNot(contains(k)));
    }
  });

  test('ein offener Strich ist eine dünne Fläche: die Kacheln, über die er läuft', () {
    final a = tileBounds(_z, x, y), b = tileBounds(_z, x + 5, y);
    final row = (a.north + a.south) / 2;
    final keys = tilesTouchedByRing([LatLng(row, a.west + 1e-5), LatLng(row, b.east - 1e-5)])!;
    expect(keys, {for (var i = x; i <= x + 5; i++) _key(i, y)});
  });

  test('zu groß gezeichnet ⇒ null, zu wenig ⇒ nichts', () {
    expect(
        tilesTouchedByRing(const [LatLng(30, 0), LatLng(30, 30), LatLng(60, 30), LatLng(60, 0)]),
        isNull);
    expect(tilesTouchedByRing(const [LatLng(47.9, 11.6)]), isEmpty);
  });

  test('der Entwurf: dazu, weg, zurück — und nach jedem Strich ist das Werkzeug weg', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(areaDraftProvider.notifier);
    expect(c.read(areaDraftProvider), isNull);
    n.start();
    expect(c.read(areaDraftProvider)!.isEmpty, isTrue);
    n.applyStroke({_key(x, y)});
    expect(c.read(areaDraftProvider)!.isEmpty, isTrue, reason: 'ohne Werkzeug zählt kein Strich');

    n.arm(AreaDrawTool.add);
    expect(c.read(areaDraftProvider)!.tool, AreaDrawTool.add);
    n.applyStroke({_key(x, y), _key(x + 1, y), _key(x + 2, y)});
    expect(c.read(areaDraftProvider)!.keys, hasLength(3));
    expect(c.read(areaDraftProvider)!.tool, isNull);

    n.arm(AreaDrawTool.remove);
    n.applyStroke({_key(x + 1, y), _key(x + 9, y)});
    expect(c.read(areaDraftProvider)!.keys, {_key(x, y), _key(x + 2, y)});

    // Derselbe Knopf noch einmal nimmt das Werkzeug zurück.
    n.arm(AreaDrawTool.add);
    n.arm(AreaDrawTool.add);
    expect(c.read(areaDraftProvider)!.tool, isNull);

    n.undo();
    expect(c.read(areaDraftProvider)!.keys, hasLength(3));
    n.undo();
    expect(c.read(areaDraftProvider)!.isEmpty, isTrue);
    expect(c.read(areaDraftProvider)!.history, isEmpty);

    n.addAll({_key(x, y)});
    // Gespeichert mit ANDEREN Kacheln: bleibt; mit denselben: weg.
    n.discardIfSaved(TileSetShape(zoom: _z, keys: {_key(x + 5, y)}));
    expect(c.read(areaDraftProvider), isNotNull);
    n.discardIfSaved(TileSetShape(zoom: _z, keys: {_key(x, y)}));
    expect(c.read(areaDraftProvider), isNull);
  });

  test('ein Strich ohne Änderung ist kein Schritt — Rückgängig tut immer etwas', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(areaDraftProvider.notifier)..start();
    n.arm(AreaDrawTool.remove);
    n.applyStroke({_key(x, y)});
    expect(c.read(areaDraftProvider)!.history, isEmpty);
    expect(c.read(areaDraftProvider)!.tool, isNull);
  });

  test('Schnappschuss: die 13er-Kacheln des Ausschnitts, zu groß ⇒ null', () {
    final b = tileBounds(_z, x, y);
    final keys = tilesInBounds(AreaBounds(
        south: b.south + 1e-6, west: b.west + 1e-6, north: b.north - 1e-6,
        east: tileBounds(_z, x + 2, y).east - 1e-6))!;
    expect(keys, {_key(x, y), _key(x + 1, y), _key(x + 2, y)});
    expect(tilesInBounds(const AreaBounds(south: 30, west: 0, north: 60, east: 30)), isNull);
  });

  test('Werkzeuge und „dazunehmen" beginnen den Entwurf selbst', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(areaDraftProvider.notifier);
    expect(n.hasChanges, isFalse);
    n.addAll({_key(x, y)});
    expect(n.hasChanges, isTrue);
    n.discard();
    n.arm(AreaDrawTool.add);
    expect(c.read(areaDraftProvider)!.tool, AreaDrawTool.add);
    expect(n.hasChanges, isFalse, reason: 'ein Werkzeug allein ist keine Änderung');
  });

  test('die Anzeige zieht eine Zeile zu einem Rechteck, zwei Zeilen zu zweien', () {
    final draft = AreaDraft(keys: {
      for (var i = x; i < x + 5; i++) _key(i, y),
      _key(x, y + 1),
      _key(x + 3, y + 1),
    });
    final center = tileBounds(_z, x + 2, y).center;
    const half = 0.1;
    final view = MapViewBounds(
        west: center.longitude - half, east: center.longitude + half,
        south: center.latitude - half / 2, north: center.latitude + half / 2);
    // Kamera weit genug drin, dass die Anzeige Zoom 13 nimmt.
    final polys = draftPolygons(draft, view);
    expect(polys, hasLength(3), reason: 'eine Zeile aus fünf, dann zwei einzelne');
    expect(polys.every((p) => p.fillColor == kAreaDraftFill), isTrue);
    final run = polys.firstWhere((p) => p.points[1].longitude - p.points[0].longitude > 0.2);
    expect(run.points[0].longitude, closeTo(tileBounds(_z, x, y).west, 1e-9));
    expect(run.points[1].longitude, closeTo(tileBounds(_z, x + 4, y).east, 1e-9));
    // Leer oder ohne Fenster: nichts.
    expect(draftPolygons(AreaDraft(keys: const {}), view), isEmpty);
    // Weit draußen dieselben Rechtecke: Der Entwurf hängt nicht am Zoom.
    final wide = MapViewBounds(
        west: center.longitude - 2, east: center.longitude + 2,
        south: center.latitude - 1, north: center.latitude + 1);
    expect(draftPolygons(draft, wide).map((p) => p.points.first), polys.map((p) => p.points.first));
  });
}
