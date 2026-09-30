// Bewegung (Design Turn 1p–1t): Die Keyframes rechnen pur, die Widgets
// laufen nur, wenn das System Bewegung will, und das Endbild ist immer
// vollständig — auch wenn nichts läuft.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';
import 'package:trailbuddy/core/widgets/motion.dart';
import 'package:trailbuddy/core/widgets/start_splash.dart';
import 'package:trailbuddy/core/widgets/trailbuddy_logo.dart';
import 'package:trailbuddy/features/friends/friends_screen.dart' show ConnectMergeMark, connectMergeAt;
import 'package:trailbuddy/features/map/map_screen.dart' show kRidePulseScale, ridePulseAt;

Widget _host(Widget child, {bool reduce = false}) => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(AppColors.dark),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );

int _tickers() => SchedulerBinding.instance.transientCallbackCount;

void main() {
  group('1q Loader', () {
    final length = logoPath().computeMetrics().first.length;

    test('das Stück läuft vorwärts über die Serpentine und bleibt auf ihr', () {
      double head(double t) => loaderSegments(t, length).map((s) => s.$1).reduce((a, b) => a > b ? a : b);
      expect(loaderSegments(0, length), [(0.0, kLoaderDash)], reason: 'Offset 300: das Stück am Anfang');
      expect(head(0.1), greaterThan(head(0.02)));
      for (var t = 0.0; t < 1; t += 0.01) {
        for (final (a, b) in loaderSegments(t, length)) {
          expect(a, greaterThanOrEqualTo(0));
          expect(b, lessThanOrEqualTo(length));
          expect(b - a, lessThanOrEqualTo(kLoaderDash + 1e-9));
        }
      }
    });

    testWidgets('läuft und sagt „Lädt …"', (tester) async {
      await tester.pumpWidget(_host(const CenteredTrailLoader()));
      expect(find.bySemanticsLabel('Lädt …'), findsOneWidget);
      expect(_tickers(), greaterThan(0));
    });

    testWidgets('mit reduzierter Bewegung steht er, sagt aber weiter „Lädt …"', (tester) async {
      await tester.pumpWidget(_host(const CenteredTrailLoader(), reduce: true));
      await tester.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel('Lädt …'), findsOneWidget);
      expect(_tickers(), 0);
    });
  });

  group('1r Fahrt läuft', () {
    test('der Ring wächst vom Punkt auf das 3,2-Fache und blendet von 0,7 aus', () {
      expect(ridePulseAt(0), (scale: 1.0, opacity: 0.7));
      final end = ridePulseAt(1);
      expect(end.scale, closeTo(kRidePulseScale, 1e-9));
      expect(end.opacity, closeTo(0, 1e-9));
      expect(ridePulseAt(0.5).scale, greaterThan(1));
    });
  });

  group('1t Neuer Hinweis', () {
    test('der Schein atmet von 2 auf 6 px, außen von 0 auf 14 px', () {
      expect(glowAt(0), (inner: 2.0, outer: 0.0));
      expect(glowAt(1), (inner: 6.0, outer: 14.0));
    });

    testWidgets('mit reduzierter Bewegung ein ruhiger Schein, kein Takt', (tester) async {
      await tester.pumpWidget(_host(
          const BreathingGlow(color: Colors.yellow, radius: 14, child: SizedBox(width: 50, height: 20)),
          reduce: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('breathing-glow')), findsOneWidget);
      expect(_tickers(), 0);
    });
  });

  group('1s Buddy verbunden', () {
    test('erst auseinander, dann eine Spur, dann der Punkt', () {
      expect(connectMergeAt(0), (apart: 1.0, dot: 0.0));
      expect(connectMergeAt(0.15).apart, 1);
      expect(connectMergeAt(0.55).apart, closeTo(0, 1e-9));
      expect(connectMergeAt(0.55).dot, 0, reason: 'der Punkt kommt NACH dem Zusammenlaufen');
      expect(connectMergeAt(0.75).dot, closeTo(1.25, 1e-5));
      expect(connectMergeAt(1).apart, 0);
      expect(connectMergeAt(1).dot, closeTo(1, 1e-5));
    });

    testWidgets('läuft einmal und hört auf', (tester) async {
      await tester.pumpWidget(_host(const ConnectMergeMark()));
      expect(_tickers(), greaterThan(0));
      await tester.pump(ConnectMergeMark.duration + const Duration(milliseconds: 100));
      expect(_tickers(), 0);
    });
  });

  group('1p Splash', () {
    test('das Endbild ist vollständig: Linie ganz, Endstriche da, Wortmarke da', () {
      final end = splashAt(1);
      expect(end.line, closeTo(1, 1e-5));
      expect(end.lineOpacity, 1);
      expect(end.tail, closeTo(1, 1e-5));
      expect(end.word, closeTo(1, 1e-5));
      final start = splashAt(0);
      expect((start.line, start.tail, start.word), (0.0, 0.0, 0.0));
      expect(splashAt(0.6).line, closeTo(1, 1e-5), reason: 'die Linie ist bei 60 % fertig');
      expect(splashAt(0.55).tail, 0, reason: 'die Endstriche warten auf die Linie');
      expect(splashAt(0.65).tail, inExclusiveRange(0, 1), reason: 'und wachsen dann');
      expect(splashAt(0.8).tail, closeTo(1, 1e-5), reason: 'stehen bei 80 %');
    });

    // Das Kind trägt KEINEN GlobalKey (anders als der Navigator unter
    // MaterialApp.home): Nur so zeigt der Test, dass der Splash die App
    // darunter nicht umhängt — ein GlobalKey rettete den Zustand sonst.
    Widget app({bool enabled = true, bool reduce = false}) => ProviderScope(
          overrides: [startSplashEnabledProvider.overrideWithValue(enabled)],
          child: MaterialApp(
            theme: buildAppTheme(AppColors.dark),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
                child: const StartSplash(child: _Counter()),
              ),
            ),
          ),
        );
    final splash = find.byKey(const ValueKey('start-splash'));

    testWidgets('liegt einmal über der App, die darunter schon läuft, und geht wieder',
        (tester) async {
      await tester.pumpWidget(app());
      expect(splash, findsOneWidget);
      expect(find.bySemanticsLabel('TrailBuddy'), findsWidgets);
      // Die App darunter ist schon gebaut und hat ihren Zustand.
      tester.state<_CounterState>(find.byType(_Counter)).bump();
      // Bildweise weiter, bis Zeichnen (1,2 s) und Ausblenden (0,25 s)
      // durch sind — jede Animation beginnt erst im Bild nach ihrem Start.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(splash, findsOneWidget, reason: 'nach 1 s läuft er noch');
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(splash, findsNothing);
      expect(tester.state<_CounterState>(find.byType(_Counter)).count, 1, reason: 'derselbe Zustand — nichts neu eingehängt');
      expect(_tickers(), 0);
    });

    testWidgets('die Wortmarke hat einen echten Textstil, auch über dem Navigator',
        (tester) async {
      // Wie in app.dart: im Builder, also ohne Material der Seite darüber.
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(AppColors.dark),
          builder: (context, child) => StartSplash(child: child!),
          home: const _Counter(),
        ),
      ));
      await tester.pump(kSplashDuration);
      final word = find.byType(TrailBuddyWordmark);
      expect(word, findsOneWidget);
      final style = DefaultTextStyle.of(tester.element(word)).style;
      expect(style.debugLabel ?? '', isNot(contains('fallback')),
          reason: 'sonst gelb doppelt unterstrichen');
    });

    testWidgets('ein Tipp überspringt ihn', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(splash);
      await tester.pump(); // das Ausblenden beginnt im nächsten Bild
      await tester.pump(kSplashFade + const Duration(milliseconds: 50));
      expect(splash, findsNothing);
    });

    testWidgets('bei reduzierter Bewegung und im Test-Harness gibt es ihn nicht', (tester) async {
      await tester.pumpWidget(app(reduce: true));
      expect(splash, findsNothing);
      await tester.pumpWidget(Container());
      await tester.pumpWidget(app(enabled: false));
      expect(splash, findsNothing);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var count = 0;
  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('$count', textDirection: TextDirection.ltr);
}
