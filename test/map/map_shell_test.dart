// Die Hülle der Karte (Design Turn 3, Spezifikation 3e): rechts die
// Knöpfe, links die Leiste nur mit offenem Menü — Maße, Markierung des
// offenen Menüs, aktives Werkzeug und Speichern, hell und dunkel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_buttons.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/offline_areas/area_draw.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/offline_tool_rail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

/// Der IconButton zu einem Knopf — unter dem Schlüssel (am Rahmen) oder
/// über dem Tooltip (den der IconButton selbst einzieht).
Finder _button(Finder f) {
  final below = find.descendant(of: f, matching: find.byType(IconButton));
  return below.evaluate().isNotEmpty ? below.first : find.ancestor(of: f, matching: find.byType(IconButton)).first;
}

ButtonStyle _style(WidgetTester tester, Finder f) => tester.widget<IconButton>(_button(f)).style!;

ButtonStyle _railStyle(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey(key))).style!;

void main() {
  for (final (mode, palette) in [('light', AppColors.light), ('dark', AppColors.dark)]) {
    testWidgets('Knöpfe und Leiste ($mode)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'anna').id);
      await pumpApp(tester, backend, settings: FakeSettings(appearance: mode));
      await settle(tester);

      // Rechts: Idee, Ebenen, Position übereinander (44), unten die
      // Aufnahme (60), in dieser Reihenfolge.
      final idea = find.byTooltip('Idee oder Fehler melden');
      final layers = find.byKey(const ValueKey('layers-button'));
      final locate = find.byTooltip('Meine Position');
      final record = find.byKey(const ValueKey('ride-button'));
      for (final f in [idea, layers, locate]) {
        expect(tester.getSize(_button(f)), const Size.square(kMapButtonSize));
      }
      expect(tester.getSize(_button(record)), const Size.square(kRecordButtonSize));
      final ys = [idea, layers, locate, record].map((f) => tester.getCenter(f).dy).toList();
      expect(ys, orderedEquals([...ys]..sort()));
      expect(_style(tester, record).backgroundColor!.resolve({}), AppColors.brand);
      expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing);
      expect(tester.widget<MapView>(find.byType(MapView)).config.bottomLeftInset, 0);

      // Ebenen auf: links die Leiste, der Knopf rechts trägt die Marke.
      await tester.tap(layers);
      await settle(tester);
      expect(_style(tester, layers).side!.resolve({})!.color, palette.brandMark);
      final rail = tester.getRect(find.byKey(const ValueKey('offline-tool-rail')));
      expect(rail.width, kRailWidth);
      expect(tester.getSize(find.byKey(const ValueKey('area-draw-add'))), const Size.square(kMapButtonSize));
      // Maßstab und Quelle rücken neben die Leiste.
      expect(tester.widget<MapView>(find.byType(MapView)).config.bottomLeftInset,
          greaterThanOrEqualTo(kRailWidth));

      // Nichts im Entwurf: Speichern ist aus, nicht Lime.
      expect(_railStyle(tester, 'area-draw-save').backgroundColor?.resolve({WidgetState.disabled}), isNot(AppColors.brand));

      // Ein Werkzeug scharf: helle Fläche (Gegenhelligkeit der Leiste)
      // und oben die Zeile, was der Strich tut.
      await tester.tap(find.byKey(const ValueKey('area-draw-add')));
      await settle(tester);
      expect(_railStyle(tester, 'area-draw-add').backgroundColor!.resolve({WidgetState.selected}), palette.text);
      expect(_railStyle(tester, 'area-draw-add').foregroundColor!.resolve({WidgetState.selected}), palette.ground);
      expect(find.byKey(const ValueKey('area-draw-hint')), findsOneWidget);

      // Etwas im Entwurf: Speichern wird Lime, der Zähler steht darunter.
      ProviderScope.containerOf(tester.element(find.byType(MapScreen)))
          .read(areaDraftProvider.notifier)
          .addAll(tilesInBounds(const AreaBounds(south: 48, west: 9, north: 48.01, east: 9.01))!);
      await settle(tester);
      expect(_railStyle(tester, 'area-draw-save').backgroundColor!.resolve({}), AppColors.brand);
      final save = tester.getRect(find.byKey(const ValueKey('area-draw-save')));
      final count = tester.getRect(find.byKey(const ValueKey('area-draw-count')));
      expect(count.top, greaterThanOrEqualTo(save.bottom));
      expect(count.top - save.bottom, lessThan(8));
      expect((tester.widget(find.byKey(const ValueKey('area-draw-count'))) as Text).data, startsWith('+'));
    });
  }
}
