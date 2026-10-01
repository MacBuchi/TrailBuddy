// Das Blatt „Zum Trailkopf" (#158 Schritt 4, Konzept-Routing 4): ein Fix
// für den Standort, der Wegegraph aus den gespeicherten Bereichen, A* zum
// Trailkopf — die Linie als Vorschau auf der Karte, darunter Länge,
// Höhenmeter, Zeit, der Mix der Wegklassen und der Satz zum Wanderweg.
// Dazu „Als GPX" (#150) und „Anfahrt" (#151) als die Übergabe, die auch
// ohne Bereich trägt.
//
// Drei Dinge, die man wissen muss:
// - **Der Fix kommt beim Öffnen, nicht beim Tipp** — das Blatt IST der
//   Tipp auf „Zum Trailkopf"; `positionFixProvider` darf nach der
//   Berechtigung fragen, ein zweiter Knopf davor wäre eine Hürde ohne
//   Gewinn. Ohne Standort gibt es keinen Startpunkt und das Blatt sagt es.
// - **Gerechnet wird NUR aus den Bereichen** (Konzept-Routing 1, Nicht-
//   Ziele): `partial` heißt kein Weg, nicht ein halber — und das Blatt
//   nennt den Ebenen-Knopf.
// - **Das Profil lässt sich im Blatt umschalten** (Entscheidung 8.1): Der
//   Graph bleibt, nur die Suche läuft neu; die Einstellung im Profil
//   bleibt, was sie war — hier wird für DIESE Planung gewählt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/errors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../core/gpx_share.dart';
import '../../core/line_geometry.dart';
import '../../models/trail.dart';
import '../map/map_view/map_view.dart';
import '../map/position_provider.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/height_tiles.dart';
import '../profile/profile_providers.dart';
import '../rides/ride_providers.dart';
import '../rides/ride_track.dart';
import '../rides/road_index.dart' show RoadCoverage;
import '../trails/gpx_writer.dart';
import '../trails/trail_navigation.dart';
import 'ride_calibrator.dart';
import 'road_graph.dart';
import 'road_graph_loader.dart';
import 'route_profile.dart';
import 'trail_head_providers.dart';
import 'trail_head_route.dart';

/// Zeigt das Blatt über der Karte; die Vorschau lebt mit dem Blatt und
/// wird HIER geleert, nach dem `await` — im `dispose` des Blatts wäre
/// `ref` schon tot (dasselbe Muster wie das Zerlege-Blatt).
Future<void> showTrailHeadSheet(BuildContext context, Trail trail) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Die Karte soll sichtbar bleiben: Sie zeigt die Linie.
    barrierColor: Colors.black12,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scroll) => _TrailHeadSheet(trail: trail, scroll: scroll),
    ),
  );
  container.read(trailHeadPreviewProvider.notifier).state = const [];
}

enum _Phase { locating, loading, done }

/// Was die Rechnung ergeben hat, bevor es einen Graphen gab.
enum _Blocker { noPosition, noArea, partialArea }

class _TrailHeadSheet extends ConsumerStatefulWidget {
  const _TrailHeadSheet({required this.trail, required this.scroll});

  final Trail trail;
  final ScrollController scroll;

  @override
  ConsumerState<_TrailHeadSheet> createState() => _TrailHeadSheetState();
}

class _TrailHeadSheetState extends ConsumerState<_TrailHeadSheet> {
  _Phase _phase = _Phase.locating;
  _Blocker? _blocker;
  int _tilesFound = 0, _tilesNeeded = 0;
  RoadGraph? _graph;
  LatLng? _from;
  late RiderProfile _profile;
  TrailHeadPlan? _plan;

  @override
  void initState() {
    super.initState();
    _profile = ref.read(riderProfileProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _compute());
  }

