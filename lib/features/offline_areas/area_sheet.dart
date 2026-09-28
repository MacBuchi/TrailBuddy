// „Bereich speichern" (Konzept 3.2): der aktuelle Ausschnitt oder ein
// Rahmen um die eigenen Trails mit Rand; die Größe steht VOR dem
// Speichern da, exakt aus dem Verzeichnis des Archivs; dann Fortschritt
// und Abbruch. Ohne Empfang gibt es keinen Bereich — das Blatt sagt es.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../map/online_map.dart';
import 'area_downloader.dart';
import 'area_plan.dart';
import 'area_providers.dart';

enum _Choice { viewport, trails }

Future<void> showSaveAreaSheet(
  BuildContext context, {
  required AreaBounds? viewport,
  required AreaBounds? aroundTrails,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SaveAreaSheet(viewport: viewport, aroundTrails: aroundTrails),
    );

class _SaveAreaSheet extends ConsumerStatefulWidget {
  const _SaveAreaSheet({required this.viewport, required this.aroundTrails});

  final AreaBounds? viewport;
  final AreaBounds? aroundTrails;

  @override
  ConsumerState<_SaveAreaSheet> createState() => _SaveAreaSheetState();
}

class _SaveAreaSheetState extends ConsumerState<_SaveAreaSheet> {
  static final _date = DateFormat('d. MMMM', 'de');

  late final TextEditingController _name;
  _Choice _choice = _Choice.viewport;
  AreaPlan? _plan;
  String? _planError;
  bool _planning = false;

  AreaBounds? get _bounds => switch (_choice) {
        _Choice.viewport => widget.viewport,
        _Choice.trails => widget.aroundTrails,
      };

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: 'Bereich vom ${_date.format(DateTime.now())}');
    if (widget.viewport == null && widget.aroundTrails != null) _choice = _Choice.trails;
    // Der Zustand eines früheren Downloads (fertig, gescheitert) gehört
    // nicht auf ein frisches Blatt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(areaDownloadProvider.notifier).reset();
    });
    _measure();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    final bounds = _bounds;
    if (bounds == null) return;
    setState(() {
      _planning = true;
      _plan = null;
      _planError = null;
    });
    try {
      final plan = await ref.read(areaDownloadProvider.notifier).plan(bounds);
      if (!mounted) return;
      setState(() => _plan = plan);
    } on AreaTooLarge catch (e) {
      if (!mounted) return;
      setState(() => _planError =
          'Zu groß: ${e.tiles} Kacheln, erlaubt sind $kAreaMaxTiles. Näher heranzoomen oder zwei Bereiche speichern.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _planError = looksOffline(e) || e is StateError
          ? 'Ohne Empfang lässt sich kein Bereich speichern — der Kartenhost ist nicht erreichbar.'
          : 'Die Größe ließ sich nicht messen.');
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null) return;
    final name = _name.text.trim().isEmpty ? 'Bereich' : _name.text.trim();
    await ref.read(areaDownloadProvider.notifier).start(plan, name: name);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final download = ref.watch(areaDownloadProvider);
    final manifest = ref.watch(mapManifestProvider).valueOrNull;
    final plan = _plan;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bereich für unterwegs speichern', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Die Karte dieses Bereichs bis Zoomstufe ${manifest?.maxZoom ?? 13} '
              'samt Orten bleibt auf dem Gerät — für den Wald ohne Empfang. '
              'Bereiche werden nie von selbst gelöscht.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),
            if (download.phase == AreaDownloadPhase.done && download.result != null) ...[
              Row(children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        '„${download.result!.name}" gespeichert: ${formatBytes(download.result!.bytes)}.')),
              ]),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig')),
              ),
            ] else if (download.phase == AreaDownloadPhase.running) ...[
              Text('„${download.name}" wird gespeichert …', style: text.titleMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: download.progress?.fraction),
              const SizedBox(height: 8),
              Text(_progressLine(download.progress), style: text.bodySmall),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('area-cancel'),
                  onPressed: () => ref.read(areaDownloadProvider.notifier).cancel(),
                  child: const Text('Abbrechen'),
                ),
              ),
            ] else ...[
              RadioGroup<_Choice>(
                groupValue: _choice,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _choice = v);
                  _measure();
                },
                child: Column(children: [
                  RadioListTile<_Choice>(
                    key: const ValueKey('area-choice-viewport'),
                    value: _Choice.viewport,
                    enabled: widget.viewport != null,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktueller Ausschnitt'),
                  ),
                  RadioListTile<_Choice>(
                    key: const ValueKey('area-choice-trails'),
                    value: _Choice.trails,
                    enabled: widget.aroundTrails != null,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Um meine Trails'),
                    subtitle: Text(widget.aroundTrails == null
                        ? 'Noch keine Trails auf der Karte'
                        : 'Mit ${kAreaTrailsMarginKm.round()} km Rand'),
                  ),
                ]),
              ),
              TextField(
                key: const ValueKey('area-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              if (_planning)
                const Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Größe wird gemessen …'),
                ])
              else if (_planError != null)
                Text(_planError!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error))
              else if (plan != null)
                Text(
                  plan.tiles.isEmpty
                      ? 'Hier liegt keine Karte — außerhalb von Deutschland, Österreich und der Schweiz.'
                      : '${plan.tiles.length} Kacheln, ${formatBytes(plan.bytes)}',
                  key: const ValueKey('area-size'),
                  style: text.titleMedium,
                ),
              if (download.phase == AreaDownloadPhase.failed && download.error != null) ...[
                const SizedBox(height: 8),
                Text(download.error!,
                    style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('area-save'),
                  onPressed: plan != null && plan.tiles.isNotEmpty && !_planning ? _save : null,
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(plan == null ? 'Speichern' : 'Speichern (${formatBytes(plan.bytes)})'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _progressLine(AreaProgress? p) {
    if (p == null) return 'Verbindung zum Kartenhost …';
    return switch (p.phase) {
      AreaPhase.tiles => 'Kacheln ${p.done} von ${p.total}',
      AreaPhase.pois => 'Orte ${p.done} von ${p.total}',
      AreaPhase.writing => 'Archiv wird geschrieben …',
    };
  }
}
