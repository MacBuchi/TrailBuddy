import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../data/feedback_repository.dart';
import '../../data/providers.dart';

/// Die Glühbirne (PilzBuddy-Muster): ein Wunsch oder eine Fehlermeldung
/// an den Betreiber. Der Feedback-Bot macht daraus ein ÖFFENTLICHES
/// GitHub-Issue (`tool/feedback_bot.py`) — ohne Benutzernamen, aber mit
/// dem Text, wie er dasteht.
///
/// **Keine Trails hierhin.** Das Issue ist öffentlich, das Buddy-Netz
/// nicht; ein Trailname oder eine Ortsbeschreibung in einem Issue wäre
/// genau das, was das Community-Tor verhindern soll (Konzept 4). Der
/// Dialog sagt das vor dem Schreiben. Meldungen zu einem einzelnen Trail
/// bekommen einen eigenen Weg (Issue #7 für die Hinweise an Buddys).
Future<void> showFeedbackFlow(BuildContext context, WidgetRef ref) async {
  final input = await showDialog<FeedbackInput>(
    context: context,
    builder: (_) => const FeedbackDialog(),
  );
  if (input == null) return;
  try {
    // `await …future` und nicht `valueOrNull`: Beim ersten Lesen läuft
    // der Provider gerade erst an, die Version wäre sonst fast immer leer
    // (PilzBuddy #358). Ohne Version ist die Meldung trotzdem wertvoll.
    String? version;
    try {
      version = await ref.read(appVersionProvider.future);
    } catch (_) {
      // Kein Fehler des Nutzers und keiner, den jemand sucht.
    }
    await ref
        .read(feedbackRepositoryProvider)
        .submit(input.type, input.text, appVersion: version);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(input.type == FeedbackType.bug
          ? 'Danke für die Meldung — wir schauen uns das an!'
          : 'Danke für deinen Wunsch!'),
    ));
  } catch (e, st) {
    logError('Feedback senden', e, st);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// Was der Dialog zurückgibt.
class FeedbackInput {
  const FeedbackInput(this.type, this.text);
  final FeedbackType type;
  final String text;
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  FeedbackType _type = FeedbackType.feature;
  final _text = TextEditingController();

  bool get _canSend => _text.text.trim().length >= kFeedbackMinChars;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Wünsch dir was!'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<FeedbackType>(
              segments: const [
                ButtonSegment(
                    value: FeedbackType.feature,
                    icon: Icon(Icons.lightbulb_outline),
                    label: Text('Idee')),
                ButtonSegment(
                    value: FeedbackType.bug,
                    icon: Icon(Icons.bug_report_outlined),
                    label: Text('Fehler')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            Text(
              _type == FeedbackType.bug
                  ? 'Was funktioniert nicht? Beschreib kurz, was du gemacht '
                      'hast und was stattdessen passiert ist.'
                  : 'TrailBuddy ist noch ganz frisch — was fehlt dir, was '
                      'nervt, was wäre praktisch?',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText:
                    _type == FeedbackType.bug ? 'Was ist passiert?' : 'Dein Wunsch',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.public, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Wird als öffentlicher Eintrag auf GitHub angelegt — '
                    'ohne deinen Namen, aber mit diesem Text. Bitte keine '
                    'Trailnamen, Orte oder Wegbeschreibungen.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
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
          onPressed: _canSend
              ? () => Navigator.of(context)
                  .pop(FeedbackInput(_type, _text.text.trim()))
              : null,
          child: const Text('Senden'),
        ),
      ],
    );
  }
}
