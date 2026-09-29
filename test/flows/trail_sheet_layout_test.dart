// Das Trail-Blatt nach Design 1i/4f (seit 0.39.0): Titel in Versalien,
// drei Kennzahl-Kacheln nebeneinander, ein neuer Hinweis gelb gerahmt,
// unten „Hinweis schreiben" (Lime) und „Karte".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('Kacheln, gerahmter Hinweis und die beiden Aktionen unten', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    final id = trails.seedTrail(bob.id, name: 'Rosskopf Süd', grade: 2, ele: [900, 700, 480]);
    trails.seedNote(bob.id, id, 'Baum liegt quer', at: DateTime.now());

    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    await tester.tap(find.text('Rosskopf Süd'));
    await settle(tester);

    expect(find.text('ROSSKOPF SÜD'), findsOneWidget);
    final tiles = [
      find.byKey(const ValueKey('metric-length')),
      find.byKey(const ValueKey('metric-elevation')),
      find.byKey(const ValueKey('grade-chip')),
    ];
    final xs = [for (final t in tiles) tester.getCenter(t).dx];
    expect(xs, orderedEquals([...xs]..sort()), reason: 'Länge, Höhe, S-Grad von links nach rechts');
    expect({for (final t in tiles) tester.getCenter(t).dy.round()}, hasLength(1),
        reason: 'in EINER Reihe');
    expect(findLabel('↓ 420 Hm · ↑ 0 Hm'), findsOneWidget);
    expect(findLabel('S2 · 1 Einschätzung'), findsOneWidget);

    final note = tester.widget<Container>(find.ancestor(
        of: find.text('Baum liegt quer'), matching: find.byWidgetPredicate((w) => w is Container && w.key != null)));
    final border = (note.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, AppColors.light.map.note, reason: 'neuer Hinweis: gelber Rahmen');

    final write = find.byKey(const ValueKey('add-note'));
    expect(tester.widget(write), isA<FilledButton>(), reason: 'die Hauptaktion in Lime');
    final map = find.byKey(const ValueKey('trail-show-on-map'));
    expect(tester.getCenter(write).dy, closeTo(tester.getCenter(map).dy, 1), reason: 'nebeneinander');
    expect(tester.getTopLeft(write).dy, greaterThan(tester.getBottomLeft(find.text('Baum liegt quer')).dy),
        reason: 'unter den Hinweisen');
  });
}
