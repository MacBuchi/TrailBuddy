// Das Planer-Blatt (#158 Schritt 5, Konzept-Routing 4): Start, Profil,
// drei Regler, Pool mit Pflicht-Haken, Rechnen — und das Ergebnis mit
// Summen, den Trails in Reihenfolge, den ausgelassenen samt Grund, der
// Vorschau auf der Karte, „Als Fahrt speichern" und „Als GPX".
//
// Drei Stufen, eine nach der anderen: Erst die Regler (ohne Standort),
// dann der Pool — der braucht den Start, also den Fix oder den getippten
// Punkt —, dann das Ergebnis. Zurück geht es stufenweise, der Graph bleibt
// stehen, solange der Start derselbe ist. Vier Dinge, die man wissen muss:
// - **Der Fix kommt beim Schritt zum Pool**, nicht beim Öffnen: Wer erst
//   die Regler stellt, soll nicht vorher nach dem Standort gefragt werden.
// - **Gerechnet wird NUR aus den Bereichen** (Konzept-Routing 1): Der
//   Rahmen ist Start plus alle gewählten Trails plus Rand; `partial` heißt
//   kein Plan, und das Blatt nennt den Ebenen-Knopf.
// - **Trails mit warnender Meldung stehen abseits** (Entscheidung 8.8),
//   abgewählt, einzeln hineinholbar. Wartende Trails gar nicht.
// - **Die Regler merkt sich das Gerät** (`Settings.loopPlannerPrefs`) —
//   die nächste Planung beginnt, wo die letzte war.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/errors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../core/gpx_share.dart';
import '../../core/line_geometry.dart';
import '../../core/settings.dart';
import '../../models/trail.dart';
import '../coach/coach.dart';
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
import '../trails/trail_providers.dart';
import 'loop_planner.dart';
import 'loop_planner_providers.dart';
import 'ride_calibrator.dart';
import 'road_graph.dart';
import 'road_graph_loader.dart';
import 'route_profile.dart';
import 'trail_head_route.dart' show kTrailHeadMarginM, routeTimeLabel;

/// Der Anker auf dem Knopf, der vom Formular zum Pool führt — für die
/// Vorführung aus „Entdecken".
const kLoopNextAnchor = 'map.loop.next';

/// Zeigt das Blatt über der Karte; die Vorschau lebt mit dem Blatt und
/// wird HIER geleert, nach dem `await` (wie beim Zerlege-Blatt).
Future<void> showLoopPlannerSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    barrierColor: Colors.black12,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scroll) => _LoopPlannerSheet(scroll: scroll),
    ),
  );
  container.read(loopPreviewProvider.notifier).state = const [];
}

enum _Stage { setup, locating, pool, loading, result }

enum _Blocker { noPosition, noArea, partialArea }

class _LoopPlannerSheet extends ConsumerStatefulWidget {
  const _LoopPlannerSheet({required this.scroll});

  final ScrollController scroll;

  @override
  ConsumerState<_LoopPlannerSheet> createState() => _LoopPlannerSheetState();
}

class _LoopPlannerSheetState extends ConsumerState<_LoopPlannerSheet> {
  _Stage _stage = _Stage.setup;
  late RiderProfile _profile;
  late LoopPrefs _prefs;
  LatLng? _start;
  _Blocker? _blocker;
  int _tilesFound = 0, _tilesNeeded = 0;

  // Der Pool, sobald der Start steht.
  List<Trail> _inReach = const [], _warned = const [];
  int _tooFar = 0;
  final _selected = <String>{};
  final _mandatory = <String>{};

  RoadGraph? _graph;
  LatLng? _graphStart;
  Set<String> _graphTrails = const {};
  LoopPlan? _plan;

  @override
  void initState() {
    super.initState();
    _profile = ref.read(riderProfileProvider);
    _prefs = LoopPrefs.parse(ref.read(settingsProvider).loopPlannerPrefs, _profile);
    final picked = ref.read(loopStartProvider);
    if (picked != null) _start = picked;
  }

