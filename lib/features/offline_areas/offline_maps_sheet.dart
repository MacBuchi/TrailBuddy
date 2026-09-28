// Das Blatt „Offline-Karten" (Stufe B; Betreiber, 2026-09-28: „die
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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
void showOfflineMapsSheet(ScaffoldState scaffold, WidgetRef ref, {required VoidCallback onSaveArea}) {
  final overlay = ref.read(offlineOverlayProvider.notifier);
  if (overlay.state) return; // schon offen
  overlay.state = true;
  final controller = scaffold.showBottomSheet(
    (_) => OfflineMapsSheet(onSaveArea: onSaveArea),
    showDragHandle: true,
    enableDrag: true,
  );
  controller.closed.whenComplete(() => overlay.state = false);
}

class OfflineMapsSheet extends ConsumerWidget {
  const OfflineMapsSheet({super.key, required this.onSaveArea});

  final VoidCallback onSaveArea;

  static String _buildLabel(String build) => build.length == 8
      ? '${build.substring(6, 8)}.${build.substring(4, 6)}.${build.substring(0, 4)}'
      : build;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                IconButton(
                  key: const ValueKey('offline-maps-close'),
                  tooltip: 'Schließen',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
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
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
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
                  TextButton.icon(
                    key: const ValueKey('manage-areas'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go('/profile/areas');
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Meine Bereiche verwalten'),
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
