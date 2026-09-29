// Das Blatt „Offline-Karten" (Stufe B, gezeichnet seit Stufe C; Betreiber, 2026-09-28: „die
// Offline-Karten-Settings in einem Menüpunkt, wird dieser aufgerufen,
// erfolgt schon die hervorgehobene Darstellung bis man das Menü
// schließt"): die gespeicherten Bereiche, „Bereich speichern", der Weg
// zur Verwaltung — und solange es offen ist, dunkelt die Karte alles ab,
// was nicht gespeichert ist.
//
// **Ein PERSISTENTES Blatt, kein modales.** Ein modales Blatt sperrt die
// Karte hinter sich; hier soll man die Karte schieben und sehen, was
// liegt. `Scaffold.showBottomSheet` lässt die Karte bedienbar und geht
// mit Zurück-Taste, Wisch oder dem X zu — und genau dann geht die
// Hervorhebung wieder aus (`closed`).
//
// **Stufe C: „Bereich zeichnen"** schaltet das Blatt auf den Entwurf
// (area_draw.dart): Stift und Radierer warten je auf EINEN Strich über
// der Karte, dazu „entlang meiner Trails" als Ausgangspunkt, Rückgängig,
// die Kachelzahl live und „Speichern …" ins bekannte Blatt mit Größe.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../map/online_map.dart';
import '../trails/trail_providers.dart';
import 'area_draw.dart';
import 'area_plan.dart';
import 'area_providers.dart';
import 'area_store.dart';

/// Öffnet das Blatt am [scaffold] der KARTE. [onSaveArea] öffnet
/// „Bereich speichern" — vom Karten-Screen gereicht, der Ausschnitt und
/// Trails kennt.
///
/// **Der Scaffold der Karte, nicht `Scaffold.of(context)`:** Aus dem
/// Build-Kontext des Karten-Screens fände das den Scaffold der
/// Reiter-Hülle — dessen Blatt läge ÜBER dem Navigator des Reiters und
/// damit über jedem modalen Blatt, das die Karte danach öffnet; das
/// modale „Bereich speichern" war dann nicht mehr antippbar (im Test
/// gefunden: der Tipp traf das Offline-Blatt).
/// [onSaveDrawn] öffnet dasselbe Blatt mit der gezeichneten Fläche.
void showOfflineMapsSheet(ScaffoldState scaffold, WidgetRef ref,
    {required VoidCallback onSaveArea, required void Function(AreaShape drawn) onSaveDrawn}) {
  final overlay = ref.read(offlineOverlayProvider.notifier);
  if (overlay.state) return; // schon offen
  overlay.state = true;
  final draft = ref.read(areaDraftProvider.notifier);
  final controller = scaffold.showBottomSheet(
    (_) => OfflineMapsSheet(onSaveArea: onSaveArea, onSaveDrawn: onSaveDrawn),
    showDragHandle: true,
    enableDrag: true,
  );
  controller.closed.whenComplete(() {
    overlay.state = false;
    // Der Entwurf bleibt (wer nachsieht, verliert nichts), das Werkzeug
    // nicht — ohne Blatt gibt es keinen Weg, es zurückzunehmen.
    draft.disarm();
  });
}

class OfflineMapsSheet extends ConsumerWidget {
  const OfflineMapsSheet({super.key, required this.onSaveArea, required this.onSaveDrawn});

  final VoidCallback onSaveArea;
  final void Function(AreaShape drawn) onSaveDrawn;

