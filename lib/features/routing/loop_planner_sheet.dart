// Das Planer-Blatt (#158 Schritt 5, Konzept-Routing 4): Start, Profil,
// drei Regler, Pool mit Pflicht-Haken, Rechnen — und das Ergebnis mit
// Summen, den Trails in Reihenfolge, den ausgelassenen samt Grund, der
// Vorschau auf der Karte, „Als Fahrt speichern" und „Als GPX".
//
// Drei Stufen, eine nach der anderen: Erst die Regler (ohne Standort),
// dann der Pool — der braucht den Start, also den Fix oder den getippten
// Punkt —, dann das Ergebnis. Zurück geht es stufenweise, der Graph bleibt
// stehen, solange der Start derselbe ist. Sechs Dinge, die man wissen muss:
// - **Das Blatt ist kein Modal** (seit 0.74.0, `map_panel.dart`): Die Karte
//   bleibt bedienbar, Runterziehen verkleinert nur, geschlossen wird über
//   X oder Zurück. Beim Ergebnis klappt es ein, und die Karte passt die
//   Runde in die Fläche darüber ein — vorher lag sie unter dem Blatt.
// - **Im Pool wählt ein Tipp auf einen Trail der Karte ihn an oder ab**
//   (#178, `loopMapPickProvider`); die gewählten leuchten.
// - **Der Fix kommt beim Schritt zum Pool**, nicht beim Öffnen: Wer erst
//   die Regler stellt, soll nicht vorher nach dem Standort gefragt werden.
// - **Gerechnet wird NUR aus den Bereichen** (Konzept-Routing 1): Der
//   Rahmen ist Start plus alle gewählten Trails plus Rand; `partial` heißt
//   kein Plan, und das Blatt nennt den Ebenen-Knopf.
// - **Trails mit warnender Meldung stehen abseits** (Entscheidung 8.8),
//   abgewählt, einzeln hineinholbar. Wartende Trails gar nicht.
// - **Die Regler merkt sich das Gerät** (`Settings.loopPlannerPrefs`) —
//   die nächste Planung beginnt, wo die letzte war.
import 'dart:async';

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
import '../profile/profile_providers.dart';
import '../rides/ride_providers.dart';
import '../rides/ride_track.dart';
import '../trails/gpx_writer.dart';
import '../trails/trail_providers.dart';
import 'loop_planner.dart';
import 'loop_planner_providers.dart';
import 'map_panel.dart';
import 'planning_graph.dart';
import 'ride_calibrator.dart';
import 'road_graph.dart';
import 'route_profile.dart';
import 'trail_head_route.dart' show routeTimeLabel;

/// Der Anker auf dem Knopf, der vom Formular zum Pool führt — für die
/// Vorführung aus „Entdecken".
const kLoopNextAnchor = 'map.loop.next';

/// Zeigt das Blatt am Scaffold der Karte; die Vorschau lebt mit dem Blatt
/// und wird HIER geleert, nach dem `await` (wie beim Zerlege-Blatt).
Future<void> showLoopPlannerSheet(ScaffoldState scaffold) async {
  final container = ProviderScope.containerOf(scaffold.context, listen: false);
  await showMapPanel(
    scaffold,
    initialSize: 0.6,
    builder: (context, scroll, panel) => _LoopPlannerSheet(scroll: scroll, panel: panel),
  );
  container.read(loopPreviewProvider.notifier).state = const [];
  container.read(loopMapPickProvider.notifier).state = null;
}

enum _Stage { setup, locating, pool, loading, computing, result }

enum _Blocker { noPosition, noArea, failed }

class _LoopPlannerSheet extends ConsumerStatefulWidget {
  const _LoopPlannerSheet({required this.scroll, required this.panel});

  final ScrollController scroll;
  final MapPanelController panel;

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
  bool _partial = false;

