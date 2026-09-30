import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../data/providers.dart';
import '../../core/router_branches.dart';
import '../../models/trail.dart';
import '../rides/ride_split_sheet.dart';
import 'elevation_backfill.dart';
import 'gpx.dart';
import 'gpx_files.dart';
import 'trail_geometry.dart';
import 'trail_details_dialog.dart';
import 'trail_providers.dart';
import 'trail_sheet.dart';
import 'trail_takeover.dart';

/// Dateiauswahl als Provider, damit Tests Dateien einhängen, ohne den
/// System-Dialog zu öffnen.
///
/// **Auf Android ohne Typfilter.** Der System-Dialog (SAF) filtert nach
/// MIME-Typen, und für `.gpx` gibt es keinen registrierten — Dateimanager
/// melden `application/octet-stream` oder gar nichts. Mit einem Filter auf
/// `application/gpx+xml` waren GPX- UND Zip-Dateien ausgegraut, die
/// Auswahl scheiterte, bevor die App eine Datei sah (Feldbefund v0.1.0,
/// dieselbe Lehre wie im PilzBuddy-Import). Geprüft wird deshalb danach,
/// in [gpxFilesFrom]. Im Browser filtert die Endung bequem vor.
final gpxPickerProvider = Provider<Future<List<PickedFile>> Function()>((ref) {
  return () async {
    const typeGroups = kIsWeb
        ? [XTypeGroup(label: 'GPX oder Zip', extensions: ['gpx', 'zip'])]
        : [XTypeGroup(label: 'Alle Dateien', mimeTypes: ['*/*'])];
    final files = await openFiles(acceptedTypeGroups: typeGroups);
    return [
      for (final f in files) PickedFile(name: f.name, bytes: await f.readAsBytes()),
    ];
  };
});

/// Ein Kandidat aus einer Datei, mit der Einordnung nach Konzept 5.2.
class ImportCandidate {
  ImportCandidate(this.file, this.track,
      {this.existing, this.existingNameMissing = false})
      : lengthM = trackLengthM(track.points),
        // Aus der VEREINFACHTEN Spur, also aus genau dem, was hochgeht:
        // Das Blatt rechnet danach mit denselben Punkten, und die Zahl
        // hier soll dieselbe sein wie dort.
        elevation = elevationGainLoss(simplify(track.points)),
        kind = classifyTrack(track.points),
        source = sourceOf(track.points);

  final String file;
  final GpxTrack track;
  final double lengthM;
  final ({double gain, double loss})? elevation;
  final TrackKind kind;
  final RecordingSource source;

  /// EINE Kennung je Kandidat, beim Einlesen vergeben: Ein zweiter
  /// Versuch nach einem Abriss trägt dieselbe, und der Server antwortet
  /// mit der Aufzeichnung von damals statt eine zweite anzulegen.
  final String clientId = newClientId();

  /// Diese Spur liegt schon als eigene Aufzeichnung auf dem Server (#16).
  /// Dann wird sie nie ein zweites Mal beigesteuert — höchstens bekommt
  /// die alte ihre Höhen.
  final ExistingRecording? existing;

  bool get backfill => existing?.canBackfill ?? false;

  /// Die schon beigesteuerte Aufzeichnung hat keinen eigenen Namen — etwa
  /// weil der Name aus der Datei vor 0.9.1 zu lang war und das Speichern
  /// scheiterte. Dann übernimmt ein zweiter Import ihn.
  final bool existingNameMissing;

  bool get adoptsName =>
      existing != null && existingNameMissing && track.name.trim().isNotEmpty;

  /// Etwas an einer schon beigesteuerten Aufzeichnung nachtragen (Höhen
  /// oder Name) — nie eine zweite anlegen.
  bool get completesExisting => backfill || adoptsName;

  bool get contributable =>
      existing == null ? kind == TrackKind.trail : completesExisting;
}

class TrailImportScreen extends ConsumerStatefulWidget {
  const TrailImportScreen({super.key});

  @override
  ConsumerState<TrailImportScreen> createState() => _TrailImportScreenState();
}

class _TrailImportScreenState extends ConsumerState<TrailImportScreen> {
  final _candidates = <ImportCandidate>[];
  final _selected = <ImportCandidate>{};
  final _errors = <String>[];
  bool _busy = false;
  int _done = 0;
  ({int ok, int queued, int backfilled, int named, int failed})? _result;

  /// Trails, die ich vor dem Import schon über Buddys sah und jetzt selbst
  /// belegt habe (#102): Das Ergebnis bietet an, sie zu übernehmen. Erst
  /// NACH der RPC weiß der Client, dass eine Kennung dazugehört.
  final _takeOverIds = <String>[];

