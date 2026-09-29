import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

/// Die Singletrail-Skala (STS), S0 bis S5: die in DACH übliche Angabe,
/// wie schwierig ein Trail FAHRTECHNISCH ist — bei guten Bedingungen,
/// nicht, wie anstrengend er ist. Die Texte sind eigene Kurzfassungen,
/// keine Zitate.
///
/// EINE Quelle für alle Stellen, die einen Grad zeigen oder abfragen:
/// Auswahl im Beitrag, Chips im Blatt, Erklärblatt. Zwei Fassungen der
/// Beschreibung wären zwei Meinungen darüber, was S2 heißt.
class SingletrailGrade {
  const SingletrailGrade(this.value, this.short, this.description);

  final int value;

  /// Ein paar Wörter für Auswahllisten: „S2 · größere Wurzeln, Stufen".
  final String short;

  /// Ein bis zwei Sätze für das Erklärblatt.
  final String description;

  String get label => 'S$value';
}

const kSingletrailScale = <SingletrailGrade>[
  SingletrailGrade(0, 'fester Boden, ohne Hindernisse',
      'Fester, griffiger Untergrund ohne Wurzeln oder Steine; flach bis '
          'mäßig steil, weite Kurven.'),
  SingletrailGrade(1, 'kleine Wurzeln und Steine',
      'Kleine Wurzeln und Steine, stellenweise loser Untergrund, etwas '
          'engere Kurven — ohne besondere Fahrtechnik fahrbar.'),
  SingletrailGrade(2, 'größere Wurzeln, flache Stufen',
      'Größere Wurzeln und Steine, flache Stufen und Absätze, engere '
          'Kurven, oft loser Boden. Braucht Übung im Gelände.'),
  SingletrailGrade(3, 'verblockt, hohe Stufen, enge Kehren',
      'Verblockt, hohe Stufen und Absätze, enge Kehren, rutschiger '
          'Untergrund, steile Stücke. Braucht sichere Fahrtechnik.'),
  SingletrailGrade(4, 'sehr steil, Spitzkehren',
      'Sehr steil und verblockt, Spitzkehren, die nur mit Umsetzen des '
          'Hinterrads gehen. Nur mit Trialtechnik.'),
  SingletrailGrade(5, 'extrem, kaum fahrbar',
      'Extrem steil und verblockt, mehrere Hindernisse hintereinander, '
          'kaum Anlauf- oder Bremsweg. Für sehr wenige fahrbar.'),
];

SingletrailGrade singletrailGrade(int value) =>
    kSingletrailScale.firstWhere((g) => g.value == value);

/// Das Erklärblatt. [highlight] hebt eine Stufe hervor (die, die gerade
/// gewählt ist oder gezeigt wird).
Future<void> showSingletrailScaleSheet(BuildContext context, {int? highlight}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SingletrailScaleSheet(highlight: highlight),
  );
}

class SingletrailScaleSheet extends StatelessWidget {
  const SingletrailScaleSheet({super.key, this.highlight});

  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Singletrail-Skala', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Wie schwierig ein Trail fahrtechnisch ist — bei guten '
              'Bedingungen. Nässe, Laub oder Schnee machen jeden Trail '
              'schwerer; Länge und Höhenmeter zählen hier nicht.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final g in kSingletrailScale)
              Container(
                key: ValueKey('sts-${g.value}'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: g.value == highlight
                      ? AppPalette.of(context).map.mine.withValues(alpha: 0.12)
                      : null,
                  border: Border.all(
                      color: g.value == highlight
                          ? AppPalette.of(context).map.mine
                          : theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(g.label,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(child: Text(g.description)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'In TrailBuddy schätzt jeder, der einen Trail gefahren ist, '
              'selbst ein. Angezeigt wird der Median deiner Buddys, bei '
              'Gleichstand der schwerere Grad, dazu die Spanne.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Der kleine Knopf „?", der das Erklärblatt öffnet — neben jeder Stelle,
/// an der man einen Grad angibt.
class SingletrailScaleButton extends StatelessWidget {
  const SingletrailScaleButton({super.key, this.highlight});

  final int? highlight;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Singletrail-Skala erklären',
        icon: const Icon(Icons.help_outline),
        onPressed: () => showSingletrailScaleSheet(context, highlight: highlight),
      );
}
