// Die Trefferprüfung der Kartenfassade: EINE Rechnung für beide Engines.
// Was hier stimmt, stimmt auf Android (MapLibre) und im Web (flutter_map)
// gleich — und was hier fehlt, fehlt auf beiden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_hit_test.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';

// Ein Ausschnitt 0,1° × 0,05° auf 1000 × 500 px: 1° = 10 000 px in der
// Breite. (In der Höhe streckt Mercator bei 48° um ~1,5, das ist hier
// egal — geprüft wird gegen die Projektion selbst.)
const _camera = MapViewCamera(
  center: LatLng(48.025, 11.05),
  bounds: MapViewBounds(west: 11.0, east: 11.1, south: 48.0, north: 48.05),
  size: Size(1000, 500),
);

MapTap _tapAt(LatLng p, {Offset shift = Offset.zero}) => MapTap(
      point: p,
      screenPoint: projectToScreen(_camera, p) + shift,
      camera: _camera,
    );

MapViewPolyline _line(Object? hit, {double width = 4, double border = 0}) => MapViewPolyline(
      points: const [LatLng(48.02, 11.02), LatLng(48.02, 11.08)],
      color: Colors.green,
      width: width,
      borderWidth: border,
      hitValue: hit,
    );

MapViewMarker _pin(Object? hit, LatLng at) => MapViewMarker(
      point: at,
      width: 30,
      height: 40,
      alignment: Alignment.topCenter,
      hitValue: hit,
      child: const SizedBox(),
    );

