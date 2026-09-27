import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../core/router_branches.dart';
import '../../models/trail.dart';
import 'elevation_profile_chart.dart';
import 'singletrail_scale.dart';
import 'trail_elevation.dart';
import 'trail_geometry.dart';
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

/// „↓ 420 Hm · ↑ 35 Hm" — bergab zuerst, weil ein Trail bergab gefahren
/// wird. Dieselbe Zeile im Import-Blatt und im Trail-Blatt.
String formatElevation(({double gain, double loss}) el) =>
    '↓ ${el.loss.round()} Hm · ↑ ${el.gain.round()} Hm';

/// „Ø 14 % Gefälle" bzw. „Ø 3 % Steigung"; unter einem halben Prozent
/// „Ø eben" statt einer Null mit Vorzeichen.
String formatMeanGrade(double descentPct) {
  final v = descentPct.abs().round();
  if (v == 0) return 'Ø eben';
  return descentPct > 0 ? 'Ø $v % Gefälle' : 'Ø $v % Steigung';
}

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
    final elevation = trail.elevation;
    final contributors = trail.contributionsOrdered
        .where((d) => d.userId != trail.myId)
        .map((d) => d.username ?? 'Buddy')
        .toList();

    // Scrollbar, seit das Höhenprofil drinsteht: Auf einem kleinen oder
    // quer gehaltenen Telefon liefe das Blatt sonst unten über.
    return SafeArea(
      child: SingleChildScrollView(
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
                if (elevation != null) ...[
                  Chip(
                      label: Text(formatElevation(
                          (gain: elevation.gainM, loss: elevation.lossM)))),
                  Chip(label: Text(formatMeanGrade(elevation.meanDescentPct))),
                ],
                if (trail.grade != null)
                  ActionChip(
                    key: const ValueKey('grade-chip'),
                    label: Text(gradeSummary(trail)!),
                    onPressed: () => showGradeVotesSheet(context, trail),
                  ),
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
            if (elevation != null) ...[
              ElevationProfileChart(elevation),
              const SizedBox(height: 4),
              Text(_profileCaption(elevation), style: theme.textTheme.bodySmall),
            ] else
              Text('Keine Höhenangaben — die Datei hatte keine.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
            if (trail.isOwn) ...[
              const SizedBox(height: 12),
              OwnGradePicker(trail: trail),
            ],
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

String _profileCaption(ElevationProfile p) {
  final steepest = p.steepestDescentPct;
  final parts = <String>['In Trail-Richtung'];
  if (steepest != null && steepest > 0) {
    parts.add('steilstes Stück ${steepest.round()} % auf ${kSteepestWindowM.round()} m');
  }
  return parts.join(' · ');
}

/// „S2 · S1–S3 · 4 Einschätzungen" — Median, Spanne (nur wenn es eine
/// gibt) und wie viele es sind. Eine Einschätzung ist eine Meinung, vier
/// sind ein Bild; die Zahl sagt, welches von beiden man sieht.
String? gradeSummary(Trail trail) {
  final median = trail.grade;
  final range = trail.gradeRange;
  if (median == null || range == null) return null;
  final n = trail.gradeVotes.length;
  return [
    gradeLabel(median),
    if (range.min != range.max) '${gradeLabel(range.min)}–${gradeLabel(range.max)}',
    '$n ${n == 1 ? 'Einschätzung' : 'Einschätzungen'}',
  ].join(' · ');
}

/// Wer hat was gesagt — nur sichtbare Beiträge, also die eigenen und die
/// der Buddys (dieselbe Liste, aus der der Median kommt).
Future<void> showGradeVotesSheet(BuildContext context, Trail trail) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Schwierigkeit', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(gradeSummary(trail) ?? 'Noch keine Einschätzung',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              for (final d in trail.gradeVotes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    child: Text(gradeLabel(d.grade!)),
                  ),
                  title: Text(d.userId == trail.myId ? 'Du' : (d.username ?? 'Buddy')),
                  subtitle: Text(singletrailGrade(d.grade!).short),
                ),
              TextButton.icon(
                onPressed: () =>
                    showSingletrailScaleSheet(sheetContext, highlight: trail.grade),
                icon: const Icon(Icons.help_outline),
                label: const Text('Was bedeuten S0 bis S5?'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Die eigene Einschätzung direkt im Blatt: ein Tipp auf S0–S5 speichert,
/// ein zweiter Tipp auf dieselbe Stufe nimmt sie zurück. Nur für Trails,
/// die man selbst belegt hat — ohne Beleg kein Beitrag (Konzept 3).
class OwnGradePicker extends ConsumerStatefulWidget {
  const OwnGradePicker({super.key, required this.trail});
  final Trail trail;

  @override
  ConsumerState<OwnGradePicker> createState() => _OwnGradePickerState();
}

class _OwnGradePickerState extends ConsumerState<OwnGradePicker> {
  bool _saving = false;

  Future<void> _set(int? grade) async {
    final trail = widget.trail;
    final current = trail.myDetails ??
        TrailDetails(trailId: trail.id, userId: trail.myId);
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fresh = await ref.read(trailsProvider.notifier).saveDetails(
          grade == null ? current.copyWith(clearGrade: true) : current.copyWith(grade: grade));
      if (!fresh) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Einschätzung gespeichert$staleAfterWriteHint')));
      }
    } catch (e, st) {
      logError('Trail-Einschätzung speichern', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.trail.myDetails?.grade;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Deine Einschätzung', style: theme.textTheme.titleSmall),
            SingletrailScaleButton(highlight: mine),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final g in kSingletrailScale)
              ChoiceChip(
                key: ValueKey('own-grade-${g.value}'),
                label: Text(g.label),
                tooltip: g.short,
                selected: mine == g.value,
                onSelected: _saving
                    ? null
                    : (on) => _set(on ? g.value : null),
              ),
          ],
        ),
      ],
    );
  }
}
