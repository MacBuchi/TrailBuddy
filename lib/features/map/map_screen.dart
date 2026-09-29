import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/connectivity.dart';
import '../../core/geo.dart';
import '../../models/trail.dart';
import '../feedback/feedback_dialog.dart';
import '../rides/ride_providers.dart';
import '../rides/ride_split_sheet.dart';
import '../rides/ride_task_handler.dart';
import '../rides/ride_track.dart';
import '../official/official_trails.dart';
import '../official/official_trails_layer.dart';
import '../official/official_trails_source.dart';
import '../offline_areas/area_draw.dart';
import '../offline_areas/area_draw_overlay.dart';
import '../offline_areas/area_overlay.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/offline_tool_rail.dart';
import '../trails/grade_shield.dart' show trailColorOf;
import '../trails/outbox_providers.dart';
import '../trails/trail_list.dart';
import '../trails/trail_providers.dart';
import '../trails/trail_sheet.dart';
import '../update/update_banner.dart';
import 'map_buttons.dart';
import 'map_view/map_view.dart';
import 'poi.dart';
import 'poi_layer.dart';
import 'position_provider.dart';
import 'poi_source.dart';

/// Die Karte: hinter der Fassade `map_view/` (MapLibre auf Android,
/// flutter_map im Web), darüber die Trails des eigenen Netzes als Linien.
/// Eigene grün, nur von Buddys belegte blau, gesperrte oder zerstörte in
/// Warnfarbe — die Farbe sagt, was ICH damit zu tun habe, nicht, wie gut
/// der Trail ist. Ein gelber Rand heißt: Ein Buddy hat in den letzten
/// Tagen einen Hinweis dazu geschrieben (#7). Auf Wunsch Orte aus
/// OpenStreetMap als Stecknadeln (#12); gestrichelt die offiziellen
/// Trails (#13), eine eigene Ebene aus Behördendaten. Und die eigene
/// Fahrt (#28): die laufende Spur, unter den Trails.
///
/// **Was ein Tipp trifft, entscheidet die Fassade**, nicht die
/// Zeichenreihenfolge: Linien zuerst (das Netz liegt über den
/// offiziellen Trails), dann die Nadeln. Die Fahrt und die eigene
/// Position sind Kulisse und melden nichts.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _dachCenter = LatLng(48.8, 10.5);
  static const _initialZoom = 6.0;

  final _controller =
      MapViewController(initialCenter: _dachCenter, initialZoom: _initialZoom);
  bool _fittedOnce = false;

  /// Ein Fokus-Wunsch (`mapFocusTrailProvider`) auf einen Trail, der
  /// noch nicht in der Liste ist — etwa aus einer Push-Benachrichtigung
  /// beim Kaltstart, bevor die Trails geladen sind. Eingelöst, sobald er
  /// kommt; ein Wunsch auf einen Trail, den man nie sieht, verfällt.
  String? _pendingFocus;

  /// Die Kamera beim letzten Stillstand — daran hängen Orte und
  /// offizielle Trails (welche Zellen, welcher Ausschnitt).
  MapViewCamera? _camera;

  Timer? _loadDebounce;
  String? _requestedPois;
  String? _requestedOfficial;

  /// Nachladen kurz verzögert, damit ein Wischen über die Karte nicht
  /// zehn Abfragen auslöst.
  static const _loadDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    // Eine Fahrt, die der Prozess-Kill unterbrochen hat, läuft weiter
    // (#28): Der Service hat derweil in die Datei geschrieben.
    unawaited(ref.read(rideProvider.notifier).restore());
    // Was im Ausgangskorb liegt, geht beim Start raus (#30).
    unawaited(ref.read(trailsProvider.notifier).sendOutbox());
    // Die Rückrichtung vom Service-Isolate: jeder Messpunkt kommt auf
    // die Karte, solange die App lebt. Der Port dafür entsteht in
    // `main()` (`initRideCommunication`).
    FlutterForegroundTask.addTaskDataCallback(_onRideTick);
    // Ein Fokus-Wunsch, der VOR dem Aufbau gestellt wurde (Route
    // `/trail/<id>` aus einer Push): `ref.listen` sieht nur Änderungen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _takeFocusWish();
    });
  }

  void _takeFocusWish() {
    final id = ref.read(mapFocusTrailProvider);
    if (id == null) return;
    ref.read(mapFocusTrailProvider.notifier).state = null;
    if (!_focusOn(id)) _pendingFocus = id;
  }

  /// Die Werkzeugleiste „Ebenen" öffnen (seit 0.27.0): abdunkeln, was
  /// nicht gespeichert ist, und einen leeren Entwurf beginnen.
  void _openTools() {
    ref.read(areaDraftProvider.notifier).start();
    ref.read(offlineOverlayProvider.notifier).state = true;
  }

  /// Schließen — über X, Ebenen-Knopf oder Zurück. Steht etwas im
  /// Entwurf, wird gefragt; „Weiter bearbeiten" lässt alles offen.
  Future<void> _closeTools() async {
    final draft = ref.read(areaDraftProvider.notifier);
    if (draft.hasChanges && !await confirmDiscardDraft(context)) return;
    if (!mounted) return;
    draft.discard();
    ref.read(offlineOverlayProvider.notifier).state = false;
  }

  /// Der „Schnappschuss": die Kacheln des Ausschnitts in den Entwurf.
  void _addViewport() {
    final camera = _camera;
    if (camera == null) return;
    final b = camera.bounds;
    final keys = tilesInBounds(AreaBounds(south: b.south, west: b.west, north: b.north, east: b.east));
    if (keys == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Der Ausschnitt ist zu groß — erst näher heranzoomen.')));
      return;
    }
    ref.read(areaDraftProvider.notifier).addAll(keys);
  }

  /// Die Kacheln entlang der eigenen Trails in den Entwurf.
  void _addTrails() {
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final along = AreaShape.alongLines([for (final t in trails) t.points]);
    if (along != null) ref.read(areaDraftProvider.notifier).addAll(along.keys);
  }

  /// Speichern: der Dialog misst, fragt und führt aus; danach ist der
  /// Entwurf leer, die Leiste bleibt offen und zeigt den neuen Bestand.
  Future<void> _saveDraft(AreaDraft draft) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showSaveDraftDialog(context, draft);
    if (!saved || !mounted) return;
    ref.read(areaDraftProvider.notifier).clear();
    final area = draft.adds.isEmpty ? null : ref.read(areaDownloadProvider).result;
    messenger.showSnackBar(SnackBar(
        content: Text(area == null
            ? 'Änderungen gespeichert.'
            : '„${area.name}" gespeichert: ${formatBytes(area.bytes)}.')));
  }

  /// Ein fertiger Strich (Stufe C): seine Kacheln in den Entwurf — oder,
  /// wenn er zu groß war, ein Satz statt einer Rechnung, die hängt.
  void _onStroke(Set<int>? keys) {
    final draft = ref.read(areaDraftProvider.notifier);
    if (keys == null) {
      draft.disarm();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Zu groß gezeichnet — erst näher heranzoomen.')));
      return;
    }
    draft.applyStroke(keys);
  }

  /// Auf den Trail zoomen, wenn er da ist. `false`, wenn nicht.
  ///
  /// Direkt aus der Liste, nicht über `trailByIdProvider`: Im Listener
  /// von `trailsProvider` ist die Familie noch nicht nachgezogen und
  /// antwortete mit dem alten Stand (gemessen: null, obwohl die Liste
  /// den Trail trug).
  bool _focusOn(String id) {
    final t = ref.read(trailsProvider).valueOrNull?.where((x) => x.id == id).firstOrNull;
    if (t == null) return false;
    // Blendet der Filter (#66) genau diesen Trail aus, fällt er — sonst
    // führte eine Push-Meldung auf eine leere Stelle. Und die App sagt es.
    final filter = ref.read(trailListFilterProvider);
    if (!passesTrailFilter(t, filter, seenNotes: ref.read(seenNotesProvider))) {
      ref.read(trailListFilterProvider.notifier).state = const TrailListFilter();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          key: ValueKey('filter-reset-for-focus'),
          content: Text('Filter zurückgesetzt, damit der Trail zu sehen ist.')));
    }
    _fittedOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitTo([t]);
    });
    return true;
  }

  void _onRideTick(Object data) {
    final point = decodeRideTick(data);
    if (point == null) return;
    ref.read(rideProvider.notifier).acceptTick(point);
    unawaited(ref.read(rideProvider.notifier).stopIfExpired());
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onRideTick);
    _loadDebounce?.cancel();
    super.dispose();
  }

  /// Die Linie trägt die Schwierigkeit (seit 0.42.0), nicht mehr die
  /// Beziehung; eine Meldung liegt als Leuchtrand darum ([_borderOf]).
  Color _colorOf(Trail t) => trailColorOf(t, AppColors.mapGrades);

  /// Der Rand um die Linie sagt den Zustand: gemeldet orange (die
  /// Warnung schlägt den Hinweis — meist kommt beides zusammen, und die
  /// Liste nennt beide Wörter), neuer Hinweis eines Buddys gelb, sonst
  /// der weiße Saum.
  (Color, double) _borderOf(Trail t, Set<String> seenNotes) {
    const c = AppColors.mapLines;
    if (t.status.warns) return (c.warning, 4);
    if (t.hasFreshNote(seen: seenNotes)) return (c.note, 4);
    return (c.halo!, c.haloBorderWidth);
  }

  void _onCameraIdle(MapViewCamera camera) {
    if (!mounted) return;
    setState(() => _camera = camera);
  }

  /// Orte und offizielle Trails für den Ausschnitt nachladen — je
  /// Ausschnitt EIN Versuch: Ohne Netz änderte sonst jede Antwort den
  /// Zustand, der Neuaufbau fragte wieder — alle halbe Sekunde.
  void _scheduleLoads({
    required List<PoiCell>? cells,
    required Set<PoiGroup> groups,
    required ({double s, double w, double n, double e})? officialView,
  }) {
    final poiKey = cells == null
        ? null
        : '${cells.join(';')}|${groups.map((g) => g.name).join(',')}';
    final officialKey = officialView == null
        ? null
        : '${officialView.s},${officialView.w},${officialView.n},${officialView.e}';
    final poisDue = poiKey != null && poiKey != _requestedPois;
    final officialDue = officialKey != null && officialKey != _requestedOfficial;
    if (poiKey == null) _requestedPois = null;
    if (officialKey == null) _requestedOfficial = null;
    if (!poisDue && !officialDue) return;
    if (poisDue) _requestedPois = poiKey;
    if (officialDue) _requestedOfficial = officialKey;
    _loadDebounce?.cancel();
    _loadDebounce = Timer(_loadDelay, () {
      if (!mounted) return;
      if (poisDue) {
        unawaited(ref.read(poiControllerProvider.notifier).ensure(cells!, groups));
      }
      if (officialDue) {
        unawaited(ref.read(officialTrailsControllerProvider.notifier).ensure(officialView!));
      }
    });
  }

  void _onHit(Object hit, MapTap tap) {
    switch (hit) {
      case final Trail t:
        // Die Liste kann inzwischen frischer sein als die gezeichnete
        // Linie — das Blatt bekommt den aktuellen Stand.
        showTrailSheet(context, ref.read(trailByIdProvider(t.id)) ?? t);
      case final OfficialTrail o:
        showOfficialTrailSheet(context, o);
      case final Poi p:
        showPoiSheet(context, p);
    }
  }

  /// „Meine Position": die einzige Stelle, die nach der Berechtigung
  /// fragt (`positionFixProvider`). Danach läuft der Punkt mit.
  Future<void> _locateMe() async {
    final messenger = ScaffoldMessenger.of(context);
    final fix = await ref.read(positionFixProvider)();
    if (!mounted) return;
    if (fix == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Position nicht verfügbar — Standort ist aus '
              'oder für TrailBuddy nicht erlaubt.')));
      return;
    }
    _fittedOnce = true;
    final zoom = _controller.zoom;
    _controller.move(LatLng(fix.latitude, fix.longitude), zoom < 14 ? 15 : zoom);
    ref.invalidate(positionStreamProvider);
  }

  void _fitTo(List<Trail> trails) => _fitPoints([for (final t in trails) ...t.points]);

  void _fitPoints(List<LatLng> pts) => _controller.fit(pts, padding: 40, maxZoom: 15);

  /// Fahrt aufzeichnen oder beenden (#28). Beim Beenden ist die Fahrt
  /// gespeichert, BEVOR das Blatt aufgeht — wer es wegwischt, behält.
  Future<void> _toggleRide() async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(rideProvider.notifier);
    if (!notifier.isRunning) {
      final result = await notifier.start();
      if (!mounted) return;
      final text = switch (result) {
        RideStartResult.started =>
          'Fahrt läuft — der Weg wird aufgezeichnet, auch wenn das Telefon '
              'in der Tasche steckt.',
        RideStartResult.noPermission =>
          'Ohne Standortberechtigung lässt sich keine Fahrt aufzeichnen.',
        RideStartResult.noService => 'Der Standortdienst ist ausgeschaltet.',
        RideStartResult.failed => 'Die Fahrt ließ sich nicht starten.',
      };
      messenger.showSnackBar(SnackBar(content: Text(text)));
      return;
    }
    final ride = await notifier.stop();
    if (!mounted) return;
    if (ride == null) return;
    if (ride.points.length < 2) {
      // Nichts gemessen: nichts zu behalten, und ein leeres Blatt wäre
      // eine Frage ohne Gegenstand.
      await ref.read(ridesProvider.notifier).delete(ride.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Fahrt beendet — es kam kein Standort zustande, '
              'nichts gespeichert.')));
      return;
    }
    _fittedOnce = true;
    _fitPoints([for (final p in ride.points) LatLng(p.lat, p.lng)]);
    final discard = await showRideSplitSheet(context, SplitRequest.fromRide(ride), offerDiscard: true);
    if (!mounted || !discard) return;
    await ref.read(ridesProvider.notifier).delete(ride.id);
  }

  /// „Fahrt zerlegen" aus „Meine Fahrten" oder dem GPX-Import (#29):
  /// die Spur einpassen, das Blatt öffnen.
  void _openSplit(SplitRequest request) {
    _fittedOnce = true;
    _fitPoints([for (final p in request.track.points) LatLng(p.lat, p.lon)]);
    unawaited(showRideSplitSheet(context, request));
  }

  @override
  Widget build(BuildContext context) {
    final trailsAsync = ref.watch(trailsProvider);
    final trails = trailsAsync.valueOrNull ?? const <Trail>[];
    final seenNotes = ref.watch(seenNotesProvider);
    // Derselbe Filter wie in der Liste (#66, seit 0.33.0). Er wirkt NUR
    // auf das, was gezeichnet und getroffen wird — „Entlang meiner
    // Trails", Einpassen und Fokus rechnen weiter mit allen.
    final trailFilter = ref.watch(trailListFilterProvider);
    final shownTrails = trailFilter.isActive
        ? [for (final t in trails) if (passesTrailFilter(t, trailFilter, seenNotes: seenNotes)) t]
        : trails;
    final groups = ref.watch(poiGroupsProvider);
    final hidden = ref.watch(poiHiddenKindsProvider);
    final poiState = ref.watch(poiControllerProvider);
    final poiUnavailable = groups.isNotEmpty && poiState.unavailable;
    final officialOn = ref.watch(officialTrailsEnabledProvider);
    final position = ref.watch(positionStreamProvider).valueOrNull;
    final official = ref.watch(officialTrailsControllerProvider);
    final ride = ref.watch(rideProvider);
    final focusRide = ref.watch(mapFocusRideProvider);
    final splitPreview = ref.watch(rideSplitPreviewProvider);
    final canRecord = ref.watch(rideRecordingAvailableProvider);
    final cachedAt = ref.watch(trailsCachedAtProvider);

    // Einmal auf das Netz zoomen, sobald es da ist; danach nie wieder
    // von selbst — wer die Karte verschoben hat, will nicht zurückgeholt
    // werden.
    ref.listen(trailsProvider, (_, next) {
      final list = next.valueOrNull;
      // Ein wartender Fokus-Wunsch geht vor dem Einpassen auf das Netz.
      final pending = _pendingFocus;
      if (pending != null && list != null && _focusOn(pending)) {
        _pendingFocus = null;
      }
      if (!_fittedOnce && list != null && list.isNotEmpty) {
        _fittedOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitTo(list);
        });
      }
    });
    ref.listen(mapFocusTrailProvider, (_, id) {
      if (id == null) return;
      _takeFocusWish();
    });
    // Verbindung zurück ⇒ Ausgangskorb losschicken (#30). Genau hier
    // und nicht am App-Resume: Wer aus dem Wald nach Hause kommt, ohne
    // die App zu schließen, hat kein Resume — aber einen Netzwechsel.
    ref.listen<bool>(noConnectivityProvider, (previous, next) {
      if (previous == true && next == false) {
        unawaited(ref.read(trailsProvider.notifier).sendOutbox());
      }
    });
    ref.listen(mapFocusRideProvider, (_, r) {
      if (r == null) return;
      _fittedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitPoints([for (final p in r.points) LatLng(p.lat, p.lng)]);
      });
    });
    ref.listen(mapSplitRequestProvider, (_, request) {
      if (request == null) return;
      ref.read(mapSplitRequestProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSplit(request);
      });
    });
    // „Auf der Karte zeigen" aus „Meine Bereiche" (Konzept-Schritt 3).
    ref.listen(mapFocusAreaProvider, (_, area) {
      if (area == null) return;
      _fittedOnce = true;
      final b = area.bounds;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitPoints([LatLng(b.south, b.west), LatLng(b.north, b.east)]);
      });
      ref.read(mapFocusAreaProvider.notifier).state = null;
    });

    // Was der Ausschnitt braucht — und was davon fehlt, wird nachgeladen.
    final camera = _camera;
    final cells = poiCellsFor(camera, groups);
    final officialView = officialViewFor(camera, official, enabled: officialOn);
    _scheduleLoads(cells: cells, groups: groups, officialView: officialView);

    // Offline-Karten: Solange die Werkzeugleiste offen ist, liegt die
    // Abdunkelung unter allem — gespeicherte Kacheln sind die Löcher.
    // Beobachtet werden die Bereiche nur dann; sonst kostet jeder
    // Kamera-Stillstand eine Rechnung, die niemand sieht.
    final overlayOn = ref.watch(offlineOverlayProvider);
    final overlayAreas =
        overlayOn ? ref.watch(storedAreasProvider).valueOrNull ?? const <StoredArea>[] : null;
    // Um den Bestand ein durchgehender Rand in der Textfarbe des Modus
    // (Design Turn 2: dunkel hell, hell #131A16).
    final coverage = overlayAreas != null && camera != null
        ? offlineCoverage(overlayAreas, camera.bounds, outlineColor: AppPalette.of(context).text)
        : null;
    final mask = coverage?.mask;
    // Offene Änderungen über der Abdunkelung — Schraffur in der
    // Gegenhelligkeit ihres Grunds und ein gestrichelter Rand: „kommt
    // dazu" hell auf dunkel, „fällt weg" dunkel auf hell und gespiegelt;
    // nur mit Werkzeugleiste.
    final toolsOpen = overlayOn;
    final draft = overlayOn ? ref.watch(areaDraftProvider) : null;
    final drawTool = draft?.tool;
    final pending = draft != null && camera != null ? draftLayers(draft, camera) : null;

    final layers = MapViewLayers(
      polygons: [
        ?mask,
        ...?pending?.polygons,
      ],
      circles: [
        if (position != null && position.accuracy > 0)
          MapViewCircle(
            center: LatLng(position.latitude, position.longitude),
            radiusM: position.accuracy,
            fillColor: AppColors.mapLines.ride.withValues(alpha: 0.12),
            borderColor: AppColors.mapLines.ride.withValues(alpha: 0.35),
            borderWidth: 1,
          ),
      ],
      polylines: [
        // Ganz unten der Rand des Bestands und die Schraffur offener
        // Änderungen (ohne Kennung, ein Tipp geht hindurch); dann die
        // offiziellen Trails, darüber die Fahrt, oben das Netz — ein Tipp
        // trifft zuerst das Netz.
        ...?coverage?.outline,
        ...?pending?.lines,
        if (officialOn && camera != null && camera.zoom >= kOfficialMinZoom)
          ...officialPolylines(official),
        // Während das Zerlege-Blatt offen ist, zeichnet es die Fahrt
        // selbst — in Abschnitten, mit den Griffen.
        if (splitPreview.isNotEmpty)
          ...splitPreview
        else if (focusRide != null)
          _ridePolyline(focusRide.points),
        if (ride != null && ride.points.length >= 2) _ridePolyline(ride.points),
        for (final t in shownTrails)
          MapViewPolyline(
            points: t.points,
            color: t.pending ? _colorOf(t).withValues(alpha: 0.6) : _colorOf(t),
            width: 4,
            // Wartet im Ausgangskorb (#30): gestrichelt, wie eine
            // Zusage, die noch nicht eingelöst ist. Ab S4 gestrichelt wie
            // eine Skiroute — schwarz allein unterschiede S3 nicht von S5.
            dash: t.pending
                ? const [12, 8]
                : (t.grade ?? 0) >= 4
                    ? const [14, 10]
                    : null,
            borderColor: _borderOf(t, seenNotes).$1,
            borderWidth: _borderOf(t, seenNotes).$2,
            hitValue: t,
          ),
      ],
      markers: [
        if (camera != null && cells != null)
          ...poiMarkers(poiState, camera, cells, groups, hidden),
        if (position != null)
          MapViewMarker(
            key: const ValueKey('my-position'),
            point: LatLng(position.latitude, position.longitude),
            width: 22,
            height: 22,
            child: const _PositionDot(),
          ),
      ],
    );

    return PopScope(
      // Offen gilt: Zurück schließt die Werkzeugleiste (mit Rückfrage),
      // statt die App zu verlassen.
      canPop: !toolsOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeTools());
      },
      child: Scaffold(
      body: Stack(
        children: [
          MapView(
            config: MapViewConfig(
              initialCenter: _dachCenter,
              initialZoom: _initialZoom,
              // OSM liefert Kacheln nur bis Zoom 19; unten reicht 3.
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: AppColors.mapBackground,
              // Die Quellen der offiziellen Trails, solange die Ebene an
              // ist und eine ihrer Regionen geladen.
              bottomLeftInset: toolsOpen ? kRailWidth + 8 : 0,
              attributions: [
                if (officialOn)
                  for (final src in official.loadedSources)
                    '${src.attribution} (${src.license})',
              ],
              onHit: _onHit,
              onCameraIdle: _onCameraIdle,
            ),
            controller: _controller,
            layers: layers,
          ),
          // Solange ein Werkzeug auf seinen Strich wartet, liegt die
          // Zeichenfläche über der Karte und hält sie fest.
          if (drawTool != null && camera != null)
            Positioned.fill(
              child: AreaDrawOverlay(camera: camera, tool: drawTool, onStroke: _onStroke),
            ),
          if (trailsAsync.isLoading && trails.isEmpty)
            const Center(child: CircularProgressIndicator()),
          // Solange ein Werkzeug scharf ist, gehört der Platz oben der
          // Zeile, was der nächste Strich tut.
          if (trailsAsync.hasValue && trails.isEmpty && drawTool == null)
            const _EmptyHint(),
          // Die Banner oben untereinander, nicht übereinander: Update,
          // Ausgangskorb und — solange einer gilt — der Trail-Filter.
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const UpdateBanner(),
                  const _OutboxBanner(),
                  if (trailFilter.isActive)
                    _TrailFilterBanner(
                        filter: trailFilter, shown: shownTrails.length, total: trails.length),
                ],
              ),
            ),
          ),
          if (ride != null || focusRide != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 72, 16, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ride != null) _RideStatusCard(ride),
                      if (focusRide != null) _FocusRideCard(focusRide),
                    ],
                  ),
                ),
              ),
            ),
          // Die Werkzeugleiste „Ebenen" (seit 0.27.0) links, mittig:
          // unten liegen Maßstab und Quellenhinweis, oben die Banner —
          // beide bleiben frei. Scrollt, wenn der Schirm zu kurz ist.
          if (toolsOpen)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 56, 0, 64),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    child: OfflineToolRail(
                      onFilter: () => showPoiFilterSheet(context),
                      onSnapshot: _addViewport,
                      onTrails: trails.isEmpty ? null : _addTrails,
                      onManage: () => context.go('/profile/areas'),
                      onSave: _saveDraft,
                      onClose: _closeTools,
                    ),
                  ),
                ),
              ),
            ),
          // Die Knöpfe rechts (seit 0.27.0; vorher links, wo jetzt die
          // Werkzeugleiste und — auf beiden Engines — Maßstab und
          // Quellenhinweis stehen). Die Glühbirne (PilzBuddy-Muster):
          // melden kann man immer, also steht sie immer da.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (officialOn && official.unavailable)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Text('Offizielle Trails gerade nicht erreichbar'),
                        ),
                      ),
                    // Ohne Empfang kommt das Netz aus der Kopie (#32). Das
                    // gehört gesagt, sonst hält man den Stand für aktuell.
                    if (cachedAt != null)
                      Card(
                        key: const ValueKey('cached-notice'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text('Kein Empfang — Trails vom ${formatCachedAt(cachedAt)}'),
                        ),
                      ),
                    if (poiUnavailable)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Text('Orte gerade nicht erreichbar'),
                        ),
                      ),
                    // Von oben nach unten wie im Entwurf (3a): Idee, Ebenen,
                    // Position — und unten, am Daumen, die Aufnahme.
                    const SizedBox(height: 4),
                    MapRoundButton(
                      tooltip: 'Idee oder Fehler melden',
                      icon: Icons.lightbulb_outline,
                      onPressed: () => showFeedbackFlow(context, ref),
                    ),
                    const SizedBox(height: 10),
                    MapRoundButton(
                      key: const ValueKey('layers-button'),
                      tooltip: 'Ebenen und Orte',
                      icon: Icons.layers_outlined,
                      // Öffnet und schließt die Werkzeugleiste — dasselbe
                      // wie ihr X und die Zurück-Taste. Offen: Rand in der
                      // Marke, die Leiste links gehört zu diesem Knopf.
                      active: toolsOpen,
                      onPressed: toolsOpen ? _closeTools : _openTools,
                    ),
                    const SizedBox(height: 10),
                    MapRoundButton(
                      tooltip: 'Meine Position',
                      icon: Icons.my_location,
                      onPressed: _locateMe,
                    ),
                    if (canRecord) ...[
                      const SizedBox(height: 14),
                      RecordButton(
                        key: const ValueKey('ride-button'),
                        recording: ride != null,
                        onPressed: _toggleRide,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// „2 warten auf Übertragung" — antippen schickt sie los (#30). Steht
/// unter dem Update-Banner, damit sich beide nicht überdecken.
class _OutboxBanner extends ConsumerWidget {
  const _OutboxBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingJobCountProvider);
    final failed = ref.watch(failedJobCountProvider);
    if (count == 0) return const SizedBox.shrink();
    final waiting = count - failed;
    final text = [
      if (waiting > 0) '$waiting ${waiting == 1 ? 'wartet' : 'warten'} auf Übertragung',
      if (failed > 0) '$failed abgelehnt',
    ].join(' · ');
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Card(
          key: const ValueKey('outbox-banner'),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ListTile(
            dense: true,
            leading: Icon(failed > 0 ? Icons.error_outline : Icons.schedule),
            title: Text(text),
            subtitle: Text(failed > 0 && waiting == 0
                ? 'Entscheiden in der Trail-Liste'
                : 'Antippen zum Senden — sonst beim nächsten Netz'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final r = await ref.read(trailsProvider.notifier).sendOutbox();
              messenger.showSnackBar(SnackBar(
                  content: Text(r.sent > 0
                      ? '${r.sent} übertragen'
                      : 'Noch kein Netz — bleibt im Ausgangskorb.')));
            },
          ),
        ),
      ),
    );
  }
}

