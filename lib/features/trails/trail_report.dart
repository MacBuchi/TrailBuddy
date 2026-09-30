// Melden (#101, Rework Abschnitt 9): die Meldung („gesperrt" …) und der
// Zustand 1–5 zu einem Trail. Anders als der Beitrag darf das JEDER, der
// den Trail sieht — wer die Hausrunde nie aufgezeichnet hat, soll trotzdem
// „Baum liegt quer" melden können. Dann aber verblasst, „zu bestätigen".
//
// **Bestätigt** ist eine Angabe, wenn der Meldende den Trail gefahren hat
// oder vor Ort ist. „Vor Ort" prüft NUR das Gerät: ≤ [kOnSiteMaxM] zur
// Linie, mit der Position, die ein Tipp auf „Ich bin vor Ort" holt. Zum
// Server geht das Ja/Nein, nie die Position — und gespeichert wird dort
// nicht einmal das, nur das Ergebnis `confirmed`.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/geo.dart' show formatMeters;
import '../../core/line_geometry.dart';
import '../../core/read_after_write.dart';
import '../../models/trail.dart';
import '../friends/buddy_alias.dart';
import '../map/position_provider.dart';
import 'trail_condition.dart';
import 'trail_notes.dart';
import 'trail_providers.dart';

/// So nah muss man an der Linie sein, damit eine Meldung „vor Ort" gilt
/// (Betreiber, 2026-09-30).
const kOnSiteMaxM = 200.0;

/// Kürzester Abstand von [p] zur Linie [line] in Metern, null ohne Linie.
double? distanceToLineM(LatLng p, List<LatLng> line) {
  if (line.isEmpty) return null;
  final proj = FlatProjection(p.latitude);
  final q = proj.xy(p);
  final xy = proj.line(line);
  if (xy.length == 1) return q.distanceTo(xy.first);
  var best = double.infinity;
  for (var i = 1; i < xy.length; i++) {
    best = math.min(best, pointSegmentDistance(q, xy[i - 1], xy[i]));
  }
  return best;
}

/// „heute", „gestern", „vor 3 Tagen", „vor 4 Monaten" — das Alter einer
/// Meldung, ohne das Verb (das sagt die Zeile).
String reportAgeLabel(DateTime at, {DateTime? now}) {
  final days = (now ?? DateTime.now()).difference(at).inDays;
  if (days <= 0) return 'heute';
  if (days == 1) return 'gestern';
  if (days < 60) return 'vor $days Tagen';
  final months = (days / 30.4).round();
  if (months < 24) return 'vor $months Monaten';
  return 'vor ${(days / 365).floor()} Jahren';
}

/// Was eine Meldung sagt, in Worten: „Gesperrt" bzw. „Ausgefahren".
String reportValueLabel(TrailReport r) => r.kind == ReportKind.status
    ? r.status!.label
    : trailCondition(r.condition!).label;

/// Das Ergebnis des Melde-Dialogs.
typedef ReportInput = ({TrailStatus? status, int? condition, bool onSite, String? note});