  static String _buildLabel(String build) => build.length == 8
      ? '${build.substring(6, 8)}.${build.substring(4, 6)}.${build.substring(0, 4)}'
      : build;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(areaDraftProvider);
    if (draft != null) return _DraftPanel(draft: draft, onSave: onSaveDrawn);
    final text = Theme.of(context).textTheme;
    final areas = ref.watch(storedAreasProvider).valueOrNull ?? const <StoredArea>[];
    final download = ref.watch(areaDownloadProvider);
    var total = 0;
    for (final a in areas) {
      total += a.bytes;
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(children: [
                Expanded(child: Text('Offline-Karten', style: text.titleLarge)),
                // Verwalten im Kopf, nicht als dritter Knopf unten: Drei
                // brachen auf zwei Zeilen um, und das Blatt lief über.
                IconButton(
                  key: const ValueKey('manage-areas'),
                  tooltip: 'Meine Bereiche verwalten',
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/profile/areas');
                  },
                  icon: const Icon(Icons.settings_outlined),
                ),
                IconButton(
                  key: const ValueKey('offline-maps-close'),
                  tooltip: 'Schließen',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            // Der Text scrollt mit der Liste, die Knöpfe bleiben stehen.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      areas.isEmpty
                          ? 'Noch kein Bereich gespeichert — ohne Empfang zeigt die Karte '
                              'nur die Übersicht. Solange dieses Blatt offen ist, ist alles '
                              'abgedunkelt, was nicht auf dem Gerät liegt.'
                          : 'Solange dieses Blatt offen ist, bleibt hell, was auf dem Gerät '
                              'liegt (${formatBytes(total)}); der Rest ist abgedunkelt. '
                              'Antippen zeigt einen Bereich auf der Karte.',
                      style: text.bodySmall,
                    ),
                  ),
                  if (download.phase == AreaDownloadPhase.running)
                    ListTile(
                      dense: true,
                      leading: const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      title: Text('„${download.name}" wird gespeichert …'),
                      subtitle: LinearProgressIndicator(value: download.progress?.fraction),
                    ),
                  for (final a in areas)
                    ListTile(
                      key: ValueKey('offline-area-${a.id}'),
                      dense: true,
                      leading: const Icon(Icons.map_outlined),
                      title: Text(a.name),
                      subtitle: Text(
                          '${formatBytes(a.bytes)} · ${a.tiles} Kacheln · Stand ${_buildLabel(a.build)}'),
                      onTap: () => ref.read(mapFocusAreaProvider.notifier).state = a,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('save-area-tile'),
                    onPressed: onSaveArea,
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: const Text('Bereich speichern'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('draw-area-tile'),
                    onPressed: () => ref.read(areaDraftProvider.notifier).start(),
                    icon: const Icon(Icons.draw_outlined),
                    label: const Text('Bereich zeichnen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Der Entwurf im Blatt: Werkzeuge, Kachelzahl, Verwerfen und Speichern.
class _DraftPanel extends ConsumerWidget {
  const _DraftPanel({required this.draft, required this.onSave});

  final AreaDraft draft;
  final void Function(AreaShape drawn) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final notifier = ref.read(areaDraftProvider.notifier);
    final maxZoom = ref.watch(mapManifestProvider).valueOrNull?.maxZoom ?? kAreaShapeZoom;
    final count = draft.isEmpty ? 0 : draft.shape.countTiles(maxZoom: maxZoom);
    final tooLarge = count > kAreaMaxTiles;
    final trails = ref.watch(trailsProvider).valueOrNull ?? const [];
    final String status;
    if (draft.tool != null) {
      status = draft.tool == AreaDrawTool.add
          ? 'Jetzt auf der Karte umfahren, was dazukommen soll.'
          : 'Jetzt auf der Karte umfahren oder überwischen, was weg soll.';
    } else if (draft.isEmpty) {
      status = 'Stift antippen, dann auf der Karte eine Fläche umfahren — jede Kachel, '
          'die sie berührt, kommt dazu. Zwischen zwei Strichen lässt sich die Karte verschieben.';
    } else {
      status = 'Grün ist gezeichnet, hell ist schon gespeichert. Weitere Striche '
          'kommen dazu, der Radierer nimmt weg.';
    }

    Widget tool(AreaDrawTool t, IconData icon, String tip, String key) {
      final selected = draft.tool == t;
      return IconButton(
        key: ValueKey(key),
        tooltip: tip,
        isSelected: selected,
        style: IconButton.styleFrom(
          backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
        onPressed: () => notifier.arm(t),
        icon: Icon(icon),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Bereich zeichnen', style: text.titleLarge)),
              IconButton(
                key: const ValueKey('offline-maps-close'),
                tooltip: 'Schließen',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(status, style: text.bodySmall),
            ),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                tool(AreaDrawTool.add, Icons.edit_outlined, 'Fläche dazunehmen', 'area-draw-add'),
                tool(AreaDrawTool.remove, Icons.auto_fix_normal_outlined, 'Fläche wegnehmen',
                    'area-draw-remove'),
                IconButton(
                  key: const ValueKey('area-draw-trails'),
                  tooltip: 'Kacheln entlang meiner Trails dazunehmen',
                  onPressed: trails.isEmpty
                      ? null
                      : () {
                          final along = AreaShape.alongLines([for (final t in trails) t.points]);
                          if (along != null && along.zoom == kAreaShapeZoom) notifier.addAll(along.keys);
                        },
                  icon: const Icon(Icons.route_outlined),
                ),
                IconButton(
                  key: const ValueKey('area-draw-undo'),
                  tooltip: 'Rückgängig',
                  onPressed: draft.history.isEmpty ? null : notifier.undo,
                  icon: const Icon(Icons.undo),
                ),
              ],
            ),
            Text(
              draft.isEmpty
                  ? 'Noch keine Kachel'
                  : tooLarge
                      ? '$count Kacheln — zu groß, erlaubt sind $kAreaMaxTiles. Mit dem Radierer '
                          'verkleinern oder zwei Bereiche speichern.'
                      : '$count Kacheln (Zoom $kAreaMinZoom–$maxZoom)',
              key: const ValueKey('area-draw-count'),
              style: tooLarge
                  ? text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)
                  : text.titleSmall,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('area-draw-discard'),
                    onPressed: notifier.discard,
                    child: const Text('Verwerfen'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('area-draw-save'),
                    onPressed: draft.isEmpty || tooLarge
                        ? null
                        : () {
                            notifier.disarm();
                            onSave(draft.shape);
                          },
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: const Text('Speichern …'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
