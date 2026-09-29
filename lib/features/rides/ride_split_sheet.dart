// Das Zerlege-Blatt (#29, Konzept 5.1): die Fahrt auf der Karte,
// zerlegt in bekannte Trails (vorangehakt, „wieder gefahren"),
// Kandidaten für neue Trails (Griffe, Name, S-Grad — oder verwerfen)
// und den Rest, der nicht angeboten wird. Ein Blatt für alle drei
// Wege: nach der Aufzeichnung, aus „Meine Fahrten", aus dem GPX-Import
// für Fahrten (Konzept 5.2, „geht durch dasselbe Blatt wie 5.1").
//
// Die Karte zeichnet dabei mit: Das Blatt legt seine Abschnitte in
// [rideSplitPreviewProvider], der Karten-Screen malt sie über die Fahrt
// — Griffe verschieben, und die Linie folgt. Gerechnet wird in
// `ride_split.dart`, hier steht nur, was der Nutzer sieht und wählt.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../models/trail.dart';
import '../map/map_view/map_view.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../trails/gpx.dart';
import '../trails/singletrail_scale.dart';
import '../trails/trail_geometry.dart';
import '../trails/trail_providers.dart';
import '../trails/trail_sheet.dart' show formatLength;
import 'ride_split.dart';
import 'ride_track.dart';
import 'road_index.dart';

/// Was zerlegt werden soll: die Spur, ihre Quelle, die Streuung je Punkt
/// (nur bei eigenen Aufzeichnungen).
class SplitRequest {
  const SplitRequest({
    required this.track,
    required this.source,
    this.accuracyM,
    this.rideId,
  });

  /// Aus einer eigenen Fahrt. Die GPS-Höhe geht als Höhe hinein — für die
  /// Gefälle-Suche taugt sie, ausgeliefert wird sie NICHT (#28: „file
  /// elevations stay the source until measured"); [stripElevation] gilt.
  factory SplitRequest.fromRide(Ride ride) => SplitRequest(
        track: GpxTrack(
          name: 'Fahrt',
          points: [
            for (final p in ride.points) TrackPoint(p.lat, p.lng, ele: p.altM, time: p.at),
          ],
        ),
        source: RecordingSource.app,
        accuracyM: [for (final p in ride.points) p.accuracyM],
        rideId: ride.id,
      );

  /// Aus einer GPX-Datei, die eine Fahrt ist (Konzept 5.2).
  factory SplitRequest.fromGpx(GpxTrack track) =>
      SplitRequest(track: track, source: sourceOf(track.points));

  final GpxTrack track;
  final RecordingSource source;
  final List<double?>? accuracyM;
  final String? rideId;

  /// Höhen aus dem GPS werden nicht beigesteuert, Höhen aus der Datei schon.
  bool get stripElevation => source == RecordingSource.app;
}

/// Wunsch aus einer Liste an die Karte: diese Fahrt zerlegen. Die Karte
/// passt sie ein, öffnet das Blatt und setzt den Wunsch zurück.
final mapSplitRequestProvider = StateProvider<SplitRequest?>((ref) => null);

/// Was die Karte während des Blatts über die Fahrt zeichnet.
final rideSplitPreviewProvider = StateProvider<List<MapViewPolyline>>((ref) => const []);

/// Zeigt das Blatt; `true` heißt „Fahrt verwerfen" (nur nach einer
/// Aufzeichnung angeboten, [offerDiscard]).
Future<bool> showRideSplitSheet(
  BuildContext context,
  SplitRequest request, {
  bool offerDiscard = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final discard = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Die Karte soll sichtbar bleiben: Sie zeigt, was die Griffe tun.
    barrierColor: Colors.black12,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) =>
          _RideSplitSheet(request: request, offerDiscard: offerDiscard, scroll: scroll),
    ),
  );
  // Die Vorschau gehört dem Blatt; ohne Blatt keine Vorschau. Hier und
  // nicht im `dispose` des Blatts: Dort ist `ref` schon tot, und ein
  // nachgereichter Frame träfe im Test einen abgebauten Container.
  container.read(rideSplitPreviewProvider.notifier).state = const [];
  return discard ?? false;
}

class _RideSplitSheet extends ConsumerStatefulWidget {
  const _RideSplitSheet({required this.request, required this.offerDiscard, required this.scroll});

  final SplitRequest request;
  final bool offerDiscard;
  final ScrollController scroll;

  @override
  ConsumerState<_RideSplitSheet> createState() => _RideSplitSheetState();
}

/// Ein Kandidat, wie er im Blatt steht: mit den Griffen, dem Namen, dem
/// Grad — und ob er noch dabei ist.
class _CandidateDraft {
  _CandidateDraft(this.section, String name)
      : start = section.start,
        end = section.end,
        nameField = TextEditingController(text: name);