/// „Melden" im Blatt: Dialog, dann schreiben (oder in den Ausgangskorb).
Future<void> reportTrail(BuildContext context, WidgetRef ref, Trail trail) async {
  final input = await showDialog<ReportInput>(
    context: context,
    builder: (_) => _ReportDialog(trail: trail),
  );
  if (input == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final outcome = await ref.read(trailsProvider.notifier).report(trail.id,
        status: input.status,
        condition: input.condition,
        onSite: input.onSite,
        note: input.note);
    messenger.showSnackBar(SnackBar(
        content: Text(switch (outcome) {
      WriteOutcome.done => 'Gemeldet',
      WriteOutcome.doneStale => 'Gemeldet$staleAfterWriteHint',
      WriteOutcome.queued => kQueuedHint,
    })));
  } catch (e, st) {
    logError('Trail melden', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog({required this.trail});
  final Trail trail;

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

enum _Site { unknown, checking, onSite, away, noFix }

class _ReportDialogState extends ConsumerState<_ReportDialog> {
  TrailStatus? _status;
  int? _condition;
  final _note = TextEditingController();
  var _site = _Site.unknown;
  double? _distance;

  late final bool _ridden = widget.trail.hasRidden(widget.trail.myId);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Ein Tipp holt EINEN Fix — die Nachfrage nach der Berechtigung kommt
  /// damit nur, wenn jemand darum bittet (Play: Prominent Disclosure).
  Future<void> _checkSite() async {
    setState(() => _site = _Site.checking);
    try {
      final fix = await ref.read(positionFixProvider)();
      if (!mounted) return;
      if (fix == null) {
        setState(() => _site = _Site.noFix);
        return;
      }
      final d = distanceToLineM(LatLng(fix.latitude, fix.longitude), widget.trail.points);
      setState(() {
        _distance = d;
        _site = d != null && d <= kOnSiteMaxM ? _Site.onSite : _Site.away;
      });
    } catch (e, st) {
      logError('Position zum Melden', e, st);
      if (mounted) setState(() => _site = _Site.noFix);
    }
  }

  String get _confirmationText {
    if (_ridden) return 'Du bist ihn gefahren — deine Meldung gilt als bestätigt.';
    return switch (_site) {
      _Site.onSite => 'Vor Ort (${formatMeters(_distance!)} zur Linie) — deine Meldung gilt als bestätigt.',
      _Site.away => '${formatMeters(_distance!)} entfernt — deine Meldung steht als „zu bestätigen" da, '
          'bis jemand vor Ort ist.',
      _Site.noFix => 'Keine Position — deine Meldung steht als „zu bestätigen" da.',
      _ => 'Nicht gefahren: Ohne Prüfung vor Ort steht deine Meldung als „zu bestätigen" da. '
          'Zum Server geht nur, OB du vor Ort bist, nie wo.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final chosen = _status != null || _condition != null;
    return AlertDialog(
      title: const Text('Melden'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Meldung', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in TrailStatus.values)
                  ChoiceChip(
                    key: ValueKey('report-status-${s.db}'),
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (on) => setState(() => _status = on ? s : null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Zustand', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in kTrailConditions)
                  ChoiceChip(
                    key: ValueKey('report-condition-${c.value}'),
                    label: Text(c.label),
                    tooltip: c.description,
                    selected: _condition == c.value,
                    onSelected: (on) => setState(() => _condition = on ? c.value : null),
                  ),
              ],
            ),
            // Der Hinweis sagt WARUM (#7) — angeboten, sobald etwas gewählt
            // ist, vor allem bei einer Warnung oder Zustand 1–2.
            if (chosen)
              TextField(
                key: const ValueKey('report-note'),
                controller: _note,
                maxLength: kNoteMaxLength,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Hinweis für Buddys (optional)',
                  hintText: _status == TrailStatus.open
                      ? 'z. B. Baum ist weggeräumt'
                      : 'z. B. Baum liegt quer nach der zweiten Kehre',
                ),
              ),
            const SizedBox(height: 8),
            Text(_confirmationText,
                key: const ValueKey('report-confirmation'),
                style: theme.textTheme.bodySmall?.copyWith(color: palette.muted)),
            if (!_ridden && _site != _Site.onSite)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('report-on-site'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: _site == _Site.checking ? null : _checkSite,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: Text(_site == _Site.checking ? 'Position wird geprüft …' : 'Ich bin vor Ort'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('report-submit'),
          onPressed: !chosen
              ? null
              : () {
                  final note = _note.text.trim();
                  Navigator.of(context).pop((
                    status: _status,
                    condition: _condition,
                    onSite: _site == _Site.onSite,
                    note: note.isEmpty ? null : note,
                  ));
                },
          child: const Text('Melden'),
        ),
      ],
    );
  }
}

/// Wer den Trail gemeldet hat, in einem Namen: „Du", der Alias, der
/// Benutzername.
String reporterName(TrailReport r, Trail trail, BuddyNames names) =>
    r.userId == trail.myId ? 'Du' : names.of(r.userId, r.username);

/// Der Verlauf im Blatt (Betreiber, 2026-09-30: „zur Nachvollziehbarkeit
/// … auch des Buddy Namen/Alias, der es gemeldet hat"): alles aus 90
/// Tagen, neueste zuerst, dazu was angezeigt wird. Unbestätigte stehen
/// verblasst da.
class TrailReportsSection extends ConsumerWidget {
  const TrailReportsSection({super.key, required this.trail});
  final Trail trail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = trail.reportsShown();
    if (shown.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final names = ref.watch(buddyNamesViewProvider);
    return Column(
      key: const ValueKey('trail-reports'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MELDUNGEN',
            style: theme.textTheme.labelSmall?.copyWith(
                color: palette.muted, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        for (final r in shown)
          Opacity(
            opacity: r.confirmed ? 1 : 0.6,
            child: ListTile(
              key: ValueKey('report-${r.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  r.kind == ReportKind.status
                      ? (r.status!.warns ? Icons.warning_amber : Icons.check_circle_outline)
                      : Icons.terrain,
                  size: 20),
              title: Text(
                  '${r.kind == ReportKind.status ? 'Meldung' : 'Zustand'}: ${reportValueLabel(r)}'),
              subtitle: Text([
                reporterName(r, trail, names),
                reportAgeLabel(r.reportedAt),
                if (r.pending) 'wartet auf Übertragung' else if (!r.confirmed) 'zu bestätigen',
              ].join(' · ')),
            ),
          ),
      ],
    );
  }
}

/// Die eigene Bewertung direkt im Blatt, wie [OwnGradePicker]: ein Tipp
/// auf einen Stern speichert, ein zweiter Tipp auf denselben nimmt sie
/// zurück. Nur für Trails, die man selbst belegt hat.
class OwnRatingPicker extends ConsumerStatefulWidget {
  const OwnRatingPicker({super.key, required this.trail});
  final Trail trail;

  @override
  ConsumerState<OwnRatingPicker> createState() => _OwnRatingPickerState();
}

class _OwnRatingPickerState extends ConsumerState<OwnRatingPicker> {
  bool _saving = false;

  Future<void> _set(int? rating) async {
    final trail = widget.trail;
    final current = trail.myDetails ?? TrailDetails(trailId: trail.id, userId: trail.myId);
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await ref.read(trailsProvider.notifier).saveDetails(
          rating == null ? current.copyWith(clearRating: true) : current.copyWith(rating: rating));
      switch (outcome) {
        case WriteOutcome.done:
          break;
        case WriteOutcome.doneStale:
          messenger.showSnackBar(const SnackBar(
              content: Text('Bewertung gespeichert$staleAfterWriteHint')));
        case WriteOutcome.queued:
          messenger.showSnackBar(const SnackBar(content: Text(kQueuedHint)));
      }
    } catch (e, st) {
      logError('Trail-Bewertung speichern', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.trail.myDetails?.rating;
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Deine Bewertung', style: Theme.of(context).textTheme.titleSmall),
        Row(
          children: [
            for (var i = kRatingMin; i <= kRatingMax; i++)
              IconButton(
                key: ValueKey('own-rating-$i'),
                tooltip: '$i von $kRatingMax Sternen',
                visualDensity: VisualDensity.compact,
                onPressed: _saving ? null : () => _set(mine == i ? null : i),
                icon: Icon(
                  mine != null && i <= mine ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: mine == null ? palette.muted.withValues(alpha: 0.5) : palette.accentText,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Die Einzelstimmen der Bewertung (Rework E8: „ein Tipp zeigt die
/// Einzelstimmen wie beim S-Grad").
Future<void> showRatingVotesSheet(BuildContext context, WidgetRef ref, Trail trail) {
  final names = ref.read(buddyNamesViewProvider);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final n = trail.ratingVotes.length;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bewertung', style: theme.textTheme.titleLarge),
              Text(n == 0 ? 'Noch keine Bewertung' : 'Median ${trail.rating} von $kRatingMax · $n×',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              for (final d in trail.ratingVotes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.userId == trail.myId ? 'Du' : names.of(d.userId, d.username)),
                  trailing: RatingStars(d.rating),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Die Einzelstimmen des Zustands: je Person die jüngste Angabe, mit
/// Alter und „zu bestätigen".
Future<void> showConditionVotesSheet(BuildContext context, WidgetRef ref, Trail trail) {
  final names = ref.read(buddyNamesViewProvider);
  final latest = <String, TrailReport>{};
  for (final r in trail.reports.where((r) => r.kind == ReportKind.condition)) {
    final prev = latest[r.userId];
    if (prev == null || r.reportedAt.isAfter(prev.reportedAt)) latest[r.userId] = r;
  }
  final votes = latest.values.toList()..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
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
              Text('Zustand', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final r in votes)
                Opacity(
                  opacity: r.confirmed ? 1 : 0.6,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(reporterName(r, trail, names)),
                    subtitle: Text([
                      trailCondition(r.condition!).label,
                      reportAgeLabel(r.reportedAt),
                      if (!r.confirmed) 'zu bestätigen',
                    ].join(' · ')),
                  ),
                ),
              for (final c in kTrailConditions)
                Text('${c.label}: ${c.description}', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      );
    },
  );
}
