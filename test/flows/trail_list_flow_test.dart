// Suche, Filter und Sortierung im Reiter „Trails" (#66): fehlertolerant
// wie in PilzBuddy, und die Liste sagt, wenn sie rät.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    trails.seedTrail(anna.id, name: 'Roßkopf Süd', grade: 1);
    trails.seedTrail(bob.id, name: 'Hexentanz', lat: 48.1, grade: 4);
    trails.seedTrail(bob.id, name: 'Alter Weg', lat: 48.2);
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('trail-search')), text);
    await settle(tester);
  }

  String summary(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('trail-search-summary'))).textSpan!.toPlainText();

  testWidgets('Suche ohne Umlaut findet den Trail, ein Tippfehler wird als Vermutung gezeigt',
      (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('trail-search-summary')), findsNothing,
        reason: 'ohne Suche keine Zeile über der Liste');

    await type(tester, 'rosskopf sued');
    expect(find.text('Roßkopf Süd'), findsOneWidget);
    expect(find.text('Hexentanz'), findsNothing);
    expect(summary(tester), 'Ein Trail gefunden.');

    await type(tester, 'bob');
    expect(find.text('Hexentanz'), findsOneWidget, reason: 'gesucht wird auch nach dem Buddy');
    expect(find.text('Roßkopf Süd'), findsNothing);

    await type(tester, 'Hexntanz');
    expect(find.text('Hexentanz'), findsOneWidget);
    expect(summary(tester), 'Kein Trail heißt so. Meintest du …?');

    await tester.tap(find.byTooltip('Suche leeren'));
    await settle(tester);
    expect(find.text('Alter Weg'), findsOneWidget);
    expect(find.text('Roßkopf Süd'), findsOneWidget);
  });

  testWidgets('„bis S2" blendet Ungeschätztes aus und sagt es; Meine/Von Buddys', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('trail-filter-easy')));
    await settle(tester);
    expect(find.text('Roßkopf Süd'), findsOneWidget);
    expect(find.text('Hexentanz'), findsNothing, reason: 'S4');
    expect(find.text('Alter Weg'), findsNothing, reason: 'ohne Einschätzung');
    expect(summary(tester), 'Ein Trail gefunden. Ein Trail ohne Einschätzung ist nicht dabei.');

    await tester.tap(find.byKey(const ValueKey('trail-filter-easy')));
    await settle(tester);
    await tester.tap(find.text('Von Buddys').first);
    await settle(tester);
    expect(find.text('Roßkopf Süd'), findsNothing);
    expect(find.text('Hexentanz'), findsOneWidget);
    expect(find.text('Alter Weg'), findsOneWidget);
  });

  testWidgets('sortieren nach Name', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('trail-sort')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('trail-sort-name')));
    await settle(tester);
    final alter = tester.getTopLeft(find.text('Alter Weg')).dy;
    final hexe = tester.getTopLeft(find.text('Hexentanz')).dy;
    expect(alter, lessThan(hexe));
    expect(find.byTooltip('Sortieren: Name'), findsOneWidget);
  });
}
