// Das Logo (Design Turn 1b) steht zweimal: als Pfad in Dart für die App
// und in tool/brand_icons.py, das daraus alle App-Symbole erzeugt. Hier
// wird festgehalten, dass beide dieselbe Form meinen und die Symbole dort
// liegen, wo Android und das Web sie suchen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';
import 'package:trailbuddy/core/widgets/trailbuddy_logo.dart';

const _res = 'android/app/src/main/res';

void main() {
  final tool = File('tool/brand_icons.py').readAsStringSync();

  test('Dart und Generator zeichnen dieselbe Serpentine', () {
    expect(tool, contains('LOGO_PATH = "$kLogoSvgPath"'));
    expect(tool, contains('LOGO_STROKE = ${kLogoStroke.toInt()}'));
    expect(tool,
        contains('LOGO_DOT = (${kLogoDot.x.toInt()}, ${kLogoDot.y.toInt()}, ${kLogoDot.r.toInt()})'));
  });

  test('der nachgebaute Pfad hat die Ausdehnung des SVG-Pfads', () {
    // Abgetastet statt getBounds — das nähme die Kontrollpunkte der Bögen.
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final m in logoPath().computeMetrics()) {
      for (var d = 0.0; d <= m.length; d += 0.25) {
        final p = m.getTangentForOffset(d)!.position;
        minX = p.dx < minX ? p.dx : minX;
        maxX = p.dx > maxX ? p.dx : maxX;
        minY = p.dy < minY ? p.dy : minY;
        maxY = p.dy > maxY ? p.dy : maxY;
      }
    }
    // Rechte Kehre bis 62 + 13, linke bis 38 − 13; Ende bei (72, 72).
    expect(minX, closeTo(20, 0.1));
    expect(maxX, closeTo(75, 0.1));
    expect(minY, closeTo(20, 0.1));
    expect(maxY, closeTo(72, 0.1));
    final end = logoPath().computeMetrics().last;
    expect(end.getTangentForOffset(end.length)!.position, const Offset(72, 72));
  });

  test('Statusleisten-Symbol: weiß, nur Alpha, die Serpentine', () {
    final xml = File('$_res/drawable/ic_notification.xml').readAsStringSync();
    expect(xml, contains(kLogoSvgPath));
    final colors = RegExp(r'android:(?:fill|stroke)Color="(#[0-9A-Fa-f]+)"')
        .allMatches(xml)
        .map((m) => m.group(1))
        .toSet();
    expect(colors, {'#FFFFFFFF'});
  });

  test('adaptives App-Symbol: Lime-Grund, dunkles Zeichen, Themen-Variante', () {
    final adaptive = File('$_res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
    expect(adaptive, contains('@color/ic_launcher_background'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(adaptive, contains('@drawable/ic_launcher_monochrome'));
    final colors = File('$_res/values/colors.xml').readAsStringSync();
    expect(colors, contains('<color name="ic_launcher_background">#B6F04A</color>'));
    expect(AppColors.brand, const Color(0xFFB6F04A));
    final fg = File('$_res/drawable/ic_launcher_foreground.xml').readAsStringSync();
    expect(fg, contains(kLogoSvgPath));
    expect(fg, contains('#FF0E1411'));
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('$_res/mipmap-$d/ic_launcher.png').existsSync(), isTrue, reason: d);
    }
  });

  testWidgets('Logo und Wortmarke lesen die Palette des Modus', (tester) async {
    for (final p in [AppColors.light, AppColors.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(p),
        home: const Column(children: [TrailBuddyLogo(), TrailBuddyWordmark()]),
      ));
      await tester.pumpAndSettle(); // das Theme blendet über
      final painter = tester
          .widget<CustomPaint>(find.descendant(
              of: find.byType(TrailBuddyLogo), matching: find.byType(CustomPaint)))
          .painter! as LogoPainter;
      expect(painter.color, p.brandMark);
      expect(painter.dotColor, p.text);
      expect(find.bySemanticsLabel('TrailBuddy'), findsNWidgets(2));
    }
  });
}
