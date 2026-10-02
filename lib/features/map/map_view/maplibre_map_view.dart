// Die MapLibre-Engine hinter der MapView-Fassade (Android).
//
// Rendert nativ auf eigenem GL-Thread (maplibre-native via Paket
// `maplibre`) statt per Canvas auf dem UI-Isolate — PilzBuddys „Lupo →
// Porsche"-Migration, hier von Anfang an ohne Schalter. Web sieht diese
// Datei nie (bedingter Import in map_view.dart).
//
// Die Widget-Shell bleibt bewusst dumm: Platform-Views sind im
// Widget-Test nicht renderbar, ihr Gate ist das Gerät. Alles Prüfbare
// steckt im puren Composer (map_style_composer.dart), im Style-Provider
// (maplibre_style_provider.dart) und in der Trefferprüfung der Fassade
// (map_hit_test.dart).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../../../core/errors.dart';
import 'flutter_map_view.dart';
import 'map_attribution.dart';
import 'map_hit_test.dart';
import 'map_view.dart';
import 'maplibre_style_provider.dart';

/// Bau-Funktion für die Engine-Wahl in `map_view.dart` — Stub und echte
/// Datei müssen dieselbe Signatur exportieren (bedingter Import).
Widget createMapLibreMapView({
  required MapViewConfig config,
  required MapViewController controller,
  required MapViewLayers layers,
}) =>
    MapLibreMapView(config: config, controller: controller, layers: layers);

