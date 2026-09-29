// Der Splash (Design Turn 1p): Die Serpentine zeichnet sich, der Punkt
// springt, die Wortmarke steigt ein — einmal je App-Start, ~1,2 s.
//
// Er liegt ÜBER der App, statt vor ihr zu stehen: Anmeldung, Karte und
// Trails laden darunter schon, der Splash kostet also keine Wartezeit,
// die es ohne ihn nicht gäbe. Ein Tipp überspringt ihn, und bei
// reduzierter Bewegung gibt es ihn gar nicht — ein stehendes Logo vor der
// App wäre nur eine Pause.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_colors.dart';
import 'motion.dart';
import 'trailbuddy_logo.dart';

/// Ob der Splash beim Start läuft. Der Test-Harness schaltet ihn ab — er
/// läge sonst über jedem Flow-Test und schluckte die ersten Tipps.
final startSplashEnabledProvider = Provider<bool>((ref) => true);

/// Dauer der Animation selbst und des Ausblendens danach.
const kSplashDuration = Duration(milliseconds: 1200);
const kSplashFade = Duration(milliseconds: 250);

/// Stand des Splashs bei [t] (0…1), Keyframes aus dem Entwurf
/// (`tbDraw`, `tbDot`, `tbWord`). Pur, damit der Test ohne Pixel prüfen
/// kann, dass das Endbild vollständig ist.
({double line, double lineOpacity, double dot, double word}) splashAt(double t) {
  final x = t.clamp(0.0, 1.0);
  const draw = Cubic(0.6, 0, 0.2, 1);
  final line = draw.transform((x / 0.6).clamp(0.0, 1.0));
  final lineOpacity = (x / 0.1).clamp(0.0, 1.0);
  final double dot;
  if (x <= 0.55) {
    dot = 0;
  } else if (x <= 0.7) {
    dot = 1.3 * Curves.easeOut.transform(((x - 0.55) / 0.15).clamp(0.0, 1.0));
  } else {
    // Geklemmt: (1 − 0,7) / 0,3 ist in Gleitkomma 1,0000000000000002,
    // und die Kurve lehnt das ab (im Test gefunden).
    dot = 1.3 - 0.3 * Curves.easeOut.transform(((x - 0.7) / 0.3).clamp(0.0, 1.0));
  }
  final word = Curves.easeOut.transform(((x - 0.5) / 0.3).clamp(0.0, 1.0));
  return (line: line, lineOpacity: lineOpacity, dot: dot, word: word);
}

class StartSplash extends ConsumerStatefulWidget {
  const StartSplash({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StartSplash> createState() => _StartSplashState();
}

class _StartSplashState extends ConsumerState<StartSplash> with TickerProviderStateMixin {
  late final _draw = AnimationController(vsync: this, duration: kSplashDuration);
  late final _fade = AnimationController(vsync: this, duration: kSplashFade, value: 1);

  /// null: noch nicht entschieden (vor dem ersten Build); danach, ob er
  /// noch liegt.
  bool? _showing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_showing != null) return;
    _showing = ref.read(startSplashEnabledProvider) && !reduceMotion(context);
    if (_showing!) {
      _draw.forward().whenComplete(_dismiss);
    }
  }

  void _dismiss() {
    if (!mounted || _fade.isAnimating || _showing != true) return;
    _fade.reverse().whenComplete(() {
      if (mounted) setState(() => _showing = false);
    });
  }

  @override
  void dispose() {
    _draw.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    // Immer derselbe Stack: Fiele er nach dem Splash weg, hinge die App
    // um, und der Router verlöre seinen Zustand.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showing == true)
          FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            key: const ValueKey('start-splash'),
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: Semantics(
              label: 'TrailBuddy',
              // Material statt ColoredBox: Der Splash liegt im Builder der
              // App, ÜBER dem Navigator — ohne Material darüber zeichnet
              // Flutter Text mit dem Warnstil (gelb, doppelt unterstrichen).
              child: Material(
                color: p.ground,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _draw,
                    builder: (context, _) {
                      final s = splashAt(_draw.value);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 96,
                            child: CustomPaint(
                              painter: LogoPainter(
                                color: p.brandMark,
                                dotColor: p.text,
                                progress: s.line,
                                opacity: s.lineOpacity,
                                dotScale: s.dot,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Opacity(
                            opacity: s.word,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1 - s.word)),
                              child: const TrailBuddyWordmark(fontSize: 30),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
