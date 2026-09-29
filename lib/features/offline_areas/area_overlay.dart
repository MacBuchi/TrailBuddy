// Die Hervorhebung gespeicherter Kacheln (Offline-Karten, Stufe B;
// Betreiber, 2026-09-28: „die offline Kacheln hervorgehoben darstellen
// bzw. die anderen ausgegraut"), pur: aus den gespeicherten Bereichen
// und dem Ausschnitt EIN Polygon — die Abdunkelung über dem Ausschnitt
// (und einem Rand darum herum, damit ein Wischen nicht sofort ins Helle
// führt), mit den gespeicherten Kacheln als Löchern.
//
// **Immer die echten Kacheln, bei JEDEM Kamera-Zoom** (seit 0.27.0,
// Betreiber, 2026-09-29: „die gespeicherten Kacheln verändern sich je
// Zoom — die Kacheln sind groß genug, dass man sie gleich in der
// Detailansicht zeigen kann"). Bis 0.26.x zeigte die Maske zwei Stufen
// über der Kamera, weit draußen also die groben Eltern, und die
// Hervorhebung sprang beim Zoomen. Jetzt ist es der Zoom des Bereichs
// (13, die Stufe der Formen). Damit weit draußen nicht tausende Löcher
// entstehen, fasst [mergeTileRects] zusammenhängende Kacheln zu
// Rechtecken zusammen — eine Fläche aus Kacheln bleibt eine Handvoll
// Rechtecke. Gerechnet wird aus den FORMEN im Index, nicht aus den
// Archiven.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_view/map_view.dart';
import 'area_plan.dart';
import 'area_store.dart';

/// Die Abdunkelung: dunkel genug, dass der Unterschied sofort zu sehen
/// ist, hell genug, dass die Karte darunter lesbar bleibt.
const kOfflineDimColor = Color(0x66000000);

/// Mehr Rechtecke als das zeichnet die Maske nur im Ausschnitt selbst,
/// ohne den Rand darum — nie gröber: Die Kacheln sollen beim Zoomen
/// stehen bleiben.
const kOfflineOverlayMaxHoles = 3000;

/// Der Zoom, in dem ein Bereich hervorgehoben wird: seine feinste Stufe,
/// höchstens die der Formen.
int offlineOverlayZoomOf(StoredArea area) => math.min(area.maxZoom, kAreaShapeZoom);

/// Der Ausschnitt plus je eine Fensterbreite und -höhe Rand.
AreaBounds offlineOverlayBox(MapViewBounds view, {bool margin = true}) {
  final w = view.east - view.west, h = view.north - view.south;
  final f = margin ? 1.0 : 0.0;
  return AreaBounds(
    south: (view.south - f * h).clamp(-85.0, 85.0),
    west: (view.west - f * w).clamp(-180.0, 180.0),
    north: (view.north + f * h).clamp(-85.0, 85.0),
    east: (view.east + f * w).clamp(-180.0, 180.0),
  );
}

/// Kacheln EINES Zooms zu Rechtecken: erst je Zeile die Läufe
/// nebeneinander, dann gleiche Läufe übereinander. Keine Überlappung,
/// keine Lücke — die Vereinigung ist genau die Kachelmenge.
List<AreaBounds> mergeTileRects(Iterable<TileXYZ> tiles) {
  final byRow = <int, List<int>>{};
  var z = -1;
  for (final t in tiles) {
    z = t.z;
    (byRow[t.y] ??= []).add(t.x);
  }
  if (byRow.isEmpty) return const [];
  // Läufe je Zeile: (x0, x1).
  final rows = byRow.keys.toList()..sort();
  final open = <(int, int), int>{}; // Lauf → Zeile, in der er beginnt
  final out = <AreaBounds>[];
  void close((int, int) run, int y0, int y1) {
    final nw = tileBounds(z, run.$1, y0);
    final se = tileBounds(z, run.$2, y1);
    out.add(AreaBounds(south: se.south, west: nw.west, north: nw.north, east: se.east));
  }

  int? prevRow;
  for (final y in rows) {
    final xs = byRow[y]!..sort();
    final runs = <(int, int)>{};
    var a = xs.first, b = xs.first;
    for (final x in xs.skip(1)) {
      if (x == b) continue;
      if (x == b + 1) {
        b = x;
      } else {
        runs.add((a, b));
        a = b = x;
      }
    }
    runs.add((a, b));
    // Läufe, die in dieser Zeile nicht weitergehen (oder nach einer
    // Lückenzeile), schließen.
    for (final run in open.keys.toList()) {
      if (prevRow != y - 1 || !runs.contains(run)) {
        close(run, open.remove(run)!, prevRow!);
      }
    }
    for (final run in runs) {
      open.putIfAbsent(run, () => y);
    }
    prevRow = y;
  }
  for (final e in open.entries) {
    close(e.key, e.value, prevRow!);
  }
  return out;
}

List<LatLng> rectRing(AreaBounds b) => [
      LatLng(b.north, b.west),
      LatLng(b.north, b.east),
      LatLng(b.south, b.east),
      LatLng(b.south, b.west),
    ];

/// Die Maske für [areas] im Ausschnitt [view] — null nur, wenn der
/// Ausschnitt leer ist. Ohne Bereiche ist alles dunkel: Das IST die
/// Aussage.
MapViewPolygon? offlineCoverageMask(List<StoredArea> areas, MapViewBounds view) {
  if (view.east <= view.west || view.north <= view.south) return null;
  var box = offlineOverlayBox(view);
  var holes = _holes(areas, box);
  if (holes.length > kOfflineOverlayMaxHoles) {
    box = offlineOverlayBox(view, margin: false);
    holes = _holes(areas, box);
  }
  return MapViewPolygon(
    points: rectRing(box),
    holes: holes,
    fillColor: kOfflineDimColor,
  );
}

List<List<LatLng>> _holes(List<StoredArea> areas, AreaBounds box) {
  // Je Zoom gesammelt: Bereiche mit verschiedenem Zoom (ein alter bis
  // 10) liegen sonst doppelt übereinander.
  final byZoom = <int, Set<TileXYZ>>{};
  for (final a in areas) {
    final z = offlineOverlayZoomOf(a);
    if (z < a.minZoom) continue;
    (byZoom[z] ??= {}).addAll(a.shape.tilesWithin(box, z));
  }
  return [
    for (final tiles in byZoom.values)
      for (final r in mergeTileRects(tiles)) rectRing(r),
  ];
}
