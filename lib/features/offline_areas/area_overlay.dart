// Die Hervorhebung gespeicherter Kacheln (Offline-Karten, Stufe B;
// Betreiber, 2026-09-28: „die offline Kacheln hervorgehoben darstellen
// bzw. die anderen ausgegraut"), pur: aus den gespeicherten Bereichen
// und dem Ausschnitt EIN Polygon — die Abdunkelung über dem Ausschnitt
// (und einem Rand darum herum, damit ein Wischen nicht sofort ins Helle
// führt), mit den gespeicherten Kacheln als Löchern.
//
// Gezeigt werden die Kacheln zwei Stufen über dem Zoom der Kamera, bis
// zum Zoom des Bereichs: Weit draußen sind das die groben Eltern (die
// sind ja gespeichert), nah dran die echten Kacheln. Gerechnet wird aus
// den FORMEN im Index, nicht aus den Archiven — die kennen ihre Kacheln.
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_view/map_view.dart';
import 'area_plan.dart';
import 'area_store.dart';

/// Die Abdunkelung: dunkel genug, dass der Unterschied sofort zu sehen
/// ist, hell genug, dass die Karte darunter lesbar bleibt.
const kOfflineDimColor = Color(0x66000000);

/// Wie viele Stufen über dem Kamera-Zoom die Kacheln gezeigt werden.
const kOfflineOverlayZoomAbove = 2;

/// Mehr Löcher zeichnet die Maske nicht — dann eine Stufe gröber.
const kOfflineOverlayMaxHoles = 2000;

/// Der Zoom, in dem die Kacheln für [cameraZoom] gezeigt werden.
int offlineOverlayZoom(double cameraZoom) =>
    (cameraZoom.floor() + kOfflineOverlayZoomAbove).clamp(kAreaMinZoom, kAreaShapeZoom);

/// Der Ausschnitt plus je eine Fensterbreite und -höhe Rand.
AreaBounds offlineOverlayBox(MapViewBounds view) {
  final w = view.east - view.west, h = view.north - view.south;
  return AreaBounds(
    south: (view.south - h).clamp(-85.0, 85.0),
    west: (view.west - w).clamp(-180.0, 180.0),
    north: (view.north + h).clamp(-85.0, 85.0),
    east: (view.east + w).clamp(-180.0, 180.0),
  );
}

/// Die Maske für [areas] im Ausschnitt [view] — null nur, wenn der
/// Ausschnitt leer ist. Ohne Bereiche ist alles dunkel: Das IST die
/// Aussage.
MapViewPolygon? offlineCoverageMask(List<StoredArea> areas, MapViewBounds view,
    {required double cameraZoom}) {
  if (view.east <= view.west || view.north <= view.south) return null;
  final box = offlineOverlayBox(view);
  var z = offlineOverlayZoom(cameraZoom);
  var holes = _holes(areas, box, z);
  while (holes.length > kOfflineOverlayMaxHoles && z > kAreaMinZoom) {
    z--;
    holes = _holes(areas, box, z);
  }
  return MapViewPolygon(
    points: [
      LatLng(box.north, box.west),
      LatLng(box.north, box.east),
      LatLng(box.south, box.east),
      LatLng(box.south, box.west),
    ],
    holes: holes,
    fillColor: kOfflineDimColor,
  );
}

List<List<LatLng>> _holes(List<StoredArea> areas, AreaBounds box, int z) {
  final seen = <TileXYZ>{};
  for (final a in areas) {
    // Ein Bereich bis Zoom 10 hat keine Kacheln bei 13 — dann seine
    // feinsten.
    final az = z > a.maxZoom ? a.maxZoom : z;
    if (az < a.minZoom) continue;
    seen.addAll(a.shape.tilesWithin(box, az));
  }
  return [
    for (final t in seen)
      () {
        final b = tileBounds(t.z, t.x, t.y);
        return [
          LatLng(b.north, b.west),
          LatLng(b.north, b.east),
          LatLng(b.south, b.east),
          LatLng(b.south, b.west),
        ];
      }(),
  ];
}
