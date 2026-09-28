import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../offline_areas/area_overlay.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_sheet.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/offline_maps_sheet.dart';
import '../trails/outbox_providers.dart';
import '../trails/trail_providers.dart';
import '../trails/trail_sheet.dart';
import '../update/update_banner.dart';
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

  /// Der Scaffold der Karte — das persistente Blatt „Offline-Karten"
  /// hängt an IHM, nicht an dem der Reiter-Hülle (offline_maps_sheet.dart).
  final _scaffoldKey = GlobalKey<ScaffoldState>();
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

  /// „Bereich speichern" mit dem AKTUELLEN Ausschnitt und den Trails.
  void _openSaveArea(BuildContext context) {
    final camera = _camera;
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    showSaveAreaSheet(
      context,
      viewport: camera == null
          ? null
          : AreaBounds(
              south: camera.bounds.south,
              west: camera.bounds.west,
              north: camera.bounds.north,
              east: camera.bounds.east),
      // Die Kacheln entlang der Trails, nicht ein Rechteck um alle (0.24.0).
      aroundTrails: AreaShape.alongLines([for (final t in trails) t.points]),
    );
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

  Color _colorOf(Trail t) {
    if (t.status.warns) return AppColors.warningAmber;
    return t.isOwn ? AppColors.trailGreen : AppColors.friendBlue;
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

    // Offline-Karten (Stufe B): Solange das Blatt offen ist, liegt die
    // Abdunkelung unter allem — gespeicherte Kacheln sind die Löcher.
    // Beobachtet werden die Bereiche nur dann; sonst kostet jeder
    // Kamera-Stillstand eine Rechnung, die niemand sieht.
    final overlayOn = ref.watch(offlineOverlayProvider);
    final overlayAreas =
        overlayOn ? ref.watch(storedAreasProvider).valueOrNull ?? const <StoredArea>[] : null;
    final mask = overlayAreas != null && camera != null
        ? offlineCoverageMask(overlayAreas, camera.bounds, cameraZoom: camera.zoom)
        : null;

    final layers = MapViewLayers(
      polygons: [?mask],
      circles: [
        if (position != null && position.accuracy > 0)
          MapViewCircle(
            center: LatLng(position.latitude, position.longitude),
            radiusM: position.accuracy,
            fillColor: AppColors.positionDot.withValues(alpha: 0.12),
            borderColor: AppColors.positionDot.withValues(alpha: 0.35),
            borderWidth: 1,
          ),
      ],
      polylines: [
        // Unten die offiziellen Trails, darüber die Fahrt, oben das Netz —
        // ein Tipp trifft zuerst das Netz.
        if (officialOn && camera != null && camera.zoom >= kOfficialMinZoom)
          ...officialPolylines(official),
        // Während das Zerlege-Blatt offen ist, zeichnet es die Fahrt
        // selbst — in Abschnitten, mit den Griffen.
        if (splitPreview.isNotEmpty)
          ...splitPreview
        else if (focusRide != null)
          _ridePolyline(focusRide.points),
        if (ride != null && ride.points.length >= 2) _ridePolyline(ride.points),
        for (final t in trails)
          MapViewPolyline(
            points: t.points,
            color: t.pending ? _colorOf(t).withValues(alpha: 0.6) : _colorOf(t),
            width: 4,
            // Wartet im Ausgangskorb (#30): gestrichelt, wie eine
            // Zusage, die noch nicht eingelöst ist.
            dash: t.pending ? const [12, 8] : null,
            // Neuer Hinweis eines Buddys (#7): ein gelber Leuchtrand, die
            // Linie behält ihre Farbe.
            borderColor: t.hasFreshNote(seen: seenNotes) ? AppColors.noteYellow : null,
            borderWidth: t.hasFreshNote(seen: seenNotes) ? 4 : 0,
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

    return Scaffold(
      key: _scaffoldKey,
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
          if (trailsAsync.isLoading && trails.isEmpty)
            const Center(child: CircularProgressIndicator()),
          if (trailsAsync.hasValue && trails.isEmpty)
            const _EmptyHint(),
          const UpdateBanner(),
          const _OutboxBanner(),
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
          // Die Glühbirne (PilzBuddy-Muster): melden kann man immer, also
          // steht sie immer da — klein, unten links, wo weder die
          // Attribution (rechts) noch die Banner (oben) liegen. Der
          // Orte-Filter steht aus demselben Grund darüber.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    if (canRecord) ...[
                      FloatingActionButton(
                        key: const ValueKey('ride-button'),
                        heroTag: 'ride',
                        tooltip: ride == null ? 'Fahrt aufzeichnen' : 'Fahrt beenden',
                        backgroundColor: ride == null ? null : AppColors.warningAmber,
                        foregroundColor: ride == null ? null : Colors.white,
                        onPressed: _toggleRide,
                        child: Icon(ride == null ? Icons.fiber_manual_record : Icons.stop),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FloatingActionButton.small(
                      heroTag: 'locate',
                      tooltip: 'Meine Position',
                      onPressed: _locateMe,
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'poi-filter',
                      tooltip: 'Ebenen und Orte',
                      // „Offline-Karten" wohnt im Blatt, nicht als
                      // eigener Knopf: Die Spalte lief auf einem kleinen
                      // Telefon sonst quer über (im Test gesehen).
                      onPressed: () => showPoiFilterSheet(
                        context,
                        onOfflineMaps: () => showOfflineMapsSheet(
                          _scaffoldKey.currentState!,
                          ref,
                          // Ausschnitt und Trails vom ZEITPUNKT des
                          // Speicherns, nicht vom Öffnen des Blatts — man
                          // schiebt die Karte ja, während es offen ist.
                          onSaveArea: () => _openSaveArea(context),
                        ),
                      ),
                      child: const Icon(Icons.layers_outlined),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'feedback',
                      tooltip: 'Idee oder Fehler melden',
                      onPressed: () => showFeedbackFlow(context, ref),
                      child: const Icon(Icons.lightbulb_outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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

/// „28.9., 10:12" — Tag und Uhrzeit des zwischengespeicherten Stands.
String formatCachedAt(DateTime at) {
  final l = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}.${l.month}., ${two(l.hour)}:${two(l.minute)}';
}

/// Die Fahrt: Kulisse ohne Kennung — ein Tipp gilt weiter dem Trail.
MapViewPolyline _ridePolyline(List<RidePoint> points) => MapViewPolyline(
      points: [for (final p in thinnedRide(points)) LatLng(p.lat, p.lng)],
      color: AppColors.rideTrack.withValues(alpha: 0.75),
      width: 4,
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
            const Icon(Icons.fiber_manual_record, size: 14, color: AppColors.warningAmber),
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
            color: AppColors.positionDot,
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