/// Ein aktiver Trail-Filter meldet sich auf der Karte (#66; PilzBuddy
/// #154): Eine Karte, die still ausblendet, sieht aus, als fehlten
/// Trails. Das X setzt ihn zurück — für Liste und Karte.
class _TrailFilterBanner extends ConsumerWidget {
  const _TrailFilterBanner({required this.filter, required this.shown, required this.total});

  final TrailListFilter filter;
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        key: const ValueKey('map-filter-banner'),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.filter_alt_outlined),
          title: Text('Gefiltert: ${filter.describe()}'),
          subtitle: Text('$shown von $total ${total == 1 ? 'Trail' : 'Trails'}'),
          trailing: IconButton(
            key: const ValueKey('map-filter-reset'),
            tooltip: 'Filter zurücksetzen',
            icon: const Icon(Icons.close),
            onPressed: () => ref.read(trailListFilterProvider.notifier).state = const TrailListFilter(),
          ),
        ),
      );
}

/// „28.9., 10:12" — Tag und Uhrzeit des zwischengespeicherten Stands.
String formatCachedAt(DateTime at) {
  final l = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}.${l.month}., ${two(l.hour)}:${two(l.minute)}';
}

/// Die Fahrt: Kulisse ohne Kennung — ein Tipp gilt weiter dem Trail.
MapViewPolyline _ridePolyline(List<RidePoint> points) => MapViewPolyline(
      points: [for (final p in thinnedRide(points)) LatLng(p.lat, p.lng)],
      color: AppColors.mapLines.ride.withValues(alpha: 0.75),
      width: 4,
      borderColor: AppColors.mapLines.halo,
      borderWidth: AppColors.mapLines.haloBorderWidth,
    );

