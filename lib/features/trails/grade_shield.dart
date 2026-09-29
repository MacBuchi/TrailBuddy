// Der S-Grad als Form (Design Turn 4, Abschnitt 7): ein farbloses Schild
// mit Form und „S3". Die Form trägt die Stufe auch für den, der die Zahl
// nicht liest — wie die Pistenzeichen im Skigebiet:
//
//   S0 ○  S1 ●  S2 ■  S3 ◆  S4 ◆◆  S5 ◆◆▮
//
// Farblos, weil Farbe in TrailBuddy die Beziehung sagt (grün meiner,
// blau Buddy); ein rotes S2 läse sich als „gemeldet". Das Schild steht in
// der Gegenhelligkeit des Grunds — im Hellen dunkel mit heller Form, im
// Dunklen umgekehrt —, damit es in beiden Modi dieselbe Kraft hat.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../models/trail.dart';
import 'singletrail_scale.dart';

/// Das Schild zu einem Grad 0–5.
class GradeShield extends StatelessWidget {
  const GradeShield(this.grade, {super.key, this.fontSize = 12});

  final int grade;

  /// Schriftgröße von „S3"; die Form wächst mit.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final ink = palette.ground;
    final g = singletrailGrade(grade);
    return Semantics(
      label: 'Schwierigkeit ${g.label}: ${g.short}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.55, vertical: fontSize * 0.2),
        decoration: BoxDecoration(
          color: palette.text,
          borderRadius: BorderRadius.circular(fontSize * 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradeShape(grade, size: fontSize * 0.75, color: ink),
            SizedBox(width: fontSize * 0.35),
            Text(gradeLabel(grade),
                style: AppFonts.numbers(TextStyle(fontSize: fontSize, height: 1.2))
                    .copyWith(color: ink)),
          ],
        ),
      ),
    );
  }
}

/// Nur die Form eines Grads, ohne Schild — für Stellen, die ihren
/// eigenen Grund haben (Erklärblatt).
class GradeShape extends StatelessWidget {
  const GradeShape(this.grade, {super.key, required this.size, required this.color});

  final int grade;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(gradeShapeWidth(grade, size), size),
        painter: _GradeShapePainter(grade, color),
      );
}

/// Breite der Form bei Höhe [size]: eine Einheit, zwei Rauten bei S4,
/// dazu ein Balken bei S5.
double gradeShapeWidth(int grade, double size) => switch (grade) {
      4 => size * 2 + size * 0.15,
      5 => size * 2 + size * 0.15 + size * 0.2 + size * 0.3,
      _ => size,
    };

class _GradeShapePainter extends CustomPainter {
  _GradeShapePainter(this.grade, this.color);

  final int grade;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.height;
    final fill = Paint()..color = color;
    final center = Offset(u / 2, u / 2);
    Path diamond(double left) => Path()
      ..moveTo(left + u / 2, 0)
      ..lineTo(left + u, u / 2)
      ..lineTo(left + u / 2, u)
      ..lineTo(left, u / 2)
      ..close();
    switch (grade) {
      case 0:
        final w = u * 0.16;
        canvas.drawCircle(
            center,
            u / 2 - w / 2,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = w);
      case 1:
        canvas.drawCircle(center, u / 2, fill);
      case 2:
        // Etwas kleiner als die Einheit: Ein Quadrat mit voller Kante
        // wirkt neben dem Kreis zu schwer.
        final inset = u * 0.08;
        canvas.drawRect(Rect.fromLTRB(inset, inset, u - inset, u - inset), fill);
      case 3:
        canvas.drawPath(diamond(0), fill);
      default:
        canvas.drawPath(diamond(0), fill);
        canvas.drawPath(diamond(u + u * 0.15), fill);
        if (grade >= 5) {
          final left = u * 2 + u * 0.15 + u * 0.2;
          canvas.drawRect(Rect.fromLTWH(left, 0, u * 0.3, u), fill);
        }
    }
  }

  @override
  bool shouldRepaint(_GradeShapePainter old) => old.grade != grade || old.color != color;
}
