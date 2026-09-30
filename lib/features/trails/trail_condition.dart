import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/trail.dart';

/// Der Zustand eines Trails (#101, Rework 3.2 und 9): 5 ist der beste
/// Wert, wie bei der Bewertung — dieselbe Richtung, sonst verwechselt man
/// sie.
///
/// Der Wortlaut BESCHREIBT den Zustand, nie eine Maßnahme: kein „Arbeiten
/// fällig", kein „braucht Pflege" (Konzept 7 schließt Bau-Features und
/// Aufrufe zu Arbeitseinsätzen aus). Unterhalb von 1 beginnt die Meldung
/// („gesperrt", „zerstört") — der Zustand beschreibt einen OFFENEN Trail.
///
/// EINE Quelle für jede Stelle, die einen Zustand zeigt oder abfragt.
class TrailConditionLevel {
  const TrailConditionLevel(this.value, this.label, this.description);

  final int value;

  /// Das Wort: „Ausgefahren".
  final String label;

  /// Ein Satz für Auswahl und Bildschirmleser.
  final String description;
}

const kTrailConditions = <TrailConditionLevel>[
  TrailConditionLevel(5, 'Top gepflegt', 'Sauber, griffig, alles an seinem Platz.'),
  TrailConditionLevel(4, 'Gut', 'Normale Spuren, nichts, das stört.'),
  TrailConditionLevel(3, 'Ausgefahren', 'Bremswellen, ausgewaschene Rinnen, lose Steine.'),
  TrailConditionLevel(2, 'Abgerockt', 'Wurzeln frei, Löcher, Wildwuchs.'),
  TrailConditionLevel(1, 'Kaum fahrbar', 'Nur mit Mühe fahrbar.'),
];

TrailConditionLevel trailCondition(int value) =>
    kTrailConditions.firstWhere((c) => c.value == value);

/// Die Sterne einer Bewertung: [value] volle von [kRatingMax]. [faded]
/// zeigt die verblassten Sterne eines eigenen, noch nicht bewerteten
/// Trails (Rework E4) — oder eines unbestätigten Werts.
class RatingStars extends StatelessWidget {
  const RatingStars(this.value, {super.key, this.size = 16, this.faded = false});

  final int? value;
  final double size;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final full = value ?? 0;
    final color = faded ? palette.muted.withValues(alpha: 0.5) : palette.accentText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= kRatingMax; i++)
          Icon(i <= full ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size, color: color),
      ],
    );
  }
}
