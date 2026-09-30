import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_theme.dart';

/// Der Pfad des Logos (Design Turn 1b, Form seit Turn 1h: „Serpentine —
/// zwei ungleiche Kehren, der Schenkel läuft aus") in SVG-Schreibweise,
/// viewBox 100. Dieselbe Zeichenkette steht in `tool/brand_icons.py`, das
/// daraus alle App-Symbole erzeugt; `test/brand_icons_test.dart` hält
/// beide zusammen.
const kLogoSvgPath = 'M26 20H52a11 11 0 0 1 0 22H32a15 15 0 0 0 0 30H40';

/// Strichbreite in derselben viewBox.
const kLogoStroke = 14.0;

/// Die Endstriche: Der lange Schenkel löst sich in zwei kürzer und dünner
/// werdende Striche auf — „da geht's weiter", wie eine Linie, die aus dem
/// Kartenausschnitt läuft. Kein Punkt mehr: Zwei gleiche Kehren mit Punkt
/// lasen sich als „2." (Betreiber, 2026-09-30). Waagerechte Stücke
/// (x1…x2 bei y) mit eigener Strichbreite; sichtbar 19 und 12 Einheiten
/// lang, 4 Einheiten Luft zwischen den runden Enden.
const kLogoTail = [
  (x1: 55.5, x2: 65.5, y: 72.0, w: 9.0),
  (x1: 76.5, x2: 83.5, y: 72.0, w: 5.0),
];

/// Die Mitte der Form MIT Strich und Endstrichen (x 10…86, y 13…79) und
/// ihre längere Seite — die Maler legen die Form damit mittig in ihr
/// Quadrat.
const kLogoCenter = (x: 48.0, y: 46.0);
const kLogoExtent = 76.0;

/// Der Pfad aus [kLogoSvgPath], von Hand nachgebaut (Flutter liest kein
/// SVG): SVG-Bogen mit sweep 1 ist im Uhrzeigersinn, weil y nach unten
/// zeigt — in Flutter ebenso.
Path logoPath() => Path()
  ..moveTo(26, 20)
  ..lineTo(52, 20)
  ..arcToPoint(const Offset(52, 42), radius: const Radius.circular(11))
  ..lineTo(32, 42)
  ..arcToPoint(const Offset(32, 72),
      radius: const Radius.circular(15), clockwise: false)
  ..lineTo(40, 72);

/// Die Endstriche als Pfade, in der Reihenfolge von [kLogoTail].
List<Path> logoTailPaths() => [
      for (final t in kLogoTail)
        Path()
          ..moveTo(t.x1, t.y)
          ..lineTo(t.x2, t.y),
    ];

/// Rückt den Ursprung so, dass die Form mittig in der viewBox 100 liegt.
void centerLogo(Canvas canvas) =>
    canvas.translate(50 - kLogoCenter.x, 50 - kLogoCenter.y);

/// Zeichnet die Endstriche, [progress] 0…1: einer nach dem anderen wächst
/// aus seinem Anfang. Die Breiten werden mit [strokeScale] skaliert, wenn
/// die Linie nicht in Logo-Stärke gezeichnet wird (Loader: 12 statt 14).
void drawLogoTail(Canvas canvas, Color color,
    {double progress = 1, double strokeScale = 1}) {
  final n = kLogoTail.length;
  for (var i = 0; i < n; i++) {
    final local = (progress * n - i).clamp(0.0, 1.0);
    if (local <= 0) continue;
    final t = kLogoTail[i];
    canvas.drawLine(
      Offset(t.x1, t.y),
      Offset(t.x1 + (t.x2 - t.x1) * local, t.y),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = t.w * strokeScale
        ..strokeCap = StrokeCap.round,
    );
  }
}

/// Das Logo als Zeichen. Ohne Farben: die Marke dieses Modus
/// ([AppPalette.brandMark]) für die Linie, die Textfarbe für die
/// Endstriche — wie im Login-Entwurf (1g), wo die zweite Farbe das Ende
/// absetzt.
class TrailBuddyLogo extends StatelessWidget {
  const TrailBuddyLogo({super.key, this.size = 64, this.color, this.tailColor});

  final double size;
  final Color? color;
  final Color? tailColor;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      label: 'TrailBuddy',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: LogoPainter(
            color: color ?? p.brandMark,
            tailColor: tailColor ?? p.text,
          ),
        ),
      ),
    );
  }
}

class LogoPainter extends CustomPainter {
  const LogoPainter(
      {required this.color,
      required this.tailColor,
      this.progress = 1,
      this.tailProgress,
      this.opacity = 1});

  final Color color;
  final Color tailColor;

  /// Wie viel der Linie schon gezeichnet ist (0…1) — für den Splash
  /// (Turn 1p). Die Endstriche erscheinen erst am Ende.
  final double progress;

  /// Wie viel der Endstriche steht (0…1); gesetzt vom Splash, der sie
  /// nacheinander erscheinen lässt, während die Linie noch läuft. Ohne
  /// Wert: alle, sobald die Linie fertig ist.
  final double? tailProgress;

  /// Deckkraft der Linie — der Splash blendet sie am Anfang ein.
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    centerLogo(canvas);
    final stroke = Paint()
      ..color = color.withValues(alpha: color.a * opacity.clamp(0, 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = kLogoStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    var path = logoPath();
    if (progress < 1) {
      final metric = path.computeMetrics().first;
      path = metric.extractPath(0, metric.length * progress.clamp(0, 1));
    }
    if (progress > 0) canvas.drawPath(path, stroke);
    final tail = tailProgress ?? (progress >= 1 ? 1.0 : 0.0);
    if (tail > 0) drawLogoTail(canvas, tailColor, progress: tail);
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.color != color ||
      old.tailColor != tailColor ||
      old.progress != progress ||
      old.tailProgress != tailProgress ||
      old.opacity != opacity;
}

/// Die Wortmarke „TRAIL" + „BUDDY", die zweite Hälfte in der Marke.
class TrailBuddyWordmark extends StatelessWidget {
  const TrailBuddyWordmark({super.key, this.fontSize = 44});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final style = TextStyle(
      fontFamily: AppFonts.display,
      fontWeight: FontWeight.w800,
      fontSize: fontSize,
      height: 1,
      color: p.text,
    );
    return Semantics(
      label: 'TrailBuddy',
      excludeSemantics: true,
      child: Text.rich(TextSpan(style: style, children: [
        const TextSpan(text: 'TRAIL'),
        TextSpan(text: 'BUDDY', style: TextStyle(color: p.accentText)),
      ])),
    );
  }
}