  Future<void> _compute() async {
    final fix = await ref.read(positionFixProvider)();
    if (!mounted) return;
    if (fix == null) {
      setState(() {
        _phase = _Phase.done;
        _blocker = _Blocker.noPosition;
      });
      return;
    }
    final from = LatLng(fix.latitude, fix.longitude);
    setState(() {
      _from = from;
      _phase = _Phase.loading;
    });
    List<StoredArea> areas;
    try {
      areas = await ref.read(storedAreasProvider.future);
    } catch (_) {
      areas = const [];
    }
    if (!mounted) return;
    HeightReader? heights;
    try {
      heights = await ref.read(areaHeightReaderProvider.future);
    } catch (e, s) {
      // Ohne Höhen rechnet die Suche flach und sagt es; der Weg steht
      // trotzdem.
      logError('Höhen für „Zum Trailkopf" öffnen', e, s);
    }
    if (!mounted) return;
    final store = ref.read(areaStoreProvider);
    final open = ref.read(areaArchiveOpenerProvider);
    final head = widget.trail.start;
    RoadGraphLoadResult roads;
    try {
      roads = await loadRoadGraph(
        areas: areas,
        box: LatBox.of([from, head]),
        open: (a) => open(store, a),
        heights: heights,
        marginM: kTrailHeadMarginM,
      );
    } catch (e, s) {
      logError('Wege für „Zum Trailkopf" lesen', e, s);
      roads = (
        graph: null,
        coverage: RoadCoverage.none,
        tilesNeeded: 0,
        tilesFound: 0,
        joins: 0,
        crossings: 0,
        edgesWithoutHeights: 0,
      );
    }
    if (!mounted) return;
    final graph = roads.graph;
    if (graph == null) {
      setState(() {
        _phase = _Phase.done;
        _blocker = roads.coverage == RoadCoverage.partial ? _Blocker.partialArea : _Blocker.noArea;
        _tilesFound = roads.tilesFound;
        _tilesNeeded = roads.tilesNeeded;
      });
      return;
    }
    _graph = graph;
    _replan();
  }

  /// Die Suche auf dem stehenden Graphen — beim ersten Mal und bei jedem
  /// Profilwechsel.
  void _replan() {
    // Mit den gelernten Werten des Profils (Schritt 6), wo es welche gibt.
    final plan = planTrailHeadRoute(_graph!, _from!, widget.trail.start, ref.read(calibratedRiderProvider(_profile)));
    setState(() {
      _phase = _Phase.done;
      _plan = plan;
    });
    ref.read(trailHeadPreviewProvider.notifier).state = previewLinesOf(plan.route);
  }

