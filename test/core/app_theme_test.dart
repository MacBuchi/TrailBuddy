// Die Palette hell und dunkel: Kontraste nach WCAG, das Theme je Modus,
// und die Einstellung „Erscheinungsbild" samt Merken.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final p in [AppColors.light, AppColors.dark]) {
    group('Palette ${p.brightness.name}', () {
      final grounds = {'Grund': p.ground, 'Fläche': p.surface, 'Fläche 2': p.surface2};
      final texts = {
        'Text': p.text,
        'gedämpft': p.muted,
        'Marke als Text': p.accentText,
        'Warnung als Text': p.warningText,
        'Buddy als Text': p.buddyText,
        'Hinweis als Text': p.noteText,
      };
      for (final g in grounds.entries) {
        for (final t in texts.entries) {
          test('${t.key} auf ${g.key} ≥ 4,5:1', () {
            expect(contrast(t.value, g.value), greaterThanOrEqualTo(4.5));
          });
        }
      }

      test('Symbole in Beziehungsfarbe auf Fläche ≥ 3:1', () {
        for (final c in [p.map.mine, p.map.buddy, p.map.warning]) {
          expect(contrast(c, p.surface), greaterThanOrEqualTo(3), reason: '$c');
        }
      });

      test('das Theme trägt die Palette, der Knopf ist Lime mit dunkler Schrift', () {
        final theme = buildAppTheme(p);
        expect(theme.brightness, p.brightness);
        expect(theme.extension<AppPalette>(), same(p));
        expect(theme.scaffoldBackgroundColor, p.ground);
        final style = theme.filledButtonTheme.style!;
        expect(style.backgroundColor!.resolve({}), AppColors.brand);
        expect(style.foregroundColor!.resolve({}), AppColors.onBrand);
        expect(theme.textTheme.titleLarge!.fontFamily, AppFonts.display);
        expect(theme.textTheme.bodyMedium!.fontFamily, AppFonts.body);
        // Der Titel der Leiste trägt seine Größe selbst — `textTheme`
        // bekommt sie erst in `Theme.of`, dieser Stil nie (bis 0.37.0:
        // 14 px).
        expect(theme.appBarTheme.titleTextStyle!.fontSize, 22);
        expect(theme.appBarTheme.titleTextStyle!.fontFamily, AppFonts.display);
      });
    });
  }

  test('Schrift auf dem Knopf ≥ 4,5:1', () {
    expect(contrast(AppColors.onBrand, AppColors.brand), greaterThanOrEqualTo(4.5));
  });

  test('die Karte ist hell: ihre Linien haben einen weißen Saum', () {
    expect(AppColors.mapLines, same(MapPalette.light));
    expect(AppColors.mapLines.halo, Colors.white);
    expect(AppColors.mapLines.haloBorderWidth * 2, 4, reason: 'Breite + 4');
    expect(MapPalette.dark.haloBorderWidth, 0);
  });

  test('ein unbekannter Wert gilt als System', () {
    expect(parseThemeMode(null), ThemeMode.system);
    expect(parseThemeMode('quatsch'), ThemeMode.system);
    expect(parseThemeMode('dark'), ThemeMode.dark);
  });

  testWidgets('Erscheinungsbild: aus der Einstellung gelesen, umgeschaltet, gemerkt',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    final settings = FakeSettings(appearance: 'dark');
    await pumpApp(tester, backend, settings: settings);

    Brightness brightness() =>
        Theme.of(tester.element(find.byType(NavigationBar))).brightness;
    expect(brightness(), Brightness.dark);

    await openTab(tester, 'Profil');
    await scrollTo(tester, find.byKey(const ValueKey('appearance')));
    await tester.tap(find.text('Hell'));
    await settle(tester);
    expect(brightness(), Brightness.light);
    expect(settings.appearance, 'light');

    await tester.tap(find.text('System'));
    await settle(tester);
    expect(settings.appearance, 'system');
  });
}