  // ── Stufe 1 → 2: Start finden, Pool bauen ──────────────────────────

  Future<void> _toPool() async {
    unawaitedSave();
    var start = _start;
    if (start == null) {
      setState(() => _stage = _Stage.locating);
      final fix = await ref.read(positionFixProvider)();
      if (!mounted) return;
      if (fix == null) {
        setState(() {
          _stage = _Stage.setup;
          _blocker = _Blocker.noPosition;
        });
        return;
      }
      start = LatLng(fix.latitude, fix.longitude);
    }
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final pool = loopPoolOf(trails, start);
    setState(() {
      _start = start;
      _blocker = null;
      _inReach = pool.inReach;
      _warned = pool.warned;
      _tooFar = pool.tooFar;
      // Vorgewählt: alles in Reichweite ohne Warnung; eine frühere Wahl
      // bleibt, wo sie noch gilt.
      final known = {for (final t in [..._inReach, ..._warned]) t.id};
      if (_selected.isEmpty) {
        _selected.addAll(_inReach.map((t) => t.id));
      } else {
        _selected.retainWhere(known.contains);
      }
      _mandatory.retainWhere(known.contains);
      _stage = _Stage.pool;
    });
  }

  void unawaitedSave() {
    ref.read(settingsProvider).setLoopPlannerPrefs(_prefs.encode()).catchError((Object e, StackTrace s) {
      logError('Planer-Regler merken', e, s);
    });
  }

  /// Den Start auf der Karte tippen: Bitte stellen, Blatt zu — die Karte
  /// öffnet es mit dem Punkt wieder.
  void _pickOnMap() {
    ref.read(loopStartPickProvider.notifier).state = true;
    Navigator.of(context).pop();
  }

  // ── Stufe 2 → 3: Graph laden, rechnen ──────────────────────────────

  Future<void> _compute() async {
    final start = _start!;
    final chosen = [
      for (final t in [..._inReach, ..._warned])
        if (_selected.contains(t.id)) t,
    ];
    if (chosen.isEmpty) return;
    final ids = {for (final t in chosen) t.id};
    if (_graph == null || _graphStart != start || !_graphTrails.containsAll(ids)) {
      setState(() => _stage = _Stage.loading);
      final loaded = await _loadGraph(start, chosen);
      if (!mounted) return;
      if (loaded == null) {
        setState(() => _stage = _Stage.pool);
        return;
      }
      _graph = loaded;
      _graphStart = start;
      _graphTrails = ids;
    }
    final pool = [for (final t in chosen) poolTrailOf(t, mandatory: _mandatory.contains(t.id))];
    final plan = planLoop(
      _graph!,
      start: start,
      // Mit den gelernten Werten des Profils (Schritt 6), wo es welche gibt.
      profile: ref.read(calibratedRiderProvider(_profile)),
      budget: _prefs.budget,
      pool: pool,
      returnToStart: _prefs.returnToStart,
    );
    setState(() {
      _plan = plan;
      _stage = _Stage.result;
    });
    ref.read(loopPreviewProvider.notifier).state = loopPreviewLines(plan);
  }