class MapLibreMapView extends ConsumerStatefulWidget {
  const MapLibreMapView({
    super.key,
    required this.config,
    required this.controller,
    required this.layers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewLayers layers;

  @override
  ConsumerState<MapLibreMapView> createState() => _MapLibreMapViewState();
}

class _MapLibreMapViewState extends ConsumerState<MapLibreMapView>
    implements MapViewCameraDelegate {
  ml.MapController? _ml;

  /// Unveränderte Linien behalten ihre Ebenen-OBJEKTE — MapLibre überträgt
  /// dann nichts neu (siehe [MapLibreLineCache]).
  final _lineCache = MapLibreLineCache();

  /// Kamerawunsch aus der Zeit zwischen Einbau und Map-Ready (z. B. der
  /// Zoom auf das Netz beim Start): wird bei `onMapCreated` nachgeholt,
  /// statt still verloren zu gehen.
  (LatLng, double)? _pendingMove;
  ({List<LatLng> points, double padding, double maxZoom, double bottomInset})? _pendingFit;

  /// Sichtfenster vom letzten Kamera-Idle — Grundlage des
  /// Marker-Cullings. Vorher (Karte noch nicht bereit) werden KEINE
  /// Marker eingebaut.
  MapViewBounds? _visibleBounds;

  /// Der zuletzt an die Engine gegebene Style. `initStyle` wird von
  /// `maplibre_android` genau EINMAL bei Map-Ready angewendet — jede
  /// spätere Änderung (Empfang weg ⇒ Übersicht dazu) muss über `setStyle`
  /// laufen, und der String-Vergleich erspart der Engine die
  /// unveränderten Fälle.
  String? _appliedStyle;

  Size get _size {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size : Size.zero;
  }

  MapViewCamera? _cameraOf(ml.MapController controller) {
    final camera = controller.camera;
    if (camera == null) return null;
    final region = controller.getVisibleRegion();
    return MapViewCamera(
      center: LatLng(camera.center.lat.toDouble(), camera.center.lon.toDouble()),
      bounds: MapViewBounds(
        west: region.longitudeWest,
        east: region.longitudeEast,
        south: region.latitudeSouth,
        north: region.latitudeNorth,
      ),
      size: _size,
    );
  }

  /// Liest das Sichtfenster der Engine, stößt den Rebuild an, der die
  /// Markerliste neu filtert, und meldet den Stillstand an die Fassade.
  void _onIdle() {
    final controller = _ml;
    if (controller == null || !mounted) return;
    final camera = _cameraOf(controller);
    if (camera == null) return;
    setState(() => _visibleBounds = camera.bounds);
    widget.config.onCameraIdle?.call(camera);
  }

  static ml.Geographic _geo(LatLng p) => ml.Geographic(lon: p.longitude, lat: p.latitude);

  /// Übersetzt einen Fassaden-Marker in einen MapLibre-Marker — die
  /// Kind-Widgets bleiben unangetastet.
  static ml.Marker asMapLibreMarker(MapViewMarker marker) => ml.Marker(
        point: _geo(marker.point),
        size: Size(marker.width, marker.height),
        // Gespiegelt: MapLibre versteht `alignment` umgekehrt zu
        // flutter_map (PilzBuddy #409) — bei `topCenter` liegt der Punkt
        // dort an der OBERKANTE, hier soll er an der Unterkante liegen.
        alignment: marker.alignment * -1,
        child: KeyedSubtree(key: marker.key, child: marker.child),
      );

  /// Ein Kreis in Metern als Polygon: MapLibres `circle-radius` ist ein
  /// Pixelmaß, der Genauigkeitskreis soll aber mit der Karte wachsen.
  static ml.Feature<ml.Polygon> circlePolygon(MapViewCircle c, {int segments = 48}) {
    final latRad = c.center.latitude * math.pi / 180;
    final dLat = c.radiusM / 111320;
    final dLon = c.radiusM / (111320 * math.cos(latRad));
    final ring = <double>[];
    for (var i = 0; i <= segments; i++) {
      final a = 2 * math.pi * i / segments;
      ring
        ..add(c.center.longitude + dLon * math.cos(a))
        ..add(c.center.latitude + dLat * math.sin(a));
    }
    return ml.Feature(geometry: ml.Polygon.build([ring]));
  }

  /// Eine Fläche mit Löchern als Polygon: der äußere Ring zuerst, dann je
  /// Loch ein innerer Ring (`build` nimmt flache Ketten lon,lat,…).
  static ml.Feature<ml.Polygon> polygonFeature(MapViewPolygon p) {
    List<double> ring(List<LatLng> pts) => [
          for (final q in pts) ...[q.longitude, q.latitude],
          // Geschlossen: GeoJSON verlangt, dass der letzte Punkt der
          // erste ist.
          if (pts.isNotEmpty && pts.first != pts.last) ...[pts.first.longitude, pts.first.latitude],
        ];
    return ml.Feature(geometry: ml.Polygon.build([ring(p.points), for (final h in p.holes) ring(h)]));
  }

  /// Die Flächen nach Stil gruppiert, in der Reihenfolge des ersten
  /// Auftretens — wie die Linien: Der Entwurf eines gezeichneten Bereichs
  /// (Stufe C) sind hunderte Rechtecke derselben Farbe, und eine
  /// Style-Ebene je Rechteck wäre für die Engine eine Zumutung.
  static List<ml.Layer> polygonLayers(List<MapViewPolygon> polygons) {
    final groups = <String, List<MapViewPolygon>>{};
    for (final p in polygons) {
      if (p.points.length < 3) continue;
      final key = '${p.fillColor.toARGB32()}|${p.borderColor?.toARGB32() ?? ''}';
      (groups[key] ??= []).add(p);
    }
    return [
      for (final group in groups.values)
        ml.PolygonLayer(
          polygons: [for (final p in group) polygonFeature(p)],
          color: group.first.fillColor,
          outlineColor: group.first.borderColor ?? group.first.fillColor,
        ),
    ];
  }

  /// Ein Strichmuster in Bildpunkten als MapLibre-`dasharray` — dort in
  /// Vielfachen der Linienbreite, ganzzahlig.
  static List<int> dashArrayFor(List<double> dash, double width) => [
        for (final d in dash) math.max(1, (d / math.max(width, 1)).round()),
      ];

  /// Die Linien nach Stil gruppiert, in der Reihenfolge des ersten
  /// Auftretens — MapLibre trägt Farbe, Breite und Strich am LAYER. Ein
  /// Rand wird zu einer breiteren Ebene DARUNTER in der Randfarbe.
  static List<ml.Layer> polylineLayers(List<MapViewPolyline> lines, [MapLibreLineCache? cache]) {
    final groups = <String, List<MapViewPolyline>>{};
    for (final line in lines) {
      if (line.points.length < 2) continue;
      (groups[line.styleKey] ??= []).add(line);
    }
    final out = <ml.Layer>[];
    for (final entry in groups.entries) {
      out.addAll(cache?.lookup('line:${entry.key}', entry.value) ??
          cache?.store('line:${entry.key}', entry.value, _groupLayers(entry.value)) ??
          _groupLayers(entry.value));
    }
    // Die Namen zuletzt: über allen Linien.
    final labelled = [for (final l in lines) if (l.label != null && l.points.length >= 2) l];
    if (labelled.isNotEmpty) {
      out.addAll(cache?.lookup('labels', labelled) ??
          cache?.store('labels', labelled, [_labelLayer(labelled)]) ??
          [_labelLayer(labelled)]);
    }
    return out;
  }

  static List<ml.Layer> _groupLayers(List<MapViewPolyline> group) {
    final style = group.first;
    final features = [
      for (final line in group)
        ml.Feature(
          // `build` nimmt eine flache Kette lon,lat,lon,lat…
          geometry: ml.LineString.build([
            for (final p in line.points) ...[p.longitude, p.latitude],
          ]),
        ),
    ];
    final width = math.max(1, style.width.round());
    return [
      if (style.borderColor != null && style.borderWidth > 0)
        RoundPolylineLayer(
          polylines: features,
          color: style.borderColor!,
          width: width + (2 * style.borderWidth).round(),
          dashArray: style.borderDash == null
              ? null
              : dashArrayFor(style.borderDash!, style.width + 2 * style.borderWidth),
        ),
      RoundPolylineLayer(
        polylines: features,
        color: style.color,
        width: width,
        dashArray: style.dash == null ? null : dashArrayFor(style.dash!, style.width),
      ),
    ];
  }

  static ml.Layer _labelLayer(List<MapViewPolyline> labelled) => LineLabelLayer(features: [
        for (final l in labelled)
          ml.Feature(
            geometry: ml.LineString.build([
              for (final p in l.points) ...[p.longitude, p.latitude],
            ]),
            properties: {'label': l.label!},
          ),
      ]);

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    super.dispose();
  }

  // MapViewCameraDelegate — die Kamera der Fassade.

  @override
  void move(LatLng center, double zoom) {
    final controller = _ml;
    if (controller == null) {
      _pendingMove = (center, zoom);
      _pendingFit = null;
      return;
    }
    _moveNow(controller, center, zoom, 'Karte bewegen');
  }

  @override
  void fit(List<LatLng> points, {required double padding, required double maxZoom, double bottomInset = 0}) {
    final controller = _ml;
    if (controller == null) {
      _pendingFit = (points: points, padding: padding, maxZoom: maxZoom, bottomInset: bottomInset);
      return;
    }
    // Selbst gerechnet und OHNE Animation gesetzt (#68): `fitBounds`
    // geht auf Android über `animateCamera`, und MapLibre wirft dort bei
    // 0 ms („Null duration passed into animateCamera") — zehn Berichte
    // in 0.17–0.20, jedes Einpassen. `moveCamera` kennt keine Dauer.
    final size = _size.isEmpty ? MediaQuery.sizeOf(context) : _size;
    final cam = cameraToFit(points, size,
        padding: padding, maxZoom: maxZoom, minZoom: widget.config.minZoom, bottomInset: bottomInset);
    _moveNow(controller, cam.center, cam.zoom, 'Karte einpassen');
  }

  /// Setzt die Kamera (256er-Zoom der Fassade) ohne Animation. Ein
  /// Fehler der Engine ist kein unbehandelter Fehler: Die Kamera steht
  /// dann eben woanders, gemeldet wird er mit Kontext.
  void _moveNow(ml.MapController controller, LatLng center, double zoom, String context) {
    unawaited(() async {
      try {
        // MapLibre zählt in 512er-Kacheln: eine Stufe weniger.
        await controller.moveCamera(center: _geo(center), zoom: zoom - 1);
      } catch (e, s) {
        logError(context, e, s);
      }
    }());
  }

  @override
  LatLng get center {
    final cam = _ml?.camera;
    if (cam == null) return _pendingMove?.$1 ?? widget.config.initialCenter;
    return LatLng(cam.center.lat.toDouble(), cam.center.lon.toDouble());
  }

  /// In 256er-Stufen wie die Fassade, also MapLibres Zahl plus eins.
  @override
  double get zoom {
    final cam = _ml?.camera;
    if (cam == null) return _pendingMove?.$2 ?? widget.config.initialZoom;
    return cam.zoom + 1;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(maplibreStyleProvider, (previous, next) {
      final style = next.valueOrNull;
      final controller = _ml;
      if (style != null && controller != null && style != _appliedStyle) {
        _appliedStyle = style;
        controller.setStyle(style);
      }
    });

    final styleAsync = ref.watch(maplibreStyleProvider);
    final style = styleAsync.valueOrNull;
    if (styleAsync.hasError || (styleAsync.hasValue && style == null)) {
      // Rückfalllinie: Ohne Style keine leere Karte, sondern die alte
      // Engine — geloggt hat den Fehlschlag der Style-Provider.
      return FlutterMapView(
        config: widget.config,
        controller: widget.controller,
        layers: widget.layers,
      );
    }
    if (style == null) {
      // Style lädt noch: Landton statt „kaputtem" Grau.
      return ColoredBox(color: widget.config.backgroundColor);
    }

    final layers = widget.layers;
    // Startkamera aus der Fassade, nicht aus der Config: Ein `move()` vor
    // Map-Ready landet im Fallback-Zustand des Controllers.
    final initialCenter = widget.controller.center;
    final initialZoom = widget.controller.zoom;
    return ml.MapLibreMap(
      options: ml.MapOptions(
        initStyle: style,
        initCenter: _geo(initialCenter),
        initZoom: initialZoom - 1,
        minZoom: widget.config.minZoom - 1,
        maxZoom: widget.config.maxZoom - 1,
        // Rotation und Neigung bleiben aus — wie bei flutter_map.
        gestures: const ml.MapGestures(rotate: false, pan: true, zoom: true, pitch: false),
      ),
      onMapCreated: (controller) {
        _ml = controller;
        _appliedStyle = style;
        final pendingMove = _pendingMove;
        final pendingFit = _pendingFit;
        _pendingMove = null;
        _pendingFit = null;
        if (pendingMove != null) move(pendingMove.$1, pendingMove.$2);
        if (pendingFit != null) {
          fit(pendingFit.points,
              padding: pendingFit.padding, maxZoom: pendingFit.maxZoom, bottomInset: pendingFit.bottomInset);
        }
        // Erstes Sichtfenster nach dem Aufbau — ohne diesen Aufruf
        // erschienen Marker erst nach der ersten Geste.
        WidgetsBinding.instance.addPostFrameCallback((_) => _onIdle());
      },
      onEvent: (event) {
        if (event is ml.MapEventClick) {
          final controller = _ml;
          final camera = controller == null ? null : _cameraOf(controller);
          if (camera == null) return;
          widget.config.handleTap(
            MapTap(
              point: LatLng(event.point.lat.toDouble(), event.point.lon.toDouble()),
              // `screenPoint` ist LOKAL zur Kartenfläche — genau das, was
              // die Trefferprüfung erwartet.
              screenPoint: event.screenPoint,
              camera: camera,
            ),
            layers,
          );
        }
        if (event is ml.MapEventLongClick) {
          final controller = _ml;
          final camera = controller == null ? null : _cameraOf(controller);
          if (camera == null) return;
          widget.config.onLongPress?.call(MapTap(
            point: LatLng(event.point.lat.toDouble(), event.point.lon.toDouble()),
            screenPoint: event.screenPoint,
            camera: camera,
          ));
        }
        // Culling und Nachladen bei Kamera-Idle, NICHT pro Frame.
        if (event is ml.MapEventCameraIdle) _onIdle();
      },
      // Deklarative Layer des Pakets — NICHT `children`: Ein
      // `PolylineLayer` ist dort ein `Layer`, kein Widget.
      layers: [
        ...polygonLayers(layers.polygons),
        for (final c in layers.circles) ...[
          ml.PolygonLayer(
            polygons: [circlePolygon(c)],
            color: c.fillColor,
            outlineColor: c.borderColor ?? c.fillColor,
          ),
        ],
        ...polylineLayers(layers.polylines, _lineCache),
      ],
      children: [
        // Maßstab und Quellenhinweis (ODbL-Pflicht) unten links, wie bei
        // der flutter_map-Engine — unten rechts läge er unter den Knöpfen.
        // Steht links die Werkzeugleiste, rücken beide neben sie.
        ml.MapScalebar(
          alignment: Alignment.bottomLeft,
          padding: EdgeInsets.only(left: 44 + widget.config.bottomLeftInset, bottom: 12),
        ),
        // Der eigene Hinweis, nicht `ml.SourceAttribution`: der nennt jede
        // Quelle einzeln, also jeden gespeicherten Bereich noch einmal.
        MapAttribution(
          lines: mapAttributionLines(widget.config.attributions),
          leftInset: widget.config.bottomLeftInset,
        ),
        if (_visibleBounds != null)
          ml.WidgetLayer(
            // Kein Tipp am Marker — die Fassade löst Tipps auf.
            allowInteraction: false,
            markers: [
              for (final marker in visibleMarkers(layers.markers, _visibleBounds!))
                asMapLibreMarker(marker),
            ],
          ),
      ],
    );
  }
}


/// Die Linien-Ebenen, wie die Engine sie baut — für Tests erreichbar
/// (die Platform-View selbst ist im Widget-Test nicht renderbar).
@visibleForTesting
List<ml.Layer> mapLibrePolylineLayers(List<MapViewPolyline> lines, [MapLibreLineCache? cache]) =>
    _MapLibreMapViewState.polylineLayers(lines, cache);

/// Merkt sich die Ebenen des letzten Aufbaus je Gruppe. Gemessen (200
/// Trails, 2026-09-29): Jede Übertragung an MapLibre baut den ganzen
/// GeoJSON-Text neu, 30–60 ms schon auf dem Rechner — und der Karten-Screen
/// baut bei JEDER Positionsmeldung und jedem Kamera-Stillstand neu. Das
/// Paket überträgt eine Ebene nur, wenn sie ungleich der vorigen ist, und
/// „gleich" heißt dort: DIESELBE Punktliste. Deshalb: Sind Stil, Punkte
/// (dieselbe Liste — der Screen merkt sich die geglätteten je Trail),
/// Name und Reihenfolge einer Gruppe unverändert, kommen die alten
/// Ebenen-Objekte zurück, und es wird nichts übertragen.
class MapLibreLineCache {
  final _last = <String, (List<Object?>, List<ml.Layer>)>{};

