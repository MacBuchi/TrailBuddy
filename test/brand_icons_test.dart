// Das Logo (Design Turn 1b, Form seit 1h) steht zweimal: als Pfad in Dart
// für die App und in tool/brand_icons.py, das daraus alle App-Symbole
// erzeugt. Hier wird festgehalten, dass beide dieselbe Form meinen und die
// Symbole dort liegen, wo Android und das Web sie suchen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_theme.dart';
import 'package:trailbuddy/core/widgets/trailbuddy_logo.dart';

const _res = 'android/app/src/main/res';

/// Zahlen so, wie Python sie schreibt: `72` statt `72.0`, `55.5` bleibt.
String _py(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Die Hülle des Pfads mit Strich, abgetastet statt getBounds — das nähme
/// die Kontrollpunkte der Bögen.
({double minX, double maxX, double minY, double maxY}) _hull(Path path, double stroke) {
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final m in path.computeMetrics()) {
    for (var d = 0.0; d <= m.length; d += 0.25) {
      final p = m.getTangentForOffset(d)!.position;
      minX = p.dx < minX ? p.dx : minX;
      maxX = p.dx > maxX ? p.dx : maxX;
      minY = p.dy < minY ? p.dy : minY;
      maxY = p.dy > maxY ? p.dy : maxY;
    }
  }
  final h = stroke / 2;
  return (minX: minX - h, maxX: maxX + h, minY: minY - h, maxY: maxY + h);
}

void main() {
  final tool = File('tool/brand_icons.py').readAsStringSync();

  test('Dart und Generator zeichnen dieselbe Serpentine', () {
    expect(tool, contains('LOGO_PATH = "$kLogoSvgPath"'));
    expect(tool, contains('LOGO_STROKE = ${kLogoStroke.toInt()}'));
    final tail = kLogoTail
        .map((t) => '(${_py(t.x1)}, ${_py(t.x2)}, ${_py(t.y)}, ${_py(t.w)})')
        .join(', ');
    expect(tool, contains('LOGO_TAIL = ($tail)'));
    expect(tool, contains('LOGO_CENTER = (${_py(kLogoCenter.x)}, ${_py(kLogoCenter.y)})'));
    expect(tool, contains('LOGO_EXTENT = ${_py(kLogoExtent)}'));
    expect(tool, isNot(contains('LOGO_DOT')), reason: 'kein Punkt mehr (Turn 1h)');
  });

  test('der nachgebaute Pfad hat die Ausdehnung des SVG-Pfads', () {
    final h = _hull(logoPath(), 0);
    // Rechte Kehre bis 52 + 11, linke bis 32 − 15; Ende bei (40, 72).
    expect(h.minX, closeTo(17, 0.1));
    expect(h.maxX, closeTo(63, 0.1));
    expect(h.minY, closeTo(20, 0.1));
    expect(h.maxY, closeTo(72, 0.1));
    final end = logoPath().computeMetrics().last;
    expect(end.getTangentForOffset(end.length)!.position, const Offset(40, 72));
  });

  test('Mitte und Ausdehnung sind die der Form MIT Strich und Endstrichen', () {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    final parts = [(logoPath(), kLogoStroke)];
    for (var i = 0; i < kLogoTail.length; i++) {
      parts.add((logoTailPaths()[i], kLogoTail[i].w));
    }
    for (final (path, stroke) in parts) {
      final h = _hull(path, stroke);
      minX = h.minX < minX ? h.minX : minX;
      maxX = h.maxX > maxX ? h.maxX : maxX;
      minY = h.minY < minY ? h.minY : minY;
      maxY = h.maxY > maxY ? h.maxY : maxY;
    }
    expect(minX, closeTo(10, 0.01));
    expect(maxX, closeTo(86, 0.01));
    expect(minY, closeTo(13, 0.01));
    expect(maxY, closeTo(79, 0.01));
    expect(kLogoCenter.x, closeTo((minX + maxX) / 2, 0.01));
    expect(kLogoCenter.y, closeTo((minY + maxY) / 2, 0.01));
    expect(kLogoExtent, closeTo(maxX - minX, 0.01));
    // Die Endstriche liegen rechts vom Ende der Linie, mit Luft dazwischen
    // (Linie bis 40 + 7, erster Strich ab 55,5 − 4,5): Sie sind Striche,
    // kein angeklebter Punkt.
    expect(kLogoTail.first.x1 - kLogoTail.first.w / 2, greaterThan(47 + 3));
  });

  test('Statusleisten-Symbol: weiß, nur Alpha, die Serpentine mit Endstrichen', () {
    final xml = File('$_res/drawable/ic_notification.xml').readAsStringSync();
    expect(xml, contains(kLogoSvgPath));
    expect('<path'.allMatches(xml).length, 1 + kLogoTail.length);
    expect(xml, isNot(contains('fillColor')));
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
      expect(painter.tailColor, p.text);
      expect(find.bySemanticsLabel('TrailBuddy'), findsNWidgets(2));
    }
  });
}