/// „Fahrt läuft · 1,2 km · 12 min" — die Rückmeldung, dass aufgezeichnet
/// wird, auch wenn die Linie noch kurz ist.
class _RideStatusCard extends StatelessWidget {
  const _RideStatusCard(this.ride);

  final RecordedRide ride;

  @override
  Widget build(BuildContext context) {
    final length = rideLengthM(ride.points);
    final duration = DateTime.now().toUtc().difference(ride.startedAt);
    return Card(
      key: const ValueKey('ride-status'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fiber_manual_record, size: 14, color: AppColors.mapLines.warning),
            const SizedBox(width: 8),
            Text('Fahrt läuft · ${formatMeters(length)} · ${rideDurationLabel(duration)}'),
          ],
        ),
      ),
    );
  }
}

/// Eine gespeicherte Fahrt auf der Karte, bis sie weggetippt wird.
class _FocusRideCard extends ConsumerWidget {
  const _FocusRideCard(this.ride);

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        key: const ValueKey('focus-ride'),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Fahrt · ${formatMeters(ride.lengthM)} · '
                  '${rideDurationLabel(ride.duration)}'),
              IconButton(
                tooltip: 'Fahrt ausblenden',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => ref.read(mapFocusRideProvider.notifier).state = null,
              ),
            ],
          ),
        ),
      );
}

class _PositionDot extends StatelessWidget {
  const _PositionDot();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Deine Position',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.mapLines.ride,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
          ),
        ),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Noch keine Trails. Importiere deine GPX-Dateien im Profil '
                'oder verbinde dich mit Buddys — du siehst, was sie gefahren sind.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      );
}
