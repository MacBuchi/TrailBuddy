import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_theme.dart';

/// Der Pfad des Logos (Design Turn 1b, „Serpentine — zwei Kehren, ein
/// Ziel") in SVG-Schreibweise, viewBox 100. Dieselbe Zeichenkette steht in
/// `tool/brand_icons.py`, das daraus alle App-Symbole erzeugt;
/// `test/brand_icons_test.dart` hält beide zusammen.
const kLogoSvgPath = 'M20 20H62a13 13 0 0 1 0 26H38a13 13 0 0 0 0 26H72';

/// Strichbreite und Endpunkt in derselben viewBox.
const kLogoStroke = 14.0;
const kLogoDot = (x: 82.0, y: 72.0, r: 7.0);

/// Der Pfad aus [kLogoSvgPath], von Hand nachgebaut (Flutter liest kein
/// SVG): SVG-Bogen mit sweep 1 ist im Uhrzeigersinn, weil y nach unten
/// zeigt — in Flutter ebenso.
Path logoPath() => Path()
  ..moveTo(20, 20)
  ..lineTo(62, 20)
  ..arcToPoint(const Offset(62, 46), radius: const Radius.circular(13))
  ..lineTo(38, 46)
  ..arcToPoint(const Offset(38, 72),
      radius: const Radius.circular(13), clockwise: false)
  ..lineTo(72, 72);

/// Das Logo als Zeichen. Ohne Farben: die Marke dieses Modus
/// ([AppPalette.brandMark]) für den Strich, die Textfarbe für den Punkt —
/// wie im Login-Entwurf (1g), wo der helle Punkt das Ziel absetzt.
class TrailBuddyLogo extends StatelessWidget {
  const TrailBuddyLogo({super.key, this.size = 64, this.color, this.dotColor});

  final double size;
  final Color? color;
  final Color? dotColor;

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
            dotColor: dotColor ?? p.text,
          ),
        ),
      ),
    );
  }
}

class LogoPainter extends CustomPainter {
  const LogoPainter({required this.color, required this.dotColor, this.progress = 1});

  final Color color;
  final Color dotColor;

  /// Wie viel der Linie schon gezeichnet ist (0…1) — für den Splash
  /// (Turn 1p). Der Punkt erscheint erst am Ende.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = kLogoStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    var path = logoPath();
    if (progress < 1) {
      final metric = path.computeMetrics().first;
      path = metric.extractPath(0, metric.length * progress.clamp(0, 1));
    }
    canvas.drawPath(path, stroke);
    if (progress >= 1) {
      canvas.drawCircle(
          const Offset(82, 72), kLogoDot.r, Paint()..color = dotColor);
    }
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.color != color || old.dotColor != dotColor || old.progress != progress;
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
