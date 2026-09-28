// Die eigene Position auf der Karte, und eine Karte, die sich nicht
// dreht. Gefragt wird nach dem Standort nur über „Meine Position".
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
  });

  final dot = find.byKey(const ValueKey('my-position'));

  MapCamera camera(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byType(PolylineLayer<String>)));

  testWidgets('die Karte dreht sich nicht', (tester) async {
    await pumpApp(tester, backend);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final flags = map.options.interactionOptions.flags;
    expect(flags & InteractiveFlag.rotate, 0);
    expect(flags & InteractiveFlag.pinchZoom, isNot(0));
    expect(flags & InteractiveFlag.drag, isNot(0));
  });

  testWidgets('ohne Berechtigung: kein Punkt, und beim Start wird nicht gefragt',
      (tester) async {
    final fix = FakePositionFix();
    await pumpApp(tester, backend, positionFix: fix);
    expect(dot, findsNothing);
    expect(fix.calls, 0);

    await tester.tap(find.byTooltip('Meine Position'));
    await settle(tester);
    expect(fix.calls, 1);
    expect(find.textContaining('Position nicht verfügbar'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('mit Position: Punkt auf der Karte, „Meine Position" zentriert',
      (tester) async {
    final here = fakePosition(47.2, 11.4);
    final fix = FakePositionFix(here);
    await pumpApp(tester, backend, position: here, positionFix: fix);
    await settle(tester);
    expect(dot, findsOneWidget);
    expect(fix.calls, 0, reason: 'der Punkt allein fragt nie');

    await tester.tap(find.byTooltip('Meine Position'));
    await settle(tester, frames: 12);
    final c = camera(tester);
    expect(c.center.latitude, closeTo(47.2, 1e-6));
    expect(c.center.longitude, closeTo(11.4, 1e-6));
    expect(c.zoom, 15);
  });
}