void main() {
  test('Projektion: Ecken und Mitte landen, wo sie hingehören', () {
    expect(projectToScreen(_camera, const LatLng(48.05, 11.0)), const Offset(0, 0));
    final se = projectToScreen(_camera, const LatLng(48.0, 11.1));
    expect(se.dx, closeTo(1000, 1e-6));
    expect(se.dy, closeTo(500, 1e-6));
    final mid = projectToScreen(_camera, const LatLng(48.025, 11.05));
    expect(mid.dx, closeTo(500, 1e-6));
    // Mercator: die Mitte in Grad liegt nicht exakt in der Pixelmitte.
    expect(mid.dy, closeTo(250, 1));
  });

  test('Umkehrung: Bildpunkt zurück zur Stelle (Bereiche zeichnen, Stufe C)', () {
    for (final p in const [LatLng(48.05, 11.0), LatLng(48.0, 11.1), LatLng(48.013, 11.071)]) {
      final back = unprojectFromScreen(_camera, projectToScreen(_camera, p));
      expect(back.latitude, closeTo(p.latitude, 1e-9));
      expect(back.longitude, closeTo(p.longitude, 1e-9));
    }
  });

  test('Zoom aus Fenster und Breite: 256er Web-Mercator', () {
    // 0,1° auf 1000 px ⇒ 360° auf 3,6 Mio px ⇒ 2^z · 256 = 3,6 Mio ⇒ z ≈ 13,78.
    expect(_camera.zoom, closeTo(13.78, 0.01));
    // Doppelte Breite bei gleichem Fenster: eine Stufe mehr.
    expect(mapZoomFor(_camera.bounds, 2000), closeTo(_camera.zoom + 1, 1e-9));
  });

  test('Linie: innerhalb der Toleranz getroffen, daneben nicht', () {
    final layers = MapViewLayers(polylines: [_line('trail')]);
    const on = LatLng(48.02, 11.05);
    expect(resolveMapTap(layers, _tapAt(on)), 'trail');
    // 12 px + halbe Breite (2) = 14 px Toleranz.
    expect(resolveMapTap(layers, _tapAt(on, shift: const Offset(0, 13))), 'trail');
    expect(resolveMapTap(layers, _tapAt(on, shift: const Offset(0, 16))), isNull);
    // Jenseits des Endpunkts: die Strecke endet, der Tipp geht ins Leere.
    expect(resolveMapTap(layers, _tapAt(const LatLng(48.02, 11.09))), isNull);
  });

  test('ein Rand macht die Linie breiter, also leichter zu treffen', () {
    final layers = MapViewLayers(polylines: [_line('trail', border: 4)]);
    expect(resolveMapTap(layers, _tapAt(const LatLng(48.02, 11.05), shift: const Offset(0, 17))),
        'trail');
  });

  test('die OBERSTE Linie gewinnt — das Netz liegt über den offiziellen Trails', () {
    final layers = MapViewLayers(polylines: [_line('official'), _line('trail')]);
    expect(resolveMapTap(layers, _tapAt(const LatLng(48.02, 11.05))), 'trail');
  });

  test('ohne Kennung zählt nichts: die Fahrt ist Kulisse', () {
    final layers = MapViewLayers(polylines: [_line(null)]);
    expect(resolveMapTap(layers, _tapAt(const LatLng(48.02, 11.05))), isNull);
  });

  test('Marker: die Nadel hängt ÜBER dem Punkt (topCenter), getroffen wird ihre Fläche', () {
    const at = LatLng(48.03, 11.05);
    final layers = MapViewLayers(markers: [_pin('poi', at)]);
    final foot = projectToScreen(_camera, at);
    final rect = markerRect(_camera, layers.markers.single);
    expect(rect.bottomCenter.dx, closeTo(foot.dx, 1e-9));
    expect(rect.bottomCenter.dy, closeTo(foot.dy, 1e-9));
    expect(rect.height, 40);
    // Mitten in den Kopf: Treffer. 20 px UNTER dem Punkt: nichts — dort
    // ist keine Nadel.
    expect(resolveMapTap(layers, _tapAt(at, shift: const Offset(0, -20))), 'poi');
    expect(resolveMapTap(layers, _tapAt(at, shift: const Offset(0, 20))), isNull);
  });

  test('Linie vor Nadel: liegt der Trail über dem Ort, trifft der Tipp den Trail', () {
    // Nadel genau auf der Linie (Fuß bei 48,02): Ein Tipp auf den Fuß
    // liegt in beiden — die Linie gewinnt, wie in beiden Engines.
    const at = LatLng(48.02, 11.05);
    final layers = MapViewLayers(polylines: [_line('trail')], markers: [_pin('poi', at)]);
    expect(resolveMapTap(layers, _tapAt(at)), 'trail');
    // Weit oben im Nadelkopf, außerhalb der Linien-Toleranz: die Nadel.
    expect(resolveMapTap(layers, _tapAt(at, shift: const Offset(0, -30))), 'poi');
  });

  test('handleTap ruft onHit bei Treffer, sonst onTap', () {
    Object? hit;
    var empty = 0;
    final config = MapViewConfig(
      initialCenter: _camera.center,
      initialZoom: 12,
      minZoom: 3,
      maxZoom: 19,
      backgroundColor: Colors.white,
      onHit: (h, _) => hit = h,
      onTap: (_) => empty++,
    );
    final layers = MapViewLayers(polylines: [_line('trail')]);
    config.handleTap(_tapAt(const LatLng(48.02, 11.05)), layers);
    expect(hit, 'trail');
    config.handleTap(_tapAt(const LatLng(48.04, 11.05)), layers);
    expect(empty, 1);
  });

  group('visibleMarkers (Culling der MapLibre-Engine)', () {
    MapViewMarker at(double lat, double lon) =>
        MapViewMarker(point: LatLng(lat, lon), width: 30, height: 40, child: const SizedBox());
    const bounds = MapViewBounds(west: 11.0, east: 12.0, south: 48.0, north: 48.5);

    test('innerhalb bleibt, weit außerhalb fliegt raus, der Rand (25 %) zählt noch', () {
      final inside = at(48.2, 11.5);
      final farNorth = at(52.5, 11.5);
      final justOutsideEast = at(48.2, 12.2);
      final beyondMargin = at(48.2, 12.3);
      expect(visibleMarkers([inside, farNorth, justOutsideEast, beyondMargin], bounds),
          [inside, justOutsideEast]);
    });

    test('Reihenfolge bleibt erhalten (Zeichenreihenfolge = Stapelung)', () {
      final a = at(48.1, 11.2), b = at(48.2, 11.4), c = at(48.3, 11.6);
      expect(visibleMarkers([c, a, b], bounds), [c, a, b]);
    });
  });

  test('MapViewController: fit vor dem Einbau wird beim Einbau nachgeholt', () {
    final controller = MapViewController(initialCenter: _camera.center, initialZoom: 6);
    controller.fit(const [LatLng(48.0, 11.0), LatLng(48.1, 11.1)]);
    final delegate = _RecordingDelegate();
    controller.attach(delegate);
    expect(delegate.fits, 1);
    controller.fit(const [LatLng(48.0, 11.0)]);
    expect(delegate.fits, 2);
    // Ein `move` vor dem Einbau verwirft den wartenden Fit.
    final other = MapViewController(initialCenter: _camera.center, initialZoom: 6);
    other.fit(const [LatLng(48.0, 11.0), LatLng(48.1, 11.1)]);
    other.move(const LatLng(47, 10), 12);
    final d2 = _RecordingDelegate();
    other.attach(d2);
    expect(d2.fits, 0);
    expect(other.center, const LatLng(47, 10));
  });
}

class _RecordingDelegate implements MapViewCameraDelegate {
  int fits = 0;
  @override
  LatLng center = const LatLng(47, 10);
  @override
  double zoom = 12;
  @override
  void move(LatLng c, double z) {
    center = c;
    zoom = z;
  }

  @override
  void fit(List<LatLng> points, {required double padding, required double maxZoom}) => fits++;
}