  // Der Pool, sobald der Start steht.
  List<Trail> _inReach = const [], _warned = const [], _connectors = const [];
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
      _connectors = pool.connectors;
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
    _offerMapPick();
    // Start und Pool zeigen, über dem Blatt: Die Karte ist die zweite
    // Liste, auf der man wählt (#178). Erst auf halbe Höhe — ganz
    // aufgezogen bliebe für die Karte ein Streifen.
    await widget.panel.resizeTo(kMapPanelPool);
    if (!mounted) return;
    ref.read(mapFitRequestProvider.notifier).state = [
      start,
      for (final t in [..._inReach, ..._warned]) ...t.points,
    ];
  }

  // ── Pool auf der Karte (#178) ──────────────────────────────────────

  void _offerMapPick() {
    ref.read(loopMapPickProvider.notifier).state = LoopMapPick(
      selectable: {for (final t in [..._inReach, ..._warned]) t.id},
      toggle: (id) {
        if (!mounted || _stage != _Stage.pool) return;
        setState(() => _selected.contains(id) ? _deselect(id) : _selected.add(id));
        _showSelection();
      },
    );
    _showSelection();
  }

  void _deselect(String id) {
    _selected.remove(id);
    _mandatory.remove(id);
  }

  /// Die gewählten Trails leuchten auf der Karte, solange der Pool offen ist.
  void _showSelection() {
    final c = AppColors.brand;
    ref.read(loopPreviewProvider.notifier).state = [
      for (final t in [..._inReach, ..._warned])
        if (_selected.contains(t.id))
          MapViewPolyline(
            points: t.directedPoints,
            color: c.withValues(alpha: _mandatory.contains(t.id) ? 0.75 : 0.5),
            width: kLoopPickWidth,
          ),
    ];
  }

  void _leavePool() {
    ref.read(loopMapPickProvider.notifier).state = null;
    ref.read(loopPreviewProvider.notifier).state = const [];
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
    widget.panel.close();
  }

  // ── Stufe 2 → 3: Graph laden, rechnen ──────────────────────────────

  /// Rechnen. Jeder Ausgang ist sichtbar (Feldbericht 0.73.0: „teils hat
  /// es nicht funktioniert ohne sichtbaren Grund"): kein Bereich ⇒ Satz
  /// OBEN im Blatt; ein Fehler beim Lesen oder Rechnen ⇒ Satz und
  /// Fehlerbericht; nie ein Kreisel, der stehen bleibt.
  Future<void> _compute() async {
    final start = _start!;
    final chosen = [
      for (final t in [..._inReach, ..._warned])
        if (_selected.contains(t.id)) t,
    ];
    if (chosen.isEmpty) return;
    _leavePool();
    final ids = {for (final t in chosen) t.id};
    try {
      if (_graph == null || _graphStart != start || !_graphTrails.containsAll(ids)) {
        setState(() => _stage = _Stage.loading);
        // Der Rahmen trägt auch die Uphill-Trails und Verbinder in
        // Reichweite — sie sind der Weg bergauf (#185).
        final box = LatBox.of([
          start,
          for (final t in chosen) ...t.directedPoints,
          for (final t in _connectors) ...t.points,
        ]);
        final loaded = await ref.read(planningGraphLoaderProvider)(box);
        if (!mounted) return;
        if (loaded.graph == null) {
          setState(() {
            _blocker = _Blocker.noArea;
            _stage = _Stage.pool;
          });
          _offerMapPick();
          return;
        }
        _graph = loaded.graph;
        _partial = loaded.partial;
        _tilesFound = loaded.tilesFound;
        _tilesNeeded = loaded.tilesNeeded;
        _graphStart = start;
        _graphTrails = ids;
      }
      setState(() => _stage = _Stage.computing);
      // Ein Bild für den Kreisel, bevor die Rechnung den Takt belegt.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
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
        _blocker = null;
        _stage = _Stage.result;
      });
      if (plan.outcome != LoopOutcome.ok) return;
      // Erst einklappen, dann zeigen und einpassen — sonst läge die Runde
      // unter dem Blatt.
      await widget.panel.resizeTo(kMapPanelResult);
      if (!mounted) return;
      ref.read(loopPreviewProvider.notifier).state = loopPreviewLines(plan);
      ref.read(mapFitRequestProvider.notifier).state = plan.points;
    } catch (e, s) {
      logError('Runde planen', e, s);
      if (!mounted) return;
      setState(() {
        _blocker = _Blocker.failed;
        _stage = _Stage.pool;
      });
      _offerMapPick();
    }
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
    final blocker = _blocker;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 24),
      children: [
        MapPanelHeader(
          title: 'Runde planen',
          subtitle: _stage == _Stage.result && _plan?.summary != null ? _shortSummary(_plan!.summary!) : null,
          closeKey: const ValueKey('loop-close'),
          onClose: widget.panel.close,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Was die Planung aufhält, steht OBEN — nicht unter einer
              // langen Liste, wo es niemand sieht.
              if (blocker != null && _stage != _Stage.setup) ...[
                _blockerCard(context, blocker),
                const SizedBox(height: 12),
              ],
              ...switch (_stage) {
                _Stage.setup => _setup(context),
                _Stage.locating => [_progress('Standort wird ermittelt …')],
                _Stage.pool => _pool(context),
                _Stage.loading => [_progress('Wege und Höhen aus deinen Bereichen werden gelesen …')],
                _Stage.computing => [_progress('Die Runde wird gerechnet …')],
                _Stage.result => _result(context),
              },
            ],
          ),
        ),
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

  Widget _blockerCard(BuildContext context, _Blocker b) {
    final palette = AppPalette.of(context);
    return Card(
      key: const ValueKey('loop-blocker'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: palette.warningText),
          const SizedBox(width: 10),
          Expanded(child: _notice(context, _blockerText(b))),
        ]),
      ),
    );
  }

  String _shortSummary(LoopSummary s) =>
      '${formatMeters(s.lengthM)} · ${s.gainM.round()} hm · etwa ${routeTimeLabel(s.timeS)}';

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
        _blockerCard(context, _blocker!),
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
      const SizedBox(height: 4),
      Text(
        'Tippe Trails auf der Karte an, um sie dazu- oder herauszunehmen.',
        key: const ValueKey('loop-map-pick-hint'),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
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
      if (_connectors.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('loop-connectors'),
          'Bergauf nutzt die Runde ${_connectors.length == 1 ? 'den Uphill-Trail oder Verbinder' : 'die Uphill-Trails und Verbinder'} '
          '${_connectors.map((t) => t.displayName).join(', ')} — gern auch mehrmals.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
      if (_tooFar > 0) ...[
        const SizedBox(height: 4),
        Text(
          '$_tooFar ${_tooFar == 1 ? 'Trail liegt' : 'Trails liegen'} weiter als '
          '${(kLoopReachM / 1000).round()} km vom Start und ${_tooFar == 1 ? 'kommt' : 'kommen'} nicht in Frage.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
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
        onPressed: () {
          _leavePool();
          setState(() {
            _blocker = null;
            _stage = _Stage.setup;
          });
        },
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
      onChanged: (v) {
        setState(() => v == true ? _selected.add(t.id) : _deselect(t.id));
        _showSelection();
      },
      title: Text(t.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(parts.join(' · ')),
      secondary: IconButton(
        key: ValueKey('loop-must-${t.id}'),
        tooltip: must ? 'Muss dabei sein — abwählen' : 'Muss dabei sein',
        icon: Icon(must ? Icons.star : Icons.star_border),
        onPressed: () {
          setState(() {
            if (must) {
              _mandatory.remove(t.id);
            } else {
              _mandatory.add(t.id);
              _selected.add(t.id);
            }
          });
          _showSelection();
        },
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
        _offerMapPick();
        unawaited(widget.panel.resizeTo(0.6));
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
      // Die Knöpfe gleich unter den Summen: Eingeklappt (kMapPanelResult)
      // sind sie zu sehen, die Runde darüber.
      const SizedBox(height: 8),
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
      if (s.trailUpM > 0) ...[
        const SizedBox(height: 4),
        Text(
          key: const ValueKey('loop-trail-up'),
          'Bergauf ${formatMeters(s.trailUpM)} über ${s.trailUpNames.join(', ')}',
          style: theme.textTheme.bodyMedium,
        ),
      ],
      if (s.hikingM > 0) ...[
        const SizedBox(height: 8),
        Text(
          'Davon ${formatMeters(s.hikingM)} über Wanderweg, Fußweg oder Stufen — '
          'ob du dort fahren darfst, sagt die App nicht.',
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.warningText),
        ),
      ],
      if (_partial) ...[
        const SizedBox(height: 8),
        Text(
          key: const ValueKey('loop-partial'),
          'Gerechnet über $_tilesFound von $_tilesNeeded Kacheln um die Runde — nur dort kennt die App '
          'die Wege. Ein Weg außerhalb deiner Bereiche kann kürzer sein.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
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
        _Blocker.failed => 'Die Runde ließ sich nicht rechnen — ein Fehler, der gemeldet ist. '
            'Versuch es mit weniger Trails noch einmal.',
      };

  String _outcomeText(LoopOutcome o) => switch (o) {
        LoopOutcome.ok => '',
        LoopOutcome.startOffNetwork =>
          'In ${kGraphAttachM.round()} m um den Start liegt kein Weg aus der Karte.',
        LoopOutcome.endOffNetwork =>
          'In ${kGraphAttachM.round()} m um das Ziel liegt kein Weg aus der Karte.',
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

/// Breite der leuchtenden Auswahl im Pool (#178) — breiter als eine
/// Verbindung, schmaler als der Saum eines Trails in der Runde.
const kLoopPickWidth = 8.0;

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
          dash: s.hiking ? const [10, 8] : null,
          borderColor: AppColors.mapLines.halo,
          borderWidth: AppColors.mapLines.haloBorderWidth,
        ),
  ];
}