  Future<RoadGraph?> _loadGraph(LatLng start, List<Trail> chosen) async {
    List<StoredArea> areas;
    try {
      areas = await ref.read(storedAreasProvider.future);
    } catch (_) {
      areas = const [];
    }
    if (!mounted) return null;
    HeightReader? heights;
    try {
      heights = await ref.read(areaHeightReaderProvider.future);
    } catch (e, s) {
      logError('Höhen für die Runde öffnen', e, s);
    }
    if (!mounted) return null;
    final store = ref.read(areaStoreProvider);
    final open = ref.read(areaArchiveOpenerProvider);
    final box = LatBox.of([start, for (final t in chosen) ...t.directedPoints]);
    RoadGraphLoadResult roads;
    try {
      roads = await loadRoadGraph(
        areas: areas,
        box: box,
        open: (a) => open(store, a),
        heights: heights,
        marginM: kTrailHeadMarginM,
      );
    } catch (e, s) {
      logError('Wege für die Runde lesen', e, s);
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
    if (!mounted) return null;
    final graph = roads.graph;
    if (graph == null) {
      setState(() {
        _blocker = roads.coverage == RoadCoverage.partial ? _Blocker.partialArea : _Blocker.noArea;
        _tilesFound = roads.tilesFound;
        _tilesNeeded = roads.tilesNeeded;
      });
      return null;
    }
    _blocker = null;
    return graph;
  }

  // ── Ergebnis: speichern, teilen ────────────────────────────────────

  Future<void> _saveRide() async {
    final plan = _plan;
    if (plan == null || plan.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now().toUtc();
    final ride = await ref.read(ridesProvider.notifier).savePlanned(
          name: loopName(plan),
          points: [
            for (final p in plan.points) RidePoint(lat: p.latitude, lng: p.longitude, at: now, accuracyM: 0),
          ],
          duration: Duration(seconds: plan.summary!.timeS.round()),
          profile: _profile.name,
        );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(ride == null
            ? 'Die Runde ließ sich nicht speichern.'
            : 'Als geplante Fahrt gespeichert — im Profil unter „Meine Fahrten".')));
  }

  void _exportGpx() {
    final plan = _plan;
    if (plan == null || plan.isEmpty) return;
    final track = loopToGpx(plan);
    shareGpx(context, ref,
        fileName: gpxFileName(track.name), xml: writeGpx(name: track.name, points: track.points));
  }