  Future<void> _pick() async {
    final List<PickedFile> picked;
    try {
      picked = await ref.read(gpxPickerProvider)();
    } catch (e, st) {
      logError('GPX auswählen', e, st);
      if (mounted) setState(() => _errors.add('Dateiauswahl fehlgeschlagen.'));
      return;
    }
    if (!mounted) return;
    final files = <PickedGpx>[];
    final unreadable = <String>[];
    for (final p in picked) {
      final r = gpxFilesFrom(p);
      files.addAll(r.files);
      unreadable.addAll(r.errors);
    }
    // Die eigenen Aufzeichnungen, gegen die jede Spur geprüft wird: Wer
    // denselben Zip noch einmal wählt, soll keine Doppel anlegen.
    // Noch nicht geladen (Import direkt nach dem Start): abwarten. Geht
    // das Laden schief, wird ohne Abgleich importiert wie vor #16 — der
    // Server legt dann schlimmstenfalls eine zweite Aufzeichnung an.
    List<Trail> trails;
    try {
      trails = await ref.read(trailsProvider.future);
    } catch (_) {
      trails = const [];
    }
    if (!mounted) return;
    final myId = ref.read(currentUserIdProvider);
    final own = <TrailRecording>[
      for (final t in trails)
        for (final r in t.recordings)
          if (r.userId == myId) r,
    ];
    setState(() {
      _result = null;
      _errors.addAll(unreadable);
      for (final f in files) {
        try {
          for (final t in parseGpx(f.text, fallbackName: f.name)) {
            final existing = own.isEmpty ? null : findOwnRecording(t, own);
            final c = ImportCandidate(f.name, t,
                existing: existing,
                existingNameMissing: existing != null &&
                    (trails
                                .where((x) => x.id == existing.recording.trailId)
                                .firstOrNull
                                ?.myDetails
                                ?.name ??
                            '')
                        .trim()
                        .isEmpty);
            _candidates.add(c);
            if (c.contributable) _selected.add(c);
          }
        } on GpxFormatException catch (e) {
          _errors.add('${f.name}: ${e.message}');
        }
      }
    });
  }

