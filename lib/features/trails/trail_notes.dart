import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../models/trail.dart';
import 'trail_providers.dart';
import 'trail_sheet.dart';

/// Hinweise zu einem Trail für Buddys (Issue #7): „Baum liegt quer nach
/// der zweiten Kehre". Kein Feedback an den Betreiber — das bleibt die
/// Glühbirne —, sondern eine Nachricht an meine Buddys, die den Trail
/// sehen. Schreiben darf jeder, der den Trail sieht; entfernen jeder, der
/// den Hinweis sieht (wer am Trail steht, sagt „erledigt"); bearbeiten
/// niemand: Das Alter soll stimmen.

/// Höchstlänge eines Hinweises, dieselbe wie im Check der Tabelle.
const kNoteMaxLength = 500;

/// Der Abschnitt im Trail-Blatt: die Hinweise, neueste zuerst, und der
/// Knopf zum Schreiben. [seenBefore] sind die Hinweise, die schon VOR dem
/// Öffnen gesehen waren — was jetzt neu ist, bleibt im Blatt getönt, auch
/// wenn es beim Öffnen als gesehen gemerkt wird.
class TrailNotesSection extends ConsumerWidget {
  const TrailNotesSection(
      {super.key, required this.trail, this.seenBefore = const {}});
  final Trail trail;
  final Set<String> seenBefore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = trail.notesShown();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Hinweise', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              key: const ValueKey('add-note'),
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Hinweis schreiben'),
            ),
          ],
        ),
        if (notes.isEmpty)
          Text('Noch keine. Ein Baum quer, ein neuer Drop? Deine Buddys sehen es hier.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        for (final n in notes)
          _NoteTile(
            note: n,
            mine: n.userId == trail.myId,
            fresh: trail.isFreshNote(n, seen: seenBefore),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    // Privat zählt nur, wenn ich selbst einen Beitrag habe — sonst gibt
    // es nichts, was ich verbergen könnte.
    final private = trail.myDetails?.visibility == TrailVisibility.private;
    final body = await showNoteDialog(context, private: private);
    if (body == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fresh = await ref.read(trailsProvider.notifier).addNote(trail.id, body);
      messenger.showSnackBar(SnackBar(
          content: Text('Hinweis gespeichert${fresh ? '' : staleAfterWriteHint}')));
    } catch (e, st) {
      logError('Hinweis speichern', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note, required this.mine, required this.fresh});
  final TrailNote note;
  final bool mine;
  final bool fresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final who = mine ? 'Du' : (note.username ?? 'Buddy');
    return Container(
      key: ValueKey('note-${note.id}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: fresh
            ? AppColors.noteYellow.withValues(alpha: 0.2)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.body),
                const SizedBox(height: 2),
                Text('$who · ${statusAge(note.createdAt)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (mine)
            IconButton(
              tooltip: 'Hinweis löschen',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            )
          else
            IconButton(
              tooltip: 'Erledigt — Hinweis entfernen',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => _delete(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(mine ? 'Hinweis löschen?' : 'Als erledigt entfernen?'),
        content: Text(mine
            ? '„${note.body}"'
            : '„${note.body}"\n\nDer Hinweis verschwindet für alle, die ihn '
                'sehen — auch für ${note.username ?? 'deinen Buddy'}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(mine ? 'Löschen' : 'Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fresh = await ref.read(trailsProvider.notifier).deleteNote(note.id);
      messenger.showSnackBar(SnackBar(
          content: Text('Hinweis entfernt${fresh ? '' : staleAfterWriteHint}')));
    } catch (e, st) {
      logError('Hinweis löschen', e, st);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

/// Wer den Hinweis sieht, in einem Satz — dieselbe Regel wie für den
/// Beitrag. Bei privatem Beitrag sagt er ehrlich, dass es niemand ist.
String noteAudience({required bool private}) => private
    ? 'Dein Beitrag steht auf „Nur für mich" — dann siehst nur du den Hinweis.'
    : 'Sehen deine Buddys, die diesen Trail auch sehen.';

/// Der Text eines neuen Hinweises, oder null bei Abbruch.
Future<String?> showNoteDialog(BuildContext context, {required bool private}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NoteDialog(private: private),
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.private});
  final bool private;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hinweis für Buddys'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('note-text'),
            controller: _text,
            autofocus: true,
            maxLines: 4,
            maxLength: kNoteMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'z. B. Baum liegt quer nach der zweiten Kehre',
            ),
            onChanged: (_) => setState(() {}),
          ),
          Text(noteAudience(private: widget.private),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_text.text.trim()),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