  /// Den Weg als geplante Fahrt in „Meine Fahrten" (#158 Schritt 5) —
  /// damit er auf der Karte bleibt und als GPX wiederkommt.
  Future<void> _saveRide() async {
    final route = _plan?.route;
    if (route == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now().toUtc();
    final ride = await ref.read(ridesProvider.notifier).savePlanned(
          name: 'Zum Trailkopf: ${widget.trail.displayName}',
          points: [
            for (final p in route.points) RidePoint(lat: p.latitude, lng: p.longitude, at: now, accuracyM: 0),
          ],
          duration: Duration(seconds: route.summary.timeS.round()),
          profile: _profile.name,
        );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(ride == null
            ? 'Der Weg ließ sich nicht speichern.'
            : 'Als geplante Fahrt gespeichert — im Profil unter „Meine Fahrten".')));
  }

  void _exportGpx() {
    final route = _plan?.route;
    if (route == null) return;
    final track = trailHeadToGpx(route, trailName: widget.trail.displayName);
    shareGpx(context, ref,
        fileName: gpxFileName(track.name), xml: writeGpx(name: track.name, points: track.points));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trail = widget.trail;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Zum Trailkopf', style: theme.textTheme.titleLarge),
        Text(trail.displayName, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
        const SizedBox(height: 12),
        ..._body(context),
        const SizedBox(height: 16),
        Row(
          children: [
            if (_plan?.route != null) ...[
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('trail-head-gpx'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _exportGpx,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Als GPX'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('trail-head-navigate'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => navigateToTrailHead(context, trail),
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Anfahrt'),
              ),
            ),
          ],
        ),
        if (_plan?.route != null)
          TextButton.icon(
            key: const ValueKey('trail-head-save'),
            onPressed: _saveRide,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Als Fahrt speichern'),
          ),
      ],
    );
  }

  List<Widget> _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (_phase) {
      case _Phase.locating:
        return [_progress('Standort wird ermittelt …')];
      case _Phase.loading:
        return [_progress('Wege und Höhen aus deinen Bereichen werden gelesen …')];
      case _Phase.done:
        break;
    }
    final blocker = _blocker;
    if (blocker != null) return [_notice(context, _blockerText(blocker))];
    final plan = _plan!;
    final route = plan.route;
    if (route == null) return [_notice(context, _outcomeText(plan.outcome))];
    final s = route.summary;
    final palette = AppPalette.of(context);
    return [
      Text(
        key: const ValueKey('trail-head-summary'),
        '${formatMeters(s.lengthM)} · ${s.gainM.round()} hm bergauf · '
        '${s.lossM.round()} hm bergab · etwa ${routeTimeLabel(s.timeS)}',
        style: theme.textTheme.titleMedium?.copyWith(fontFamily: AppFonts.mono),
      ),
      const SizedBox(height: 4),
      Text(_mixLine(s.mix), style: theme.textTheme.bodyMedium),
      if (s.hikingM > 0) ...[
        const SizedBox(height: 8),
        Text(
          'Davon ${formatMeters(s.hikingM)} über Wanderweg, Fußweg oder Stufen — '
          'ob du dort fahren darfst, sagt die App nicht.',
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.warningText),
        ),
      ],
      if (!s.heightsComplete) ...[
        const SizedBox(height: 8),
        Text(
          'Nicht alle Wege haben Höhen — Höhenmeter und Zeit sind eine Untergrenze. '
          'Ein neu gespeicherter Bereich bringt sie mit.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      const SizedBox(height: 12),
      SegmentedButton<RiderProfile>(
        key: const ValueKey('trail-head-profile'),
        segments: [
          for (final p in RiderProfile.values) ButtonSegment(value: p, label: Text(p.label)),
        ],
        selected: {_profile},
        showSelectedIcon: false,
        onSelectionChanged: (sel) {
          _profile = sel.single;
          _replan();
        },
      ),
      const SizedBox(height: 8),
      Text(
        'Ein Vorschlag aus Kartendaten, ohne Abbiegehinweise — fahre nach Sicht.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
    ];
  }

  Widget _progress(String text) => Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      );

  Widget _notice(BuildContext context, String text) => Text(
        key: const ValueKey('trail-head-notice'),
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      );

  String _blockerText(_Blocker b) => switch (b) {
        _Blocker.noPosition => 'Kein Standort — ohne ihn gibt es keinen Startpunkt. Erlaube '
            'TrailBuddy den Standort, oder nimm „Anfahrt": Die Navi-App kennt den Weg auch.',
        _Blocker.noArea => 'Kein gespeicherter Bereich deckt den Weg von deinem Standort zum '
            'Trailkopf. Gerechnet wird nur offline, aus deinen Bereichen — speichere einen '
            'über den Ebenen-Knopf auf der Karte.',
        _Blocker.partialArea => 'Deine Bereiche decken den Weg nur zum Teil '
            '($_tilesFound von $_tilesNeeded Kacheln). Ergänze den Bereich über den '
            'Ebenen-Knopf auf der Karte.',
      };

  String _outcomeText(TrailHeadOutcome o) => switch (o) {
        TrailHeadOutcome.ok => '',
        TrailHeadOutcome.startOffNetwork =>
          'In ${kGraphAttachM.round()} m um deinen Standort liegt kein Weg aus der Karte.',
        TrailHeadOutcome.headOffNetwork =>
          'In ${kGraphAttachM.round()} m um den Trailkopf liegt kein Weg aus der Karte.',
        TrailHeadOutcome.noPath => 'Die Wege in deinen Bereichen verbinden Standort und '
            'Trailkopf nicht — vielleicht fehlt ein Stück Bereich dazwischen.',
      };
}

/// „Forstweg 2,1 km · Nebenstraße 300 m" — die Klassen nach Länge.
String _mixLine(Map<WayClass, double> mix) {
  final entries = mix.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return entries.map((e) => '${e.key.label} ${formatMeters(e.value)}').join(' · ');
}

/// Die Vorschau: je Abschnitt eine Linie in der Fahrt-Farbe, Wanderweg
/// und Co. gestrichelt — dieselbe Sprache wie die Fahrt, kein Tipp-Ziel.
/// Die Verbinder zu Standort und Trailkopf blass und dünn.
List<MapViewPolyline> previewLinesOf(TrailHeadRoute? route) {
  if (route == null) return const [];
  final c = AppColors.mapLines.ride;
  return [
    MapViewPolyline(
      points: route.points,
      color: c.withValues(alpha: 0.35),
      width: 2,
    ),
    for (final s in route.sections)
      MapViewPolyline(
        points: s.points,
        color: c,
        width: 5,
        dash: s.cls.hiking ? const [10, 8] : null,
        borderColor: AppColors.mapLines.halo,
        borderWidth: AppColors.mapLines.haloBorderWidth,
      ),
  ];
}