  Future<void> _contribute() async {
    final chosen = _candidates.where(_selected.contains).toList();
    if (chosen.isEmpty) return;
    setState(() {
      _busy = true;
      _done = 0;
    });
    var ok = 0;
    var queued = 0;
    var backfilled = 0;
    var named = 0;
    var failed = 0;
    var limitHit = false;
    final succeeded = <ImportCandidate>{};
    final notifier = ref.read(trailsProvider.notifier);
    // Was ich bisher nur über Buddys sehe — ohne eigenen Beitrag.
    final onlyThroughBuddies = {
      for (final t in ref.read(trailsProvider).valueOrNull ?? const <Trail>[])
        if (needsTakeOver(t)) t.id,
    };
    _takeOverIds.clear();
    for (final c in chosen) {
      try {
        if (c.completesExisting) {
          // Zählt nicht ins Tageslimit, legt nichts Neues an. false heißt:
          // hatte inzwischen schon Höhen — auch das ist erledigt.
          if (c.backfill) {
            await notifier.attachElevation(c.existing!);
            backfilled++;
          }
          if (c.adoptsName &&
              await notifier.adoptName(
                  c.existing!.recording.trailId, c.track.name)) {
            named++;
          }
        } else {
          // Ohne Netz landet der Auftrag im Ausgangskorb (#30) und der
          // Trail steht als wartender auf der Karte — kein Fehler.
          final r = await notifier.contribute(c.track, clientId: c.clientId);
          if (r.queued) {
            queued++;
          } else {
            ok++;
            if (onlyThroughBuddies.contains(r.trailId) && !_takeOverIds.contains(r.trailId)) {
              _takeOverIds.add(r.trailId);
            }
          }
        }
        succeeded.add(c);
      } on DailyLimitException {
        // Kein Fehlerbericht: das ist die Regel, kein Defekt. Alle weiteren
        // scheiterten genauso, also hier aufhören.
        limitHit = true;
        break;
      } catch (e, st) {
        logError('Trail beisteuern', e, st);
        failed++;
        _errors.add('${c.track.name}: ${friendlyError(e)}');
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    // Nur neu laden, wenn etwas auf dem Server gelandet ist — ohne Netz
    // wäre das ein Fehler über einer Liste, die den Korb längst zeigt.
    final fresh = ok + backfilled + named == 0 ||
        await notifier.reloadAfterWrite('Trails nach Import laden');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = (ok: ok, queued: queued, backfilled: backfilled, named: named, failed: failed);
      if (limitHit) {
        _errors.add('Für heute ist das Limit erreicht. Die übrigen bleiben '
            'angehakt — morgen einfach noch einmal „beisteuern".');
      }
      // Gescheiterte bleiben angehakt stehen — ein zweiter Versuch ist
      // ein Tipp, und die Kennung des Auftrags macht ihn idempotent.
      _candidates.removeWhere(succeeded.contains);
      _selected.removeWhere(succeeded.contains);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '$ok ${ok == 1 ? 'Trail' : 'Trails'} beigesteuert'
        '${queued > 0 ? ', $queued ${queued == 1 ? 'wartet' : 'warten'} im Ausgangskorb auf Netz' : ''}'
        '${backfilled > 0 ? ', $backfilled mit nachgetragenen Höhen' : ''}'
        '${named > 0 ? ', $named ${named == 1 ? 'Name' : 'Namen'} übernommen' : ''}'
        '${failed > 0 ? ', $failed fehlgeschlagen' : ''}'
        '${fresh ? '' : ' — sichtbar, sobald die Liste wieder lädt.'}',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectable =
        _candidates.where((c) => c.contributable && c.existing == null).length;
    final backfills = _candidates.where((c) => c.completesExisting).length;
    return Scaffold(
      appBar: AppBar(title: const Text('GPX importieren')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Kurze Spuren, die überwiegend bergab führen, werden als Trail '
            'beigesteuert. Ganze Fahrten (ab 8 km oder mit mehr Auf- als '
            'Abstieg) zerlegst du auf der Karte in bekannte Trails und '
            'Kandidaten — die Schere neben der Spur. Was du beisteuerst, '
            'sehen deine Buddys; der Server gleicht es still mit bekannten '
            'Trails ab.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open),
            label: const Text('GPX- oder Zip-Dateien wählen'),
          ),
          for (final e in _errors)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(e, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${_result!.ok} beigesteuert, '
                '${_result!.queued > 0 ? '${_result!.queued} im Ausgangskorb, ' : ''}'
                '${_result!.backfilled > 0 ? '${_result!.backfilled} Höhen nachgetragen, ' : ''}'
                '${_result!.named > 0 ? '${_result!.named} Namen übernommen, ' : ''}'
                '${_result!.failed} fehlgeschlagen.',
                style: theme.textTheme.titleSmall,
              ),
            ),
          // Schon im Netz (#102): dieselbe Übernahme wie im Zerlege-Blatt,
          // vorbelegt aus dem, was die Buddys sagen.
          for (final id in _takeOverIds)
            if (ref.watch(trailByIdProvider(id)) case final t?)
              ListTile(
                key: ValueKey('import-takeover-$id'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.group_outlined),
                title: Text(t.displayName),
                subtitle: Text(offersTakeOver(t) || t.ratingOpen
                    ? 'Kanntest du schon über deine Buddys — übernimm ihn mit deinen Sternen.'
                    : 'Übernommen.'),
                trailing: offersTakeOver(t) || t.ratingOpen
                    ? FilledButton.tonal(
                        key: ValueKey('import-takeover-open-$id'),
                        onPressed: () => showTrailDetailsDialog(context, ref, t, takeOver: true),
                        child: const Text('Übernehmen'),
                      )
                    : null,
              ),
          if (_candidates.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
                '${_candidates.length} Spuren gefunden, $selectable davon als Trail'
                '${backfills > 0 ? ', $backfills zum Nachtragen' : ''}',
                style: theme.textTheme.titleSmall),
            for (final c in _candidates)
              CheckboxListTile(
                value: _selected.contains(c),
                enabled: c.contributable && !_busy,
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _selected.add(c);
                  } else {
                    _selected.remove(c);
                  }
                }),
                title: Text(c.track.name),
                subtitle: Text(_describe(c)),
                controlAffinity: ListTileControlAffinity.leading,
                // Eine Fahrt geht durch das Zerlege-Blatt (Konzept 5.2),
                // auf der Karte — dort sieht man, was die Griffe tun.
                secondary: c.existing == null && c.kind == TrackKind.ride
                    ? IconButton(
                        key: ValueKey('import-split-${c.clientId}'),
                        tooltip: 'Fahrt zerlegen',
                        icon: const Icon(Icons.content_cut),
                        onPressed: _busy
                            ? null
                            : () {
                                StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
                                ref.read(mapSplitRequestProvider.notifier).state =
                                    SplitRequest.fromGpx(c.track);
                              },
                      )
                    : null,
              ),
            const SizedBox(height: 12),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(
                    value: _selected.isEmpty ? null : _done / _selected.length),
              ),
            FilledButton.icon(
              onPressed: _busy || _selected.isEmpty ? null : _contribute,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(_selected.any((c) => c.completesExisting)
                  ? '${_selected.length} übernehmen'
                  : '${_selected.length} beisteuern'),
            ),
          ],
        ],
      ),
    );
  }

  String _describe(ImportCandidate c) {
    final parts = <String>[formatLength(c.lengthM)];
    final existing = c.existing;
    if (existing != null) {
      parts.add(c.backfill && c.adoptsName
          ? 'schon beigesteuert — Höhen und Name werden nachgetragen'
          : c.backfill
              ? 'schon beigesteuert — Höhen werden nachgetragen'
              : c.adoptsName
                  ? 'schon beigesteuert — Name wird übernommen'
                  : existing.recording.ele != null
                      ? 'schon beigesteuert'
                      : 'schon beigesteuert, die Datei hat keine Höhen');
      return parts.join(' · ');
    }
    final el = c.elevation;
    if (el != null) parts.add(formatElevation(el));
    parts.add(switch (c.source) {
      RecordingSource.planned => 'geplant (keine Fahrzeiten)',
      RecordingSource.import => 'aufgezeichnet',
      RecordingSource.app => 'aufgezeichnet',
    });
    parts.add(switch (c.kind) {
      TrackKind.trail => 'Trail',
      TrackKind.ride => 'Fahrt — auf der Karte zerlegen',
      TrackKind.fragment => 'zu kurz für einen Trail',
    });
    return parts.join(' · ');
  }
}
