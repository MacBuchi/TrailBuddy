// Die Werkzeugleiste „Ebenen" (seit 0.27.0; Betreiber, 2026-09-29): eine
// schmale Leiste am linken Rand statt des Blatts „Offline-Karten", das
// den halben Schirm deckte. Der Ebenen-Knopf öffnet sie, derselbe Knopf,
// das X und die Zurück-Taste schließen sie — mit Rückfrage, wenn im
// Entwurf noch etwas steht (map_screen.dart). Solange sie offen ist, ist
// abgedunkelt, was nicht auf dem Gerät liegt, und der Entwurf liegt grün
// darüber (area_overlay.dart, area_draw.dart).
//
// Oben die Werkzeuge, die den ENTWURF ändern (Ausschnitt, Fläche dazu,
// Fläche weg, entlang der Trails, Rückgängig), darunter Verwalten,
// Speichern und Schließen. Die Leiste steht mittig links: unten liegen
// Maßstab und Quellenhinweis, oben die Banner — beide bleiben frei.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../map/online_map.dart';
import 'area_downloader.dart';
import 'area_draw.dart';
import 'area_plan.dart';
import 'area_providers.dart';
import 'area_trim.dart';

/// Kachelzahl kurz, für den Platz unter dem Speichern-Symbol.
String compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')} k';
  return '${(n / 1000).round()} k';
}

class OfflineToolRail extends ConsumerWidget {
  const OfflineToolRail({
    super.key,
    required this.onFilter,
    required this.onSnapshot,
    required this.onTrails,
    required this.onManage,
    required this.onSave,
    required this.onClose,
  });

  final VoidCallback onFilter;
  final VoidCallback onSnapshot;
  final VoidCallback? onTrails;
  final VoidCallback onManage;
  final void Function(AreaDraft draft) onSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(areaDraftProvider);
    final notifier = ref.read(areaDraftProvider.notifier);
    final maxZoom = ref.watch(mapManifestProvider).valueOrNull?.maxZoom ?? kAreaShapeZoom;
    final empty = draft == null || draft.isEmpty;
    // Kacheln über alle Zoomstufen, wie sie geladen bzw. frei werden.
    final adds = draft == null || draft.adds.isEmpty ? 0 : draft.addShape.countTiles(maxZoom: maxZoom);
    final removes = draft == null || draft.removes.isEmpty ? 0 : draft.removeShape.countTiles(maxZoom: maxZoom);
    final tooLarge = adds > kAreaMaxTiles;
    final countStyle = Theme.of(context).textTheme.labelSmall;
    final scheme = Theme.of(context).colorScheme;

    Widget button(String key, String tip, Widget icon, VoidCallback? onPressed, {bool selected = false}) =>
        IconButton(
          key: ValueKey(key),
          tooltip: tip,
          isSelected: selected,
          // 36 statt 48 dp: Die Leiste soll auch auf einem kurzen Schirm
          // zwischen Banner und Maßstab passen.
          iconSize: 20,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          style: IconButton.styleFrom(
            backgroundColor: selected ? scheme.primaryContainer : null,
            // Sonst polstert Material jeden Knopf auf 48 dp Trefferfläche
            // auf, und die Leiste wird um ein Drittel höher (gemessen).
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onPressed,
          icon: icon,
        );

    Widget tool(AreaDrawTool t, String key, String tip, Widget icon) =>
        button(key, tip, icon, () => notifier.arm(t), selected: draft?.tool == t);

    return Card(
      key: const ValueKey('offline-tool-rail'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            button('rail-filter', 'Orte und offizielle Trails', const Icon(Icons.tune), onFilter),
            const _RailDivider(),
            button('rail-snapshot', 'Ausschnitt dazunehmen', const Icon(Icons.photo_camera_outlined), onSnapshot),
            tool(AreaDrawTool.add, 'area-draw-add', 'Fläche dazunehmen',
                const _PolygonIcon(sign: Icons.add)),
            tool(AreaDrawTool.remove, 'area-draw-remove', 'Fläche wegnehmen',
                const _PolygonIcon(sign: Icons.remove)),
            button('area-draw-trails', 'Entlang meiner Trails dazunehmen', const Icon(Icons.route_outlined),
                onTrails),
            button('area-draw-undo', 'Rückgängig', const Icon(Icons.undo),
                draft == null || draft.history.isEmpty ? null : notifier.undo),
            const _RailDivider(),
            button('manage-areas', 'Meine Bereiche verwalten', const _ManageIcon(), onManage),
            button(
              'area-draw-save',
              tooLarge
                  ? '+$adds Kacheln — zu viel auf einmal, erlaubt sind $kAreaMaxTiles'
                  : empty
                      ? 'Speichern — noch keine Änderung'
                      : 'Speichern (+$adds / −$removes Kacheln)',
              const Icon(Icons.save_outlined),
              empty || tooLarge
                  ? null
                  : () {
                      notifier.disarm();
                      onSave(draft);
                    },
            ),
            // Was dazukommt (grün) und was wegfällt (rot) — getrennt, wie
            // auf der Karte.
            Text(
              adds == 0 ? (removes == 0 ? '–' : '') : '+${compactCount(adds)}',
              key: const ValueKey('area-draw-count'),
              style: countStyle?.copyWith(
                color: tooLarge ? scheme.error : kAreaAddHatch.withValues(alpha: 1),
                fontWeight: FontWeight.bold,
              ),
            ),
            if (removes > 0)
              Text(
                '−${compactCount(removes)}',
                key: const ValueKey('area-draw-remove-count'),
                style: countStyle?.copyWith(color: kAreaRemoveHatch.withValues(alpha: 1), fontWeight: FontWeight.bold),
              ),
            const _RailDivider(),
            button('offline-maps-close', 'Schließen', const Icon(Icons.close), onClose),
          ],
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 24, child: Divider(height: 6));
}

/// Vieleck mit Plus oder Minus: Fläche dazu oder weg.
class _PolygonIcon extends StatelessWidget {
  const _PolygonIcon({required this.sign});

