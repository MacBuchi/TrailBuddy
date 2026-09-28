import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import '../../../core/connectivity.dart';
import '../../offline_areas/area_providers.dart';
import '../base_map_providers.dart';
import '../finite_camera_constraint.dart';
import '../online_map.dart';
import 'map_view.dart';

/// Die flutter_map-Engine: der Web-Pfad und der Rückfall auf Android,
/// wenn der MapLibre-Style nicht baut. Online die Vektorkarte vom Host
/// (`online_map.dart`, kachelweise per Range-Anfrage); darunter die
/// mitgelieferte Übersicht, sobald kein Empfang besteht oder die
/// Online-Karte nicht aufgeht.
class FlutterMapView extends ConsumerStatefulWidget {
  const FlutterMapView({
    super.key,
    required this.config,
    required this.controller,
    required this.layers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewLayers layers;

  @override
  ConsumerState<FlutterMapView> createState() => _FlutterMapViewState();
}

class _FlutterMapViewState extends ConsumerState<FlutterMapView>
    implements MapViewCameraDelegate {
  final _mapController = MapController();

  MapViewCamera _cameraOf(MapCamera camera) {
    final b = camera.visibleBounds;
    return MapViewCamera(
      center: camera.center,
      bounds: MapViewBounds(
          west: b.west, east: b.east, south: b.south, north: b.north),
      size: camera.nonRotatedSize,
    );
  }

  void _reportIdle(MapCamera camera) =>
      widget.config.onCameraIdle?.call(_cameraOf(camera));

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
  }

  @override
  void didUpdateWidget(covariant FlutterMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detach(this);
      widget.controller.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    _mapController.dispose();
    super.dispose();
  }

  // ---- MapViewCameraDelegate ----
  @override
  void move(LatLng center, double zoom) => _mapController.move(center, zoom);

  @override
  void fit(List<LatLng> points, {required double padding, required double maxZoom}) {
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: EdgeInsets.all(padding),
      maxZoom: maxZoom,
    ));
  }

  @override
  LatLng get center => _mapController.camera.center;

  @override
  double get zoom => _mapController.camera.zoom;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final layers = widget.layers;
    // Die Online-Karte — null, solange kein Manifest da ist oder das
    // Archiv nicht aufgeht (dann bleibt die Übersicht die Karte).
    final online = ref.watch(onlineMapStyleProvider).valueOrNull;
    // Die Übersicht nur, wenn sie gebraucht wird: ohne Empfang oder ohne
    // Online-Karte — siehe base_map_providers.dart. Dieselbe Regel wie in
    // der MapLibre-Engine (maplibre_style_provider.dart).
    final showBaseMap = online == null || ref.watch(noConnectivityProvider);
    final baseStyle =
        showBaseMap ? ref.watch(baseMapStyleProvider).valueOrNull : null;
    // Die gespeicherten Bereiche in demselben Fall, über der Übersicht
    // (Konzept-Schritt 3) — dieselbe Regel wie in der MapLibre-Engine.
    final areas = showBaseMap ? ref.watch(areaMapStyleProvider).valueOrNull : null;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: config.initialCenter,
        initialZoom: config.initialZoom,
        minZoom: config.minZoom,
        maxZoom: config.maxZoom,
        backgroundColor: config.backgroundColor,
        // Norden bleibt oben: Eine gedrehte Karte passiert beim Zoomen
        // mit zwei Fingern aus Versehen, und zurückdrehen kann man sie
        // ohne Kompass nicht.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        // NaN-/Infinity-Kamerazustände aus Gesten-Grenzfällen verwerfen
        // (PilzBuddy #141/#151) — Details am Wächter.
        cameraConstraint: const FiniteCameraConstraint(),
        onTap: (tapPosition, latLng) {
          final camera = _mapController.camera;
          config.handleTap(
            MapTap(
              point: latLng,
              screenPoint: tapPosition.relative ??
                  camera.latLngToScreenOffset(latLng),
              camera: _cameraOf(camera),
            ),
            layers,
          );
        },
        onMapReady: () => _reportIdle(_mapController.camera),
        onMapEvent: (event) {
          // „Zum Stehen gekommen": Gesten- und Animationsenden, nicht
          // jede Bewegung. Das Mausrad hat kein Ende-Ereignis, sein
          // Einzelschritt IST der Stillstand.
          if (event is MapEventMoveEnd ||
              event is MapEventFlingAnimationEnd ||
              event is MapEventDoubleTapZoomEnd ||
              event is MapEventScrollWheelZoom) {
            _reportIdle(event.camera);
          }
        },
      ),
      children: [
        if (baseStyle != null)
          vmt.VectorTileLayer(
            key: const ValueKey('base-map'),
            tileProviders: baseStyle.tileProviders,
            theme: baseStyle.theme,
            // Raster, nicht Vektor (PilzBuddy #119): Der Vektor-Modus
            // rendert bei jeder Zwischen-Zoomstufe neu, und diese Schicht
            // endet bei Zoom 7 — es gibt keine Schärfe zu verlieren.
            layerMode: vmt.VectorTileLayerMode.raster,
            maximumTileSubstitutionDifference: 1,
          ),
        if (areas != null)
          vmt.VectorTileLayer(
            key: ValueKey(areas.tileProviders),
            tileProviders: areas.tileProviders,
            theme: areas.theme,
            layerMode: vmt.VectorTileLayerMode.vector,
            maximumZoom: 19,
            maximumTileSubstitutionDifference: 1,
          ),
        if (online != null)
          vmt.VectorTileLayer(
            // Der Schlüssel hängt an der QUELLE (PilzBuddy #144): Ein
            // neues Archiv (neues Manifest) bekommt einen frischen Layer
            // mit frischen Caches, statt Kacheln aus dem geschlossenen
            // alten zu verlangen.
            key: ValueKey(online.tileProviders),
            tileProviders: online.tileProviders,
            theme: online.theme,
            // Vektor-Modus rendert scharf in jeder Zoomstufe; die Daten
            // enden bei Zoom 13, darüber wird skaliert.
            layerMode: vmt.VectorTileLayerMode.vector,
            maximumZoom: 19,
            maximumTileSubstitutionDifference: 1,
          ),
        if (layers.circles.isNotEmpty)
          CircleLayer(circles: [
            for (final c in layers.circles)
              CircleMarker(
                point: c.center,
                radius: c.radiusM,
                useRadiusInMeter: true,
                color: c.fillColor,
                borderColor: c.borderColor ?? Colors.transparent,
                borderStrokeWidth: c.borderWidth,
              ),
          ]),
        if (layers.polylines.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final line in layers.polylines)
                Polyline(
                  points: line.points,
                  color: line.color,
                  strokeWidth: line.width,
                  pattern: line.dash == null
                      ? const StrokePattern.solid()
                      : StrokePattern.dashed(segments: line.dash!),
                  borderStrokeWidth: line.borderWidth,
                  borderColor: line.borderColor ?? Colors.transparent,
                ),
            ],
          ),
        if (layers.markers.isNotEmpty)
          // Kein Tipp am Marker: Die Fassade löst Tipps auf (map_view.dart).
          IgnorePointer(
            child: MarkerLayer(markers: [
              for (final m in layers.markers)
                Marker(
                  key: m.key,
                  point: m.point,
                  width: m.width,
                  height: m.height,
                  alignment: m.alignment,
                  child: m.child,
                ),
            ]),
          ),
        RichAttributionWidget(
          animationConfig: const ScaleRAWA(),
          attributions: [
            const TextSourceAttribution('OpenStreetMap-Mitwirkende'),
            const TextSourceAttribution('Protomaps', prependCopyright: false),
            for (final text in config.attributions)
              TextSourceAttribution(text, prependCopyright: false),
          ],
        ),
      ],
    );
  }
}
