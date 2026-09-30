// Bewegung (Design Turn 1p–1t, docs/design/README.md Abschnitt 9): die
// gemeinsamen Bausteine. Jede Animation ist aus, wenn das System es will
// — dann steht das Endbild da, nie ein halbes.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import 'trailbuddy_logo.dart';

/// „Animationen entfernen" (Android) bzw. „Bewegung reduzieren" im Browser.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Länge des Stücks, das beim Laden über die Serpentine läuft, und der
/// Abstand zum nächsten — in Einheiten der viewBox 100 wie im Entwurf
/// (`stroke-dasharray: 60 240`).
const kLoaderDash = 60.0;
const kLoaderGap = 240.0;

/// Die sichtbaren Stücke des Laufs zum Zeitpunkt [t] (0…1) auf einem Pfad
/// der Länge [length]: der Entwurf schiebt `stroke-dashoffset` linear von
/// 300 auf −300, das Stück läuft also einmal ganz hinein und hinaus.
/// Pur, damit ein Test ohne Pixel prüfen kann, dass es läuft.
List<(double, double)> loaderSegments(double t, double length) {
  const period = kLoaderDash + kLoaderGap;
  final start = -period + 2 * period * t;
  final out = <(double, double)>[];
  for (var k = -2; k <= 2; k++) {
    final a = math.max(0.0, start + k * period);
    final b = math.min(length, start + k * period + kLoaderDash);
    if (b > a) out.add((a, b));
  }
  return out;
}

/// Der Loader (1q): Die Serpentine des Logos als Spur, darauf läuft ein
/// Stück in der Marke; die Endstriche stehen in der Spurfarbe. Ersetzt
/// die ganzseitigen Kreisel; in Knöpfen bleibt der kleine Kreisel —
/// 16 px Serpentine liest niemand.
class TrailLoader extends StatefulWidget {
  const TrailLoader({super.key, this.size = 56});

  final double size;

  static const period = Duration(milliseconds: 1600);

  @override
  State<TrailLoader> createState() => _TrailLoaderState();
}

class _TrailLoaderState extends State<TrailLoader> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: TrailLoader.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller
        ..stop()
        // Still: das Stück mitten auf der Spur, nicht am Rand.
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      label: 'Lädt …',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _LoaderPainter(_controller, track: p.line, color: p.brandMark),
          ),
        ),
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  _LoaderPainter(this.animation, {required this.track, required this.color})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    centerLogo(canvas);
    const width = 12.0;
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = logoPath();
    canvas.drawPath(path, stroke(track));
    drawLogoTail(canvas, track, strokeScale: width / kLogoStroke);
    final metric = path.computeMetrics().first;
    for (final (a, b) in loaderSegments(animation.value, metric.length)) {
      canvas.drawPath(metric.extractPath(a, b), stroke(color));
    }
  }

  @override
  bool shouldRepaint(_LoaderPainter old) => old.track != track || old.color != color;
}

/// Der Loader mittig in der verfügbaren Fläche — der häufigste Fall.
class CenteredTrailLoader extends StatelessWidget {
  const CenteredTrailLoader({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: TrailLoader());
}

/// Schein des Leuchtrands bei [t] (0…1…0 über eine Periode, `ease-in-out`
/// wie im Entwurf): innen 2 → 6 px, außen 0 → 14 px (Design 1t).
({double inner, double outer}) glowAt(double t) {
  final e = Curves.easeInOut.transform(t.clamp(0, 1));
  return (inner: 2 + 4 * e, outer: 14 * e);
}

/// Der gelbe Leuchtrand atmet (1t) — um eine Karte mit neuem Hinweis,
/// nur solange er ungesehen ist (der Aufrufer entscheidet, ob er da ist).
/// Bei reduzierter Bewegung steht der ruhige, schwache Schein.
class BreathingGlow extends StatefulWidget {
  const BreathingGlow({super.key, required this.color, required this.radius, required this.child});

  final Color color;
  final double radius;
  final Widget child;

  static const period = Duration(milliseconds: 1800);

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow> with SingleTickerProviderStateMixin {
  // Eine Periode ist hin UND zurück: 0,9 s ein, 0,9 s aus.
  late final _controller = AnimationController(
      vsync: this, duration: BreathingGlow.period ~/ 2);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final g = glowAt(_controller.value);
          return DecoratedBox(
            key: const ValueKey('breathing-glow'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: [
                BoxShadow(color: widget.color, blurRadius: g.inner),
                if (g.outer > 0) BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: g.outer),
              ],
            ),
            child: child,
          );
        },
      );
}