  final IconData sign;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: Stack(children: [
          const Icon(Icons.pentagon_outlined, size: 20),
          Positioned(
            right: -1,
            bottom: -1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
              child: Icon(sign, size: 13),
            ),
          ),
        ]),
      );
}

/// Karte mit Zahnrad: die gespeicherten Bereiche verwalten.
class _ManageIcon extends StatelessWidget {
  const _ManageIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: Stack(children: [
          const Icon(Icons.map_outlined, size: 20),
          Positioned(
            right: -1,
            bottom: -1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
              child: const Icon(Icons.settings, size: 13),
            ),
          ),
        ]),
      );
}

/// „Entwurf verwerfen?" — true heißt verwerfen.
Future<bool> confirmDiscardDraft(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Entwurf verwerfen?'),
        content: const Text('Die gewählten Kacheln sind noch nicht gespeichert.'),
        actions: [
          TextButton(
            key: const ValueKey('draft-keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Weiter bearbeiten'),
          ),
          FilledButton(
            key: const ValueKey('draft-discard'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    ) ??
    false;

/// Der Dialog vor dem Speichern: misst, was dazukommt (Kacheln, Bytes,
/// Orte — braucht den Kartenhost) und was wegfällt (lokal, ohne Netz),
/// fragt nach dem Namen des neuen Bereichs, schreibt dann erst die
/// Bereiche ohne die wegfallenden Kacheln neu und lädt danach. `true`,
/// wenn alles gespeichert ist.
Future<bool> showSaveDraftDialog(BuildContext context, AreaDraft draft) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaveDraftDialog(draft: draft),
    ) ??
    false;

class _SaveDraftDialog extends ConsumerStatefulWidget {
  const _SaveDraftDialog({required this.draft});

  final AreaDraft draft;

  @override
  ConsumerState<_SaveDraftDialog> createState() => _SaveDraftDialogState();
}

class _SaveDraftDialogState extends ConsumerState<_SaveDraftDialog> {
  static final _date = DateFormat('d. MMMM', 'de');

  late final TextEditingController _name =
      TextEditingController(text: 'Bereich vom ${_date.format(DateTime.now())}');
  AreaPlan? _plan;
  TrimPlan? _trim;
  String? _error;
  bool _measuring = true;
  bool _trimming = false;

  bool get _hasAdds => widget.draft.adds.isNotEmpty;
  bool get _hasRemoves => widget.draft.removes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Ein früherer Download (fertig, gescheitert) gehört nicht hierher.
      ref.read(areaDownloadProvider.notifier).reset();
      _measure();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    try {
      if (_hasRemoves) {
        final trim = await ref.read(storedAreasProvider.notifier).planTrim(widget.draft.removes);
        if (mounted) setState(() => _trim = trim);
      }
      if (_hasAdds) {
        final plan = await ref.read(areaDownloadProvider.notifier).plan(widget.draft.addShape);
        if (mounted) setState(() => _plan = plan);
      }
    } on AreaTooLarge catch (e) {
      if (mounted) setState(() => _error = 'Zu viel auf einmal: ${e.tiles} Kacheln, erlaubt sind $kAreaMaxTiles.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = looksOffline(e) || e is StateError
          ? 'Ohne Empfang lässt sich nichts dazuladen — der Kartenhost ist nicht erreichbar. '
              'Entfernen geht auch offline: dazu die grünen Kacheln wegnehmen.'
          : 'Die Größe ließ sich nicht messen.');
    } finally {
      if (mounted) setState(() => _measuring = false);
    }
  }

  bool get _ready =>
      !_measuring &&
      _error == null &&
      (!_hasAdds || (_plan != null && _plan!.tiles.isNotEmpty) || (_hasRemoves && _plan != null)) &&
      (!_hasRemoves || _trim != null);

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final trim = _trim;
    if (trim != null && !trim.isEmpty) {
      setState(() => _trimming = true);
      try {
        await ref.read(storedAreasProvider.notifier).applyTrim(trim);
      } catch (e, s) {
        logError('Kacheln entfernen', e, s);
        if (mounted) {
          setState(() {
            _trimming = false;
            _error = 'Das Entfernen ließ sich nicht speichern.';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() => _trimming = false);
    }
    final plan = _plan;
    if (plan != null && plan.tiles.isNotEmpty) {
      final name = _name.text.trim().isEmpty ? 'Bereich' : _name.text.trim();
      final area = await ref.read(areaDownloadProvider.notifier).start(plan, name: name);
      if (area == null) {
        // Gescheitert oder abgebrochen: Der Fehler steht im Dialog. Das
        // Entfernen ist schon gespeichert — der Entwurf behält es nicht.
        if (trim != null && !trim.isEmpty) {
          ref.read(areaDraftProvider.notifier).dropRemoves();
          messenger.showSnackBar(const SnackBar(content: Text('Entfernt ist gespeichert, das Laden nicht.')));
        }
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  static String _progressLine(AreaProgress? p) {
    if (p == null) return 'Verbindung zum Kartenhost …';
    return switch (p.phase) {
      AreaPhase.tiles => 'Kacheln ${p.done} von ${p.total}',
      AreaPhase.pois => 'Orte ${p.done} von ${p.total}',
      AreaPhase.writing => 'Archiv wird geschrieben …',
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final download = ref.watch(areaDownloadProvider);
    final plan = _plan;
    final trim = _trim;
    final running = download.phase == AreaDownloadPhase.running;
    final errorStyle = text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error);

    final Widget body;
    if (running || _trimming) {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_trimming ? 'Kacheln werden entfernt …' : '„${download.name}" wird gespeichert …'),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _trimming ? null : download.progress?.fraction),
        if (!_trimming) ...[
          const SizedBox(height: 4),
          Text(_progressLine(download.progress), style: text.bodySmall),
        ],
      ]);
    } else if (_measuring) {
      body = const Row(children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Expanded(child: Text('Größe und Orte werden gemessen …')),
      ]);
    } else {
      final pois = plan?.poiCount;
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (plan != null)
          Text(
            plan.tiles.isEmpty
                ? 'Dazu: hier liegt keine Karte — außerhalb von Deutschland, Österreich und der Schweiz.'
                : 'Lädt ${formatBytes(plan.totalBytes)} · ${plan.tiles.length} Kacheln'
                    '${pois == null ? ' · ohne Orte' : ' · $pois ${pois == 1 ? 'Ort' : 'Orte'}'}',
            key: const ValueKey('area-size'),
            style: text.titleMedium?.copyWith(color: kAreaAddHatch.withValues(alpha: 1)),
          ),
        if (trim != null)
          Text(
            'Gibt ${formatBytes(trim.freedBytes)} frei · ${trim.freedTiles} Kacheln'
            '${trim.trims.where((t) => t.shape == null).isEmpty ? '' : ' · ${trim.trims.where((t) => t.shape == null).length} Bereich(e) ganz'}',
            key: const ValueKey('area-free'),
            style: text.titleMedium?.copyWith(color: kAreaRemoveHatch.withValues(alpha: 1)),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: errorStyle),
        ],
        if (plan != null && plan.tiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('area-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name des neuen Bereichs'),
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
        if (download.phase == AreaDownloadPhase.failed && download.error != null) ...[
          const SizedBox(height: 8),
          Text(download.error!, style: errorStyle),
        ],
      ]);
    }

    return AlertDialog(
      title: const Text('Änderungen speichern?'),
      content: SingleChildScrollView(child: body),
      actions: [
        if (running)
          TextButton(
            key: const ValueKey('area-cancel'),
            onPressed: () => ref.read(areaDownloadProvider.notifier).cancel(),
            child: const Text('Abbrechen'),
          )
        else ...[
          TextButton(
            key: const ValueKey('area-save-cancel'),
            onPressed: _trimming ? null : () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const ValueKey('area-save'),
            onPressed: _ready && !_trimming ? _save : null,
            child: const Text('Speichern'),
          ),
        ],
      ],
    );
  }
}