  static List<Object?> _signature(List<MapViewPolyline> group) => [
        for (final l in group) ...[l.points, l.label],
      ];

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) && a[i] != b[i]) return false;
    }
    return true;
  }

  /// Die Ebenen vom letzten Mal, wenn die Gruppe sich nicht geändert hat.
  List<ml.Layer>? lookup(String key, List<MapViewPolyline> group) {
    final hit = _last[key];
    return hit != null && _same(hit.$1, _signature(group)) ? hit.$2 : null;
  }

  List<ml.Layer> store(String key, List<MapViewPolyline> group, List<ml.Layer> layers) {
    _last[key] = (_signature(group), layers);
    return layers;
  }
}

/// Eine Linie mit runden Ecken und Enden. Das Paket setzt kein Layout, und
/// MapLibre zeichnet ohne `line-join` spitz auf Gehrung — jede Kehre sah
/// aus wie ein Knick (Betreiber, 2026-09-29: „smoother").
class RoundPolylineLayer extends ml.PolylineLayer {
  const RoundPolylineLayer({
    required super.polylines,
    super.color,
    super.width,
    super.dashArray,
  });

  @override
  Map<String, Object> getLayout() => const {'line-join': 'round', 'line-cap': 'round'};
}

/// Namen ENTLANG der Linie (`symbol-placement: line`) wie Straßennamen:
/// MapLibre dreht jeden Buchstaben mit der Kurve, wiederholt den Namen auf
/// langen Trails und lässt ihn weg, wo er mit anderem kollidiert. Dunkle
/// Schrift mit weißem Saum, AUF der Mittellinie (#181, seit 0.74.2;
/// vorher daneben, und das las sich wie ein Name des Nachbarwegs) — der
/// Saum hält sie auf jeder Linienfarbe lesbar, die Karte ist immer hell. Die Schrift ist die des Kartenstils (Noto Sans aus
/// `assets/map_glyphs/`), kein Zeichen braucht Nachladen.
class LineLabelLayer extends ml.Layer<ml.Feature<ml.LineString>> {
  const LineLabelLayer({required List<ml.Feature<ml.LineString>> features})
      // MapLibre zählt Zoom in 512er-Kacheln, die Fassade in 256ern.
      : super(list: features, minZoom: kLineLabelMinZoom - 1);

  @override
  Map<String, Object> getPaint() => {
        'text-color': '#131A16',
        'text-halo-color': '#FFFFFF',
        'text-halo-width': 1.5,
      };

  @override
  Map<String, Object> getLayout() => {
        'symbol-placement': 'line',
        // Token-Schreibweise: Ausdrücke gehen in 0.3.5 durch toJObject().
        'text-field': '{label}',
        // Der Stack-Name, wie er als Ordner in `assets/map_glyphs/` liegt —
        // der Stil wird darauf umgeschrieben (`_rewriteFonts`), diese Ebene
        // nicht; „Noto Sans Medium" fände MapLibre nicht und ließe den
        // Namen still weg.
        'text-font': const ['noto-sans-medium'],
        'text-size': 12,
        'text-max-angle': 35,
        'symbol-spacing': 300,
        'text-keep-upright': true,
      };

  @override
  ml.StyleLayer createStyleLayer(int index) => ml.SymbolStyleLayer(
        id: getLayerId(index),
        sourceId: getSourceId(index),
        paint: getPaint(),
        layout: getLayout(),
        minZoom: minZoom,
        maxZoom: maxZoom,
      );
}
