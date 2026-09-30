// Die Mini-Legende im Tour-Schritt „Farbe heißt Schwierigkeit" (#132).
//
// **Warum gezeichnet.** Die Trail-Linien zeichnet die Karten-Engine
// (MapLibre bzw. flutter_map), sie sind keine Widgets — die Hinweis-
// Maschine kann sie nicht aussparen. Also zeigt die Blase selbst, was eine
// Linie sagen kann, in denselben Farben und Mustern wie die Karte:
// `AppColors.mapGrades` (die Karte ist immer hell), `AppColors.mapLines`
// und die Strichmuster aus `grade_shield.dart`. Eine eigene Zahl gibt es
// hier nicht; ändert sich ein Muster dort, zieht die Legende mit.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../trails/grade_shield.dart';

/// Eine Probe: Farbe, Strich der Linie, Saum und Deckkraft.
typedef _Sample = ({
  String label,
  Color color,
  List<double>? dash,
  Color? border,
  List<double>? borderDash,
  double opacity,
});

_Sample _line(String label, Color color,
        {List<double>? dash, Color? border, List<double>? borderDash, double opacity = 1}) =>
    (label: label, color: color, dash: dash, border: border, borderDash: borderDash, opacity: opacity);

/// Die Proben, in der Reihenfolge der Kurzanleitung: Schwierigkeit, dann
/// Zustand, dann was UM die Linie liegt.
List<_Sample> _samples() {
  const g = AppColors.mapGrades;
  const m = AppColors.mapLines;
  return [
    _line('S0', g.s0),
    _line('S1', g.s1),
    _line('S2', g.s2),
    _line('S3', g.s3),
    _line('S4/S5', g.s3, borderDash: kHaloDashExpert),
    _line('ohne Grad', g.ungraded),
    _line('Uphill', g.uphill),
    _line('bröckelig', g.s1, dash: kLineDashWorn),
    _line('gestrichelt', g.s1, dash: kLineDashRough),
    _line('verblasst', g.s1, dash: kLineDashRough, opacity: 0.45),
    _line('gemeldet', g.s1, border: m.warning),
    _line('neuer Hinweis', g.s1, border: m.note),
    _line('offiziell', m.official, dash: const [6, 4]),
  ];
}

/// Die Legende: kleine Linienstücke mit Beschriftung, umbrechend.
///
/// Auf dem Landton der Karte, damit Saum und Farben so aussehen wie
/// dort — in der dunklen App stünde ein weißer Saum sonst auf Schwarz.
class TourLegend extends StatelessWidget {
  const TourLegend({super.key});

  /// Die Beschriftungen, offen für den Test: Die Legende soll dieselben
  /// Regeln nennen wie die Kurzanleitung.
  static List<String> get labels => [for (final s in _samples()) s.label];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.light.text);
    return Container(
      key: const ValueKey('tour-legend'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.mapBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          for (final s in _samples())
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(size: const Size(28, 12), painter: _SamplePainter(s)),
                const SizedBox(width: 4),
                Text(s.label, style: style),
              ],
            ),
        ],
      ),
    );
  }
}

class _SamplePainter extends CustomPainter {
  const _SamplePainter(this.sample);

  final _Sample sample;

  static const _width = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final a = Offset(2, y);
    final b = Offset(size.width - 2, y);
    // Erst der Saum (weiß, auf Wunsch gestrichelt), dann ein farbiger
    // Rand, dann die Linie — dieselbe Reihenfolge wie auf der Karte.
    _stroke(canvas, a, b, AppColors.mapLines.halo!, _width + 4, sample.borderDash);
    if (sample.border case final c?) _stroke(canvas, a, b, c, _width + 5, null);
    _stroke(canvas, a, b, sample.color.withValues(alpha: sample.opacity), _width, sample.dash);
  }

  void _stroke(Canvas canvas, Offset a, Offset b, Color color, double width, List<double>? dash) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    if (dash == null) {
      canvas.drawLine(a, b, paint);
      return;
    }
    // Muster in Vielfachen der Strichbreite, wie die Engines es zeichnen.
    var x = a.dx;
    var i = 0;
    while (x < b.dx) {
      final len = dash[i % dash.length] * _width / 3;
      if (i.isEven) canvas.drawLine(Offset(x, a.dy), Offset((x + len).clamp(a.dx, b.dx), a.dy), paint);
      x += len;
      i++;
    }
  }

  @override
  bool shouldRepaint(_SamplePainter old) => old.sample != sample;
}