  // ── Aufbau ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Runde planen', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        ...switch (_stage) {
          _Stage.setup => _setup(context),
          _Stage.locating => [_progress('Standort wird ermittelt …')],
          _Stage.pool => _pool(context),
          _Stage.loading => [_progress('Wege und Höhen aus deinen Bereichen werden gelesen …')],
          _Stage.result => _result(context),
        },
      ],
    );
  }

  Widget _progress(String text) => Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]);

  Widget _notice(BuildContext context, String text, {Key? key}) =>
      Text(key: key ?? const ValueKey('loop-notice'), text, style: Theme.of(context).textTheme.bodyMedium);

  List<Widget> _setup(BuildContext context) {
    final theme = Theme.of(context);
    final start = _start;
    return [
      Text(
        start == null
            ? 'Start: mein Standort'
            : 'Start: getippter Punkt (${start.latitude.toStringAsFixed(4)}, ${start.longitude.toStringAsFixed(4)})',
        key: const ValueKey('loop-start'),
        style: theme.textTheme.bodyMedium,
      ),
      // Wrap, nicht Row: Auf 360 px ist der Knopf mit Symbol breiter als die
      // Zeile — ein Umbruch ist dort richtig, ein Überlauf nicht.
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(
          key: const ValueKey('loop-pick'),
          onPressed: _pickOnMap,
          icon: const Icon(Icons.touch_app_outlined),
          label: const Text('Auf der Karte tippen'),
        ),
        if (start != null)
          TextButton(
            key: const ValueKey('loop-start-me'),
            onPressed: () {
              ref.read(loopStartProvider.notifier).state = null;
              setState(() => _start = null);
            },
            child: const Text('Mein Standort'),
          ),
      ]),
      const SizedBox(height: 8),
      SegmentedButton<RiderProfile>(
        key: const ValueKey('loop-profile'),
        segments: [for (final p in RiderProfile.values) ButtonSegment(value: p, label: Text(p.label))],
        selected: {_profile},
        showSelectedIcon: false,
        onSelectionChanged: (sel) {
          final next = sel.single;
          setState(() {
            // Steht das Höhenbudget auf der Vorgabe des alten Profils,
            // folgt es dem neuen — wer es selbst gestellt hat, behält es.
            if (_prefs.climbM == _profile.budgetClimbM) {
              _prefs = _prefs.copyWith(climbM: next.budgetClimbM);
            }
            _profile = next;
          });
        },
      ),
      const SizedBox(height: 12),
      _slider(
        key: const ValueKey('loop-time'),
        label: 'Höchstens ${_hoursLabel(_prefs.hours)}',
        value: _prefs.hours,
        min: LoopPrefs.minHours,
        max: LoopPrefs.maxHours,
        step: LoopPrefs.hoursStep,
        onChanged: (v) => setState(() => _prefs = _prefs.copyWith(hours: v)),
      ),
      _slider(
        key: const ValueKey('loop-climb'),
        label: 'Höchstens ${_prefs.climbM.round()} hm bergauf',
        value: _prefs.climbM,
        min: LoopPrefs.minClimb,
        max: LoopPrefs.maxClimb,
        step: LoopPrefs.climbStep,
        onChanged: (v) => setState(() => _prefs = _prefs.copyWith(climbM: v)),
      ),
      _slider(
        key: const ValueKey('loop-hiking'),
        label: _prefs.hikingKm == 0
            ? 'Kein Wanderweg'
            : 'Höchstens ${formatMeters(_prefs.hikingKm * 1000)} Wanderweg',
        value: _prefs.hikingKm,
        min: LoopPrefs.minHikingKm,
        max: LoopPrefs.maxHikingKm,
        step: LoopPrefs.hikingStep,
        onChanged: (v) => setState(() => _prefs = _prefs.copyWith(hikingKm: v)),
      ),
      SwitchListTile(
        key: const ValueKey('loop-return'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Start ist auch Ziel'),
        subtitle: Text(_prefs.returnToStart ? 'Eine Runde' : 'Die Runde endet am letzten Trail'),
        value: _prefs.returnToStart,
        onChanged: (v) => setState(() => _prefs = _prefs.copyWith(returnToStart: v)),
      ),
      if (_blocker != null) ...[
        const SizedBox(height: 8),
        _notice(context, _blockerText(_blocker!)),
      ],
      const SizedBox(height: 12),
      CoachAnchor(
        id: kLoopNextAnchor,
        child: FilledButton.icon(
          key: const ValueKey('loop-next'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _toPool,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Weiter: Trails wählen'),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Die Runde nimmt möglichst viele deiner Trails bergab mit und verbindet '
        'sie über die Wege deiner gespeicherten Bereiche — offline, nach deinem Profil.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
    ];
  }

  Widget _slider({
    required Key key,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: AppFonts.mono)),
        Slider(
          key: key,
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          onChanged: onChanged,
        ),
      ]);

  List<Widget> _pool(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final chosen = _selected.length;
    return [
      Text('Start: ${_startLabel()}', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 8),
      Text('Trails in Reichweite (${_inReach.length})', style: theme.textTheme.titleMedium),
      if (_inReach.isEmpty)
        _notice(context, _warned.isEmpty
            ? 'In ${(kLoopReachM / 1000).round()} km um den Start liegt kein Trail.'
            : 'In ${(kLoopReachM / 1000).round()} km um den Start liegen nur gemeldete Trails.'),
      for (final t in _inReach) _poolRow(t),
      if (_warned.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Gemeldet (${_warned.length})', style: theme.textTheme.titleMedium),
        Text(
          'Gesperrt, zerstört oder verändert — nicht vorgewählt, einzeln dazunehmbar.',
          style: theme.textTheme.bodySmall?.copyWith(color: palette.warningText),
        ),
        for (final t in _warned) _poolRow(t),
      ],
      if (_tooFar > 0) ...[
        const SizedBox(height: 4),
        Text(
          '$_tooFar ${_tooFar == 1 ? 'Trail liegt' : 'Trails liegen'} weiter als '
          '${(kLoopReachM / 1000).round()} km vom Start und ${_tooFar == 1 ? 'kommt' : 'kommen'} nicht in Frage.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      if (_blocker != null) ...[
        const SizedBox(height: 8),
        _notice(context, _blockerText(_blocker!)),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('loop-compute'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: chosen == 0 ? null : _compute,
        icon: const Icon(Icons.alt_route),
        label: Text(chosen == 0 ? 'Runde rechnen' : 'Runde rechnen ($chosen)'),
      ),
      TextButton(
        key: const ValueKey('loop-back'),
        onPressed: () => setState(() => _stage = _Stage.setup),
        child: const Text('Zurück zu den Reglern'),
      ),
    ];
  }

  Widget _poolRow(Trail t) {
    final on = _selected.contains(t.id);
    final must = _mandatory.contains(t.id);
    final parts = [
      formatMeters(t.lengthM),
      if (t.grade != null) 'S${t.grade}',
      if (t.rating != null) '${t.rating} ${t.rating == 1 ? 'Stern' : 'Sterne'}',
    ];
    return CheckboxListTile(
      key: ValueKey('loop-trail-${t.id}'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: on,
      onChanged: (v) => setState(() {
        if (v == true) {
          _selected.add(t.id);
        } else {
          _selected.remove(t.id);
          _mandatory.remove(t.id);
        }
      }),
      title: Text(t.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(parts.join(' · ')),
      secondary: IconButton(
        key: ValueKey('loop-must-${t.id}'),
        tooltip: must ? 'Muss dabei sein — abwählen' : 'Muss dabei sein',
        icon: Icon(must ? Icons.star : Icons.star_border),
        onPressed: () => setState(() {
          if (must) {
            _mandatory.remove(t.id);
          } else {
            _mandatory.add(t.id);
            _selected.add(t.id);
          }
        }),
      ),
    );
  }

  List<Widget> _result(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final plan = _plan!;
    final back = TextButton(
      key: const ValueKey('loop-adjust'),
      onPressed: () {
        ref.read(loopPreviewProvider.notifier).state = const [];
        setState(() => _stage = _Stage.pool);
      },
      child: const Text('Anpassen'),
    );
    if (plan.outcome != LoopOutcome.ok) {
      return [
        _notice(context, _outcomeText(plan.outcome)),
        if (plan.excluded.isNotEmpty) ...[const SizedBox(height: 8), ..._excludedRows(context, plan)],
        const SizedBox(height: 8),
        back,
      ];
    }
    final s = plan.summary!;
    final byId = {for (final t in [..._inReach, ..._warned]) t.id: t};
    return [
      Text(
        key: const ValueKey('loop-summary'),
        '${formatMeters(s.lengthM)} · ${s.gainM.round()} hm bergauf · '
        '${formatMeters(s.trailM)} Trail · etwa ${routeTimeLabel(s.timeS)}',
        style: theme.textTheme.titleMedium?.copyWith(fontFamily: AppFonts.mono),
      ),
      const SizedBox(height: 4),
      Text(
        '${s.trailLossM.round()} hm bergab auf Trails · ${s.wastedLossM.round()} hm verschenkt'
        '${s.mix.isEmpty ? '' : ' · ${_mixLine(s.mix)}'}',
        style: theme.textTheme.bodyMedium,
      ),
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
      Text('In dieser Reihenfolge', style: theme.textTheme.titleMedium),
      for (var i = 0; i < plan.stops.length; i++)
        ListTile(
          key: ValueKey('loop-stop-$i'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
          title: Text(plan.stops[i].trail.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            formatMeters(plan.stops[i].trail.lengthM),
            if (byId[plan.stops[i].trail.id]?.grade case final g?) 'S$g',
            if (plan.stops[i].secondPass) 'noch einmal',
          ].join(' · ')),
        ),
      if (plan.excluded.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Nicht hineingepasst', style: theme.textTheme.titleMedium),
        ..._excludedRows(context, plan),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('loop-save'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _saveRide,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Als Fahrt speichern'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('loop-gpx'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _exportGpx,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Als GPX'),
          ),
        ),
      ]),
      back,
      Text(
        'Ein Vorschlag aus Kartendaten, ohne Abbiegehinweise — fahre nach Sicht.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
    ];
  }

  List<Widget> _excludedRows(BuildContext context, LoopPlan plan) {
    final theme = Theme.of(context);
    final byId = {for (final t in [..._inReach, ..._warned]) t.id: t};
    return [
      for (final e in plan.excluded.entries)
        Text(
          key: ValueKey('loop-excluded-${e.key}'),
          '${byId[e.key]?.displayName ?? e.key} — ${_exclusionText(e.value)}',
          style: theme.textTheme.bodySmall,
        ),
    ];
  }

  String _startLabel() {
    final s = _start;
    if (s == null) return 'mein Standort';
    return ref.read(loopStartProvider) == null
        ? 'mein Standort'
        : 'getippter Punkt (${s.latitude.toStringAsFixed(4)}, ${s.longitude.toStringAsFixed(4)})';
  }

  String _blockerText(_Blocker b) => switch (b) {
        _Blocker.noPosition => 'Kein Standort — ohne ihn gibt es keinen Startpunkt. Erlaube '
            'TrailBuddy den Standort, oder tippe den Start auf der Karte.',
        _Blocker.noArea => 'Kein gespeicherter Bereich deckt die Runde. Gerechnet wird nur offline, '
            'aus deinen Bereichen — speichere einen über den Ebenen-Knopf auf der Karte.',
        _Blocker.partialArea => 'Deine Bereiche decken die Runde nur zum Teil '
            '($_tilesFound von $_tilesNeeded Kacheln). Ergänze den Bereich über den '
            'Ebenen-Knopf auf der Karte, oder wähle weniger Trails.',
      };

  String _outcomeText(LoopOutcome o) => switch (o) {
        LoopOutcome.ok => '',
        LoopOutcome.startOffNetwork =>
          'In ${kGraphAttachM.round()} m um den Start liegt kein Weg aus der Karte.',
        LoopOutcome.empty => 'Kein gewählter Trail passt in die Runde — die Gründe stehen je Trail. '
            'Mehr Zeit oder Höhenmeter, oder ein anderer Start.',
      };

  String _exclusionText(LoopExclusion e) => switch (e) {
        LoopExclusion.tooFar => 'zu weit vom Start',
        LoopExclusion.offNetwork => 'Anfang oder Ende liegt an keinem Weg der Karte',
        LoopExclusion.unreachable => 'von den Wegen deiner Bereiche aus nicht erreichbar',
        LoopExclusion.budget => 'passt nicht ins Budget',
      };
}

String _hoursLabel(double h) {
  final whole = h.floor();
  final half = h - whole >= 0.5;
  return half ? '$whole h 30 min' : '$whole h';
}

/// „Forstweg 2,1 km · Nebenstraße 300 m" — die Klassen nach Länge.
String _mixLine(Map<WayClass, double> mix) {
  final entries = mix.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return entries.map((e) => '${e.key.label} ${formatMeters(e.value)}').join(' · ');
}

/// Die Vorschau: die ganze Linie blass, Verbindungen in der Fahrt-Farbe
/// (Wanderweg gestrichelt), die Trails als breiter Saum darunter — die
/// Trail-Linien selbst behalten ihre Farbe, der Saum sagt „dabei".
List<MapViewPolyline> loopPreviewLines(LoopPlan plan) {
  if (plan.outcome != LoopOutcome.ok) return const [];
  final c = AppColors.mapLines.ride;
  return [
    MapViewPolyline(points: plan.points, color: c.withValues(alpha: 0.35), width: 2),
    for (final s in plan.sections)
      if (s.isTrail)
        MapViewPolyline(points: s.points, color: c.withValues(alpha: 0.45), width: 9)
      else
        MapViewPolyline(
          points: s.points,
          color: c,
          width: 5,
          dash: s.cls!.hiking ? const [10, 8] : null,
          borderColor: AppColors.mapLines.halo,
          borderWidth: AppColors.mapLines.haloBorderWidth,
        ),
  ];
}
