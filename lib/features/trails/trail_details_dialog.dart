import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../models/trail.dart';
import 'trail_providers.dart';

/// Der eigene Beitrag zu einem Trail: Name, Schwierigkeit, Art,
/// Sichtbarkeit, Status. Nur für Trails, die man selbst belegt hat —
/// ohne Beleg gibt es keinen Beitrag (Konzept 3).
Future<void> showTrailDetailsDialog(
    BuildContext context, WidgetRef ref, Trail trail) async {
  final current = trail.myDetails ??
      TrailDetails(trailId: trail.id, userId: trail.myId);
  final result = await showDialog<TrailDetails>(
    context: context,
    builder: (_) => _DetailsDialog(initial: current),
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final fresh = await ref.read(trailsProvider.notifier).saveDetails(result);
    messenger.showSnackBar(SnackBar(
        content: Text('Beitrag gespeichert${fresh ? '' : staleAfterWriteHint}')));
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
  late int? _grade = widget.initial.grade;
  late TrailKind? _kind = widget.initial.kind;
  late TrailVisibility _visibility = widget.initial.visibility;
  late TrailStatus _status = widget.initial.status;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
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
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: _grade,
              decoration: const InputDecoration(labelText: 'Schwierigkeit (Singletrail-Skala)'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Keine Angabe')),
                for (var g = 0; g <= 5; g++)
                  DropdownMenuItem<int?>(value: g, child: Text(gradeLabel(g))),
              ],
              onChanged: (v) => setState(() => _grade = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TrailKind?>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Art'),
              items: [
                const DropdownMenuItem<TrailKind?>(value: null, child: Text('Keine Angabe')),
                for (final k in TrailKind.values)
                  DropdownMenuItem<TrailKind?>(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => _kind = v),
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
            final statusChanged = _status != widget.initial.status;
            Navigator.of(context).pop(TrailDetails(
              trailId: widget.initial.trailId,
              userId: widget.initial.userId,
              username: widget.initial.username,
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              grade: _grade,
              kind: _kind,
              visibility: _visibility,
              status: _status,
              // Eine Statusmeldung trägt ihr Datum (Entscheidung 6); ein
              // unveränderter Status behält das alte.
              statusAt: statusChanged ? DateTime.now() : widget.initial.statusAt,
            ));
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
