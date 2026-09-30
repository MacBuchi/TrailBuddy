import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../models/trail.dart';
import 'singletrail_scale.dart';
import 'trail_link.dart';
import 'trail_notes.dart';
import 'trail_providers.dart';
import 'trail_traits.dart';

/// Der eigene Beitrag zu einem Trail: Name, Schwierigkeit, Art,
/// Sichtbarkeit, Status. Nur für Trails, die man selbst belegt hat —
/// ohne Beleg gibt es keinen Beitrag (Konzept 3).
Future<void> showTrailDetailsDialog(
    BuildContext context, WidgetRef ref, Trail trail) async {
  final current = trail.myDetails ??
      TrailDetails(trailId: trail.id, userId: trail.myId);
  final result = await showDialog<({TrailDetails details, String? note})>(
    context: context,
    builder: (_) => _DetailsDialog(initial: current),
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final outcome = await ref
        .read(trailsProvider.notifier)
        .saveDetails(result.details, note: result.note);
    messenger.showSnackBar(SnackBar(
        content: Text(switch (outcome) {
      WriteOutcome.done => 'Beitrag gespeichert',
      WriteOutcome.doneStale => 'Beitrag gespeichert$staleAfterWriteHint',
      WriteOutcome.queued => kQueuedHint,
    })));
  } catch (e, st) {
    logError('Trail-Beitrag speichern', e, st);
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.initial});
  final TrailDetails initial;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _name = TextEditingController(text: widget.initial.name ?? '');
  late final _description =
      TextEditingController(text: widget.initial.description ?? '');
  late final _link = TextEditingController(text: widget.initial.link ?? '');
  String? _linkError;
  final _note = TextEditingController();
  late int? _grade = widget.initial.grade;
  late final Set<TrailTrait> _traits = {...widget.initial.traits};
  late TrailVisibility _visibility = widget.initial.visibility;
  late TrailStatus _status = widget.initial.status;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _link.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mein Beitrag'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: kTrailNameMaxLength,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            // Die Skala ist direkt beim Angeben erklärt: die Kurzfassung in
            // jeder Zeile der Auswahl, die ganze Fassung hinter dem „?".
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _grade,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Schwierigkeit (Singletrail-Skala)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Keine Angabe')),
                      for (final g in kSingletrailScale)
                        DropdownMenuItem<int?>(
                          value: g.value,
                          child: Text('${g.label} · ${g.short}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _grade = v),
                  ),
                ),
                SingletrailScaleButton(highlight: _grade),
              ],
            ),
            const SizedBox(height: 8),
            // Der Charakter (#72): Mehrfachwahl statt der früheren „Art".
            // Was jedes Merkmal heißt, steht direkt am Chip.
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Charakter', style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in TrailTrait.values)
                  TrailTraitChip(
                    t,
                    key: ValueKey('trait-${t.db}'),
                    selected: _traits.contains(t),
                    onSelected: (v) => setState(() => v ? _traits.add(t) : _traits.remove(t)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TrailStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Zustand'),
              items: [
                for (final s in TrailStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            // Der Status sagt WAS, der Hinweis WARUM (#7). Angeboten nur
            // beim Ändern; gespeichert als eigener Hinweis mit Datum.
            if (_status != widget.initial.status)
              TextField(
                key: const ValueKey('status-note'),
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
            DropdownButtonFormField<TrailVisibility>(
              initialValue: _visibility,
              decoration: const InputDecoration(labelText: 'Sichtbarkeit'),
              items: [
                for (final v in TrailVisibility.values)
                  DropdownMenuItem(value: v, child: Text(v.label)),
              ],
              onChanged: (v) => setState(() => _visibility = v ?? _visibility),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            // Link zur Quelle (#103): etwa die Seite des Vereins. Nur https,
            // Query und Fragment fallen weg (sanitizeLink).
            TextField(
              key: const ValueKey('details-link'),
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Link zur Quelle (optional)',
                hintText: 'z. B. die Seite des Vereins',
                errorText: _linkError,
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
          onPressed: () {
            final linkText = _link.text.trim();
            final link = sanitizeLink(linkText);
            if (linkText.isNotEmpty && link == null) {
              setState(() => _linkError = 'Nur https-Adressen, ohne Leerzeichen');
              return;
            }
            final statusChanged = _status != widget.initial.status;
            Navigator.of(context).pop((
              note: statusChanged ? _note.text.trim() : null,
              details: TrailDetails(
              trailId: widget.initial.trailId,
              userId: widget.initial.userId,
              username: widget.initial.username,
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              grade: _grade,
              traits: {..._traits},
              link: link,
              visibility: _visibility,
              status: _status,
              // Eine Statusmeldung trägt ihr Datum (Entscheidung 6); ein
              // unveränderter Status behält das alte.
              statusAt: statusChanged ? DateTime.now() : widget.initial.statusAt,
            )));
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
