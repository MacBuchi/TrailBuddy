import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../models/trail.dart';
import 'trail_providers.dart';
import 'trail_sheet.dart';

/// Die Karte als Liste: erst die eigenen Trails, dann die, die nur Buddys
/// belegt haben. Antippen öffnet das Blatt; von dort geht es auf die Karte.
class TrailsScreen extends ConsumerWidget {
  const TrailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trailsAsync = ref.watch(trailsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trails'),
        actions: [
          IconButton(
            tooltip: 'GPX importieren',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => context.push('/profile/import'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(trailsProvider.future),
        child: trailsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(friendlyError(e)),
            ),
          ]),
          data: (trails) {
            if (trails.isEmpty) {
              return ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Noch keine Trails. Importiere deine GPX-Dateien (Symbol '
                    'oben rechts) oder verbinde dich mit Buddys.',
                  ),
                ),
              ]);
            }
            final seen = ref.watch(seenNotesProvider);
            final own = trails.where((t) => t.isOwn).toList();
            final buddies = trails.where((t) => !t.isOwn).toList();
            return ListView(
              children: [
                if (own.isNotEmpty) _Header('Meine Trails (${own.length})'),
                for (final t in own) _TrailTile(t, fresh: t.hasFreshNote(seen: seen)),
                if (buddies.isNotEmpty) _Header('Von Buddys (${buddies.length})'),
                for (final t in buddies) _TrailTile(t, fresh: t.hasFreshNote(seen: seen)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _TrailTile extends StatelessWidget {
  const _TrailTile(this.trail, {required this.fresh});
  final Trail trail;

  /// Neuer, noch nicht gesehener Hinweis eines Buddys (#7).
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      formatLength(trail.lengthM),
      if (trail.elevation != null) '↓ ${trail.elevation!.lossM.round()} Hm',
      if (trail.grade != null) gradeLabel(trail.grade!),
      if (trail.buddyIds.isNotEmpty)
        '${trail.buddyIds.length} ${trail.buddyIds.length == 1 ? 'Buddy' : 'Buddys'}',
    ];
    // Neuer Hinweis eines Buddys (#7): die Zeile getönt, ein Symbol am
    // Ende und das Wort dazu — Farbe allein wäre nicht für alle lesbar.
    return ListTile(
      tileColor: fresh ? AppColors.noteYellow.withValues(alpha: 0.18) : null,
      trailing: fresh
          ? const Icon(Icons.mark_chat_unread_outlined,
              semanticLabel: 'neuer Hinweis')
          : null,
      leading: Icon(
        trail.status.warns ? Icons.warning_amber : Icons.route,
        color: trail.status.warns
            ? AppColors.warningAmber
            : (trail.isOwn ? AppColors.trailGreen : AppColors.friendBlue),
      ),
      title: Text(trail.displayName),
      subtitle: Text([
        parts.join(' · '),
        if (trail.status.warns) trail.status.label,
        if (fresh) 'neuer Hinweis',
      ].join(' — ')),
      onTap: () => showTrailSheet(context, trail, showOnMapButton: true),
    );
  }
}
