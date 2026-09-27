import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/router_branches.dart';
import '../../models/trail.dart';
import 'trail_details_dialog.dart';
import 'trail_providers.dart';

/// Das Blatt zu einem Trail: Name (und die anderen Namen), Länge, S-Grad,
/// Status mit Alter, wer ihn belegt hat, und der eigene Beitrag.
Future<void> showTrailSheet(BuildContext context, Trail trail,
    {bool showOnMapButton = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TrailSheet(trailId: trail.id, showOnMapButton: showOnMapButton),
  );
}

String statusAge(DateTime? at, {DateTime? now}) {
  if (at == null) return 'ohne Datum';
  final days = (now ?? DateTime.now()).difference(at).inDays;
  if (days <= 0) return 'heute gemeldet';
  if (days == 1) return 'gestern gemeldet';
  if (days < 60) return 'gemeldet vor $days Tagen';
  final months = (days / 30.4).round();
  if (months < 24) return 'gemeldet vor $months Monaten';
  return 'gemeldet vor ${(days / 365).floor()} Jahren';
}

String formatLength(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

class _TrailSheet extends ConsumerWidget {
  const _TrailSheet({required this.trailId, required this.showOnMapButton});
  final String trailId;
  final bool showOnMapButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trail = ref.watch(trailByIdProvider(trailId));
    if (trail == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Dieser Trail ist nicht mehr sichtbar.'),
      );
    }
    final theme = Theme.of(context);
    final status = trail.latestStatus;
    final mine = trail.myDetails;
    final buddies = trail.buddyIds.length;
    final contributors = trail.contributionsOrdered
        .where((d) => d.userId != trail.myId)
        .map((d) => d.username ?? 'Buddy')
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trail.displayName, style: theme.textTheme.titleLarge),
            if (trail.otherNames.isNotEmpty)
              Text('auch: ${trail.otherNames.join(', ')}',
                  style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text(formatLength(trail.lengthM))),
                if (trail.grade != null) Chip(label: Text(gradeLabel(trail.grade!))),
                if (mine?.kind != null) Chip(label: Text(mine!.kind!.label)),
                if (trail.status.warns)
                  Chip(
                    avatar: const Icon(Icons.warning_amber, size: 18),
                    backgroundColor: AppColors.warningAmber.withValues(alpha: 0.25),
                    label: Text('${trail.status.label} · ${statusAge(status?.statusAt)}'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              trail.isOwn
                  ? (buddies == 0
                      ? 'Nur du hast diesen Trail belegt.'
                      : 'Du und $buddies ${buddies == 1 ? 'Buddy' : 'Buddys'} '
                          '(${contributors.join(', ')}).')
                  : 'Belegt von ${contributors.isEmpty ? '$buddies Buddys' : contributors.join(', ')} '
                      '— du bist ihn noch nicht gefahren.',
              style: theme.textTheme.bodyMedium,
            ),
            if (mine?.description != null && mine!.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(mine.description!),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (trail.isOwn)
                  FilledButton.tonalIcon(
                    onPressed: () => showTrailDetailsDialog(context, ref, trail),
                    icon: const Icon(Icons.edit),
                    label: const Text('Mein Beitrag'),
                  ),
                const Spacer(),
                if (showOnMapButton)
                  TextButton.icon(
                    onPressed: () {
                      // Erst der Reiter, dann der Wunsch (PilzBuddy #345).
                      Navigator.of(context).pop();
                      StatefulNavigationShell.maybeOf(context)
                          ?.goBranch(kMapBranchIndex);
                      ref.read(mapFocusTrailProvider.notifier).state = trail.id;
                    },
                    icon: const Icon(Icons.map),
                    label: const Text('Auf der Karte'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
