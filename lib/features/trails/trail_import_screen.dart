import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import 'gpx.dart';
import 'trail_geometry.dart';
import 'trail_providers.dart';
import 'trail_sheet.dart';

/// Eine ausgewählte Datei — Name und Inhalt, mehr braucht der Import nicht.
class PickedGpx {
  const PickedGpx({required this.name, required this.text});
  final String name;
  final String text;
}

/// Dateiauswahl als Provider, damit Tests Dateien einhängen, ohne den
/// System-Dialog zu öffnen.
final gpxPickerProvider = Provider<Future<List<PickedGpx>> Function()>((ref) {
  return () async {
    final files = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(label: 'GPX', extensions: ['gpx'], mimeTypes: ['application/gpx+xml']),
    ]);
    return [
      for (final f in files) PickedGpx(name: f.name, text: await f.readAsString()),
    ];
  };
});

/// Ein Kandidat aus einer Datei, mit der Einordnung nach Konzept 5.2.
class ImportCandidate {
  ImportCandidate(this.file, this.track)
      : lengthM = trackLengthM(track.points),
        elevation = elevationGainLoss(track.points),
        kind = classifyTrack(track.points),
        source = sourceOf(track.points);

  final String file;
  final GpxTrack track;
  final double lengthM;
  final ({double gain, double loss})? elevation;
  final TrackKind kind;
  final RecordingSource source;

  bool get contributable => kind == TrackKind.trail;
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
  ({int ok, int failed})? _result;

  Future<void> _pick() async {
    final List<PickedGpx> files;
    try {
      files = await ref.read(gpxPickerProvider)();
    } catch (e, st) {
      logError('GPX auswählen', e, st);
      if (mounted) setState(() => _errors.add('Dateiauswahl fehlgeschlagen.'));
      return;
    }
    if (!mounted) return;
    setState(() {
      _result = null;
      for (final f in files) {
        try {
          for (final t in parseGpx(f.text, fallbackName: f.name)) {
            final c = ImportCandidate(f.name, t);
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
    var failed = 0;
    final succeeded = <ImportCandidate>{};
    final notifier = ref.read(trailsProvider.notifier);
    for (final c in chosen) {
      try {
        await notifier.contribute(c.track);
        succeeded.add(c);
        ok++;
      } catch (e, st) {
        logError('Trail beisteuern', e, st);
        failed++;
        _errors.add('${c.track.name}: ${friendlyError(e)}');
      }
      if (!mounted) return;
      setState(() => _done = ok + failed);
    }
    final fresh = await notifier.reloadAfterWrite('Trails nach Import laden');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = (ok: ok, failed: failed);
      // Gescheiterte bleiben angehakt stehen — ein zweiter Versuch ist
      // ein Tipp, und die Kennung des Auftrags macht ihn idempotent.
      _candidates.removeWhere(succeeded.contains);
      _selected.removeWhere(succeeded.contains);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '$ok ${ok == 1 ? 'Trail' : 'Trails'} beigesteuert'
        '${failed > 0 ? ', $failed fehlgeschlagen' : ''}'
        '${fresh ? '' : ' — sichtbar, sobald die Liste wieder lädt.'}',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectable = _candidates.where((c) => c.contributable).length;
    return Scaffold(
      appBar: AppBar(title: const Text('GPX importieren')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Kurze Spuren, die überwiegend bergab führen, werden als Trail '
            'beigesteuert. Ganze Fahrten (ab 8 km oder mit mehr Auf- als '
            'Abstieg) müssen erst zerlegt werden — das kommt in einem '
            'späteren Stand. Was du beisteuerst, sehen deine Buddys; der '
            'Server gleicht es still mit bekannten Trails ab.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open),
            label: const Text('GPX-Dateien wählen'),
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
                '${_result!.ok} beigesteuert, ${_result!.failed} fehlgeschlagen.',
                style: theme.textTheme.titleSmall,
              ),
            ),
          if (_candidates.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('${_candidates.length} Spuren gefunden, $selectable davon als Trail',
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
              label: Text('${_selected.length} beisteuern'),
            ),
          ],
        ],
      ),
    );
  }

  String _describe(ImportCandidate c) {
    final parts = <String>[formatLength(c.lengthM)];
    final el = c.elevation;
    if (el != null) parts.add('↓ ${el.loss.round()} m · ↑ ${el.gain.round()} m');
    parts.add(switch (c.source) {
      RecordingSource.planned => 'geplant (keine Fahrzeiten)',
      RecordingSource.import => 'aufgezeichnet',
      RecordingSource.app => 'aufgezeichnet',
    });
    parts.add(switch (c.kind) {
      TrackKind.trail => 'Trail',
      TrackKind.ride => 'Fahrt — zerlegen kommt später',
      TrackKind.fragment => 'zu kurz für einen Trail',
    });
    return parts.join(' · ');
  }
}
