// Bewegung (Design Turn 1p–1t, docs/design/README.md Abschnitt 9): die
// gemeinsamen Bausteine. Jede Animation ist aus, wenn das System es will
// — dann steht das Endbild da, nie ein halbes.
import 'package:flutter/material.dart';

import '../app_colors.dart';
import 'trailbuddy_logo.dart';

/// „Animationen entfernen" (Android) bzw. „Bewegung reduzieren" im Browser.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Länge des Läufers in Einheiten der Strecke (Logo C3): Er ist so breit
/// wie die Strecke an seiner Stelle und springt über die Lücken in die
/// Endstriche.
const kLoaderRun = 40.0;

/// Anteil eines Durchlaufs, in dem der Läufer unterwegs ist: 1,5 s von
/// 2 s, danach 0,5 s Pause.
const kLoaderMoving = 0.75;

/// Der sichtbare Abschnitt des Läufers bei [t] (0…1) auf einer Strecke
/// der Länge [total] (mit Endstrichen), oder null in der Pause. Er läuft
/// ganz hinein und ganz hinaus. Pur, damit ein Test ohne Pixel prüfen
/// kann, dass er läuft.
(double, double)? loaderRunAt(double t, double total) {
  if (t >= kLoaderMoving) return null;
  final head = (t / kLoaderMoving).clamp(0.0, 1.0) * (total + kLoaderRun);
  return (head - kLoaderRun, head);
}

/// Der Loader: das Logo als Spur, darauf läuft ein Stück in der Marke.
/// Ersetzt die ganzseitigen Kreisel; in Knöpfen bleibt der kleine Kreisel
/// — 16 px Serpentine liest niemand.
class TrailLoader extends StatefulWidget {
  const TrailLoader({super.key, this.size = 56});

  final double size;

  static const period = Duration(milliseconds: 2000);

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
        // Still: der Läufer mitten auf der Spur, nicht am Rand.
        ..value = kLoaderMoving / 2;
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
    final geo = LogoGeometry.forPixels(widget.size);
    return Semantics(
      label: 'Lädt …',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final run = loaderRunAt(_controller.value, geo.total);
              return CustomPaint(
                painter: LogoPainter(
                  geometry: geo,
                  color: p.brandMark,
                  track: p.line,
                  from: run?.$1 ?? 0,
                  to: run?.$2 ?? 0,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
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