  final CandidateSection section;
  int start;
  int end;
  final TextEditingController nameField;
  int? grade;
  bool selected = true;
  bool discarded = false;
}

class _RideSplitSheetState extends ConsumerState<_RideSplitSheet> {
  static final _date = DateFormat('d. MMMM', 'de');

  RideSplit? _split;
  bool _loading = true;
  final _knownSelected = <int>{};
  final _drafts = <_CandidateDraft>[];
  bool _busy = false;
  int _done = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_compute());
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.nameField.dispose();
    }
    super.dispose();
  }

  Future<void> _compute() async {
    final points = widget.request.track.points;
    final latLng = [for (final p in points) LatLng(p.lat, p.lon)];
    final projection = FlatProjection.around(latLng);
    List<Trail> trails;
    try {
      trails = await ref.read(trailsProvider.future);
    } catch (_) {
      trails = const [];
    }
    List<StoredArea> areas;
    try {
      areas = await ref.read(storedAreasProvider.future);
    } catch (_) {
      areas = const [];
    }
    if (!mounted) return;
    final store = ref.read(areaStoreProvider);
    final open = ref.read(areaArchiveOpenerProvider);
    RoadLoadResult roads;
    try {
      roads = await loadRoads(
        areas: areas,
        box: LatBox.of(latLng),
        open: (a) => open(store, a),
        projection: projection,
      );
    } catch (e, s) {
      logError('Wege für das Zerlege-Blatt lesen', e, s);
      roads = (index: null, coverage: RoadCoverage.none, tilesNeeded: 0, tilesFound: 0);
    }
    if (!mounted) return;
    final split = splitRide(
      points: points,
      accuracyM: widget.request.accuracyM,
      trails: trails,
      roads: roads,
    );
    setState(() {
      _split = split;
      _loading = false;
      _knownSelected.addAll([for (var i = 0; i < split.known.length; i++) i]);
      final date = _date.format((points.first.time ?? DateTime.now()).toLocal());
      for (var i = 0; i < split.candidates.length; i++) {
        _drafts.add(_CandidateDraft(
            split.candidates[i], split.candidates.length == 1 ? 'Trail vom $date' : 'Trail ${i + 1} vom $date'));
      }
    });
    _pushPreview();
  }

  List<LatLng> _latLng(int start, int end) => [
        for (final p in _split!.points.sublist(start, end + 1)) LatLng(p.lat, p.lon),
      ];

  double _lengthOf(int start, int end) => trackLengthM(_split!.points.sublist(start, end + 1));

  double? _lossOf(int start, int end) {
    final a = _split!.points[start].ele, b = _split!.points[end].ele;
    return a == null || b == null ? null : a - b;
  }

  /// Die Karte zeichnet: die ganze Fahrt blass, darüber die bekannten
  /// Stücke grün und die Kandidaten in ihrer Farbe — gewählt kräftig,
  /// abgewählt gestrichelt, verworfen gar nicht.
  void _pushPreview() {
    final split = _split;
    if (split == null) return;
    final lines = <MapViewPolyline>[
      MapViewPolyline(
        points: [for (final p in thinnedTrack(split.points)) LatLng(p.lat, p.lon)],
        color: AppColors.mapLines.ride.withValues(alpha: 0.45),
        width: 4,
        borderColor: AppColors.mapLines.halo,
        borderWidth: AppColors.mapLines.haloBorderWidth,
      ),
      for (var i = 0; i < split.known.length; i++)
        MapViewPolyline(
          points: _latLng(split.known[i].start, split.known[i].end),
          color: AppColors.mapLines.mine.withValues(alpha: _knownSelected.contains(i) ? 1 : 0.5),
          width: 6,
          borderColor: AppColors.mapLines.halo,
          borderWidth: AppColors.mapLines.haloBorderWidth,
          dash: _knownSelected.contains(i) ? null : const [10, 8],
        ),
      for (final d in _drafts)
        if (!d.discarded)
          MapViewPolyline(
            points: _latLng(d.start, d.end),
            color: AppColors.mapLines.candidate.withValues(alpha: d.selected ? 1 : 0.5),
            width: 6,
            borderColor: AppColors.mapLines.halo,
            borderWidth: AppColors.mapLines.haloBorderWidth,
            dash: d.selected ? null : const [10, 8],
          ),
    ];
    ref.read(rideSplitPreviewProvider.notifier).state = lines;
  }

  int get _selectedCount =>
      _knownSelected.length + _drafts.where((d) => d.selected && !d.discarded && _longEnough(d)).length;

  bool _longEnough(_CandidateDraft d) => _lengthOf(d.start, d.end) >= kTrailMinLengthM;

  GpxTrack _trackOf(int start, int end, String name) => GpxTrack(
        name: name,
        points: [
          for (final p in _split!.points.sublist(start, end + 1))
            widget.request.stripElevation ? TrackPoint(p.lat, p.lon, time: p.time) : p,
        ],
      );

  Future<void> _contribute() async {
    final split = _split;
    if (split == null || _selectedCount == 0) return;
    setState(() {
      _busy = true;
      _done = 0;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(trailsProvider.notifier);
    var ok = 0, queued = 0, failed = 0;
    var limitHit = false;
    final jobs = <({GpxTrack track, int? grade})>[
      // Ohne Namen: Der Trail hat schon einen, und der eigene Beitrag
      // bleibt, wie er ist — „wieder gefahren" ist ein Beleg, kein Name.
      for (var i = 0; i < split.known.length; i++)
        if (_knownSelected.contains(i))
          (track: _trackOf(split.known[i].start, split.known[i].end, ''), grade: null),
      for (final d in _drafts)
        if (d.selected && !d.discarded && _longEnough(d))
          (track: _trackOf(d.start, d.end, d.nameField.text), grade: d.grade),
    ];
    for (final job in jobs) {
      try {
        final r = await notifier.contribute(job.track, source: widget.request.source, grade: job.grade);
        if (r.queued) {
          queued++;
        } else {
          ok++;
        }
      } on DailyLimitException {
        limitHit = true;
        break;
      } catch (e, s) {
        logError('Fahrt-Abschnitt beisteuern', e, s);
        failed++;
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    final fresh = ok == 0 || await notifier.reloadAfterWrite('Trails nach dem Zerlegen laden');
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(
        '$ok ${ok == 1 ? 'Abschnitt' : 'Abschnitte'} beigesteuert'
        '${queued > 0 ? ', $queued ${queued == 1 ? 'wartet' : 'warten'} im Ausgangskorb auf Netz' : ''}'
        '${failed > 0 ? ', $failed fehlgeschlagen' : ''}'
        '${limitHit ? ' — für heute ist das Limit erreicht' : ''}'
        '${fresh ? '' : ' — sichtbar, sobald die Liste wieder lädt.'}',
      ),
    ));
    if (failed == 0 && !limitHit) navigator.pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = _split;
    final track = widget.request.track;
    final totalM = split?.totalM ?? trackLengthM(track.points);
    // Die Knöpfe stehen FEST unter der Liste: Auf einem halb geöffneten
    // Blatt lägen sie sonst unter dem Rand, und „Behalten" wäre erst
    // nach Scrollen zu erreichen.
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        children: [
          Text(widget.offerDiscard ? 'Fahrt beendet' : 'Fahrt zerlegen',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${formatLength(totalM)} · ${track.points.length} Punkte'
            '${widget.rideDuration != null ? ' · ${rideDurationLabel(widget.rideDuration!)}' : ''}',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Die Fahrt wird zerlegt: bekannte Trails, Kandidaten, Rest …'),
          ] else if (split != null) ...[
            if (split.known.isNotEmpty) ...[
              Text('Wieder gefahren', style: theme.textTheme.titleMedium),
              const Text('Vorangehakt — als Beleg beigesteuert, das hält den Trail aktuell.'),
              for (var i = 0; i < split.known.length; i++)
                CheckboxListTile(
                  key: ValueKey('split-known-$i'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _knownSelected.contains(i),
                  enabled: !_busy,
                  onChanged: (v) => setState(() {
                    if (v ?? false) {
                      _knownSelected.add(i);
                    } else {
                      _knownSelected.remove(i);
                    }
                    _pushPreview();
                  }),
                  title: Text(split.known[i].trail.displayName),
                  subtitle: Text(formatLength(split.known[i].lengthM)),
                ),
              const SizedBox(height: 12),
            ],
            Text('Kandidaten für neue Trails', style: theme.textTheme.titleMedium),
            if (split.roads != RoadCoverage.complete)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  key: const ValueKey('split-no-roads'),
                  split.roads == RoadCoverage.partial
                      ? 'Die Wege kennt die App hier nur zum Teil: Ein gespeicherter '
                          'Bereich deckt die Fahrt nicht ganz. Kandidaten für neue '
                          'Trails findet sie erst, wenn ein Bereich bis Zoomstufe 13 '
                          'die ganze Fahrt trägt (Ebenen-Knopf auf der Karte → '
                          'Ausschnitt oder Fläche wählen → Speichern).'
                      : 'Die Wege kennt die App hier nicht: Es gibt keinen '
                          'gespeicherten Bereich über der Fahrt. Kandidaten für neue '
                          'Trails findet sie erst damit — Ebenen-Knopf auf der Karte → '
                          'Ausschnitt oder Fläche wählen → Speichern, dann die Fahrt aus '
                          '„Meine Fahrten" noch einmal zerlegen.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else if (!split.hasElevation)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Ohne Höhen lässt sich kein Gefälle finden — die Spur trägt keine.'),
              )
            else if (_drafts.every((d) => d.discarded))
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Kein Stück mit anhaltendem Gefälle abseits von Wegen.'),
              ),
            for (var i = 0; i < _drafts.length; i++)
              if (!_drafts[i].discarded) _candidateCard(i, theme),
            const SizedBox(height: 12),
            Text(
              'Rest: ${formatLength(split.restM)} Anfahrt, Forstweg, Straße — wird nicht angeboten.'
              '${split.droppedInaccurate > 0 ? ' ${split.droppedInaccurate} unscharfe Punkte ausgelassen.' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            if (widget.request.rideId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Die Fahrt bleibt als Ganzes auf deinem Gerät („Meine Fahrten"); '
                  'beigesteuert werden nur die gewählten Stücke.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                  value: _selectedCount == 0 ? null : _done / _selectedCount),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
            children: [
              if (widget.offerDiscard)
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(true),
                  child: const Text('Verwerfen'),
                ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('split-submit'),
                onPressed: _busy || _loading
                    ? null
                    : _selectedCount == 0
                        ? () => Navigator.of(context).pop(false)
                        : _contribute,
                child: Text(_selectedCount == 0
                    ? (widget.offerDiscard ? 'Behalten' : 'Schließen')
                    : '$_selectedCount beisteuern'),
              ),
            ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _candidateCard(int i, ThemeData theme) {
    final d = _drafts[i];
    final s = d.section;
    final lengthM = _lengthOf(d.start, d.end);
    final loss = _lossOf(d.start, d.end);
    final tooShort = lengthM < kTrailMinLengthM;
    return Card(
      key: ValueKey('split-candidate-$i'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  key: ValueKey('split-candidate-check-$i'),
                  value: d.selected && !tooShort,
                  onChanged: _busy || tooShort ? null : (v) => setState(() {
                        d.selected = v ?? false;
                        _pushPreview();
                      }),
                ),
                Expanded(
                  child: TextField(
                    key: ValueKey('split-candidate-name-$i'),
                    controller: d.nameField,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Name', counterText: ''),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                IconButton(
                  key: ValueKey('split-candidate-discard-$i'),
                  tooltip: 'Kandidat verwerfen',
                  icon: const Icon(Icons.close),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            d.discarded = true;
                            _pushPreview();
                          }),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '${formatLength(lengthM)}'
                '${loss != null ? ' · ↓ ${loss.round()} Hm' : ''}'
                ' · ${(s.offRoadShare * 100).round()} % abseits von Wegen'
                '${tooShort ? ' · zu kurz für einen Trail' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (s.nearHome)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  s.nearStart && s.nearEnd
                      ? 'Beginnt und endet nahe Start und Ziel deiner Fahrt.'
                      : s.nearStart
                          ? 'Beginnt nahe deinem Start.'
                          : 'Endet nahe deinem Ziel.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppPalette.of(context).warningText),
                ),
              ),
            // Die zwei Griffe: Punkt für Punkt, die Karte zeigt es.
            RangeSlider(
              key: ValueKey('split-candidate-range-$i'),
              min: s.start.toDouble(),
              max: s.end.toDouble(),
              divisions: s.end - s.start,
              values: RangeValues(d.start.toDouble(), d.end.toDouble()),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                        d.start = v.start.round();
                        d.end = v.end.round();
                        _pushPreview();
                      }),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey('split-candidate-grade-$i'),
                    initialValue: d.grade,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Schwierigkeit (Singletrail-Skala)', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Keine Angabe')),
                      for (final g in kSingletrailScale)
                        DropdownMenuItem<int?>(
                          value: g.value,
                          child: Text('${g.label} · ${g.short}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => d.grade = v),
                  ),
                ),
                SingletrailScaleButton(highlight: d.grade),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on _RideSplitSheet {
  /// Dauer nur bei einer eigenen Fahrt mit Zeiten.
  Duration? get rideDuration {
    final pts = request.track.points;
    final a = pts.first.time, b = pts.last.time;
    return request.rideId == null || a == null || b == null ? null : b.difference(a);
  }
}

/// Jeder n-te Punkt für die blasse Fahrt darunter — dieselbe Grenze wie
/// bei der laufenden Spur.
List<TrackPoint> thinnedTrack(List<TrackPoint> points, {int max = kRideTrackMaxDots}) {
  if (points.length <= max) return points;
  final step = (points.length / max).ceil();
  final kept = <TrackPoint>[for (var i = 0; i < points.length; i += step) points[i]];
  if (kept.last != points.last) kept.add(points.last);
  return kept;
}
