// Die Farbe eines Trails ist seine Schwierigkeit (seit 0.42.0,
// Betreiber 2026-09-29) — auf der Karte, im Streifen der Liste und im
// Schild. Wem er gehört, sagt nur noch das Wort; eine Meldung liegt als
// Rand um die Linie.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
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
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    // Mein S1 und Bobs S1: gleiche Farbe, egal wem er gehört.
    trails.seedTrail(anna.id, name: 'Mein Blauer', grade: 1);
    trails.seedTrail(bob.id, name: 'Bobs Blauer', lat: 48.1, grade: 1);
    trails.seedTrail(bob.id, name: 'Schwarz', lat: 48.2, grade: 4);
    trails.seedTrail(bob.id, name: 'Gesperrt', lat: 48.3, grade: 0, status: TrailStatus.closed);
    trails.seedTrail(anna.id, name: 'Ohne', lat: 48.4);
    // Uphill: eigene Farbe statt der Stufe, das Schild trägt einen Pfeil.
    trails.seedTrail(bob.id, name: 'Auffahrt', lat: 48.5, grade: 2, traits: {TrailTrait.uphill});
  });

  MapViewPolyline lineOf(WidgetTester tester, String name) =>
      fakeMapLayers(tester).polylines.singleWhere((l) => l.hitValue is Trail && (l.hitValue as Trail).displayName == name);

  testWidgets('Karte: Linie in der Stufenfarbe, ab S4 gestrichelt, Meldung als Rand', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    const g = AppColors.mapGrades;

    expect(lineOf(tester, 'Mein Blauer').color, g.s1);
    expect(lineOf(tester, 'Bobs Blauer').color, g.s1, reason: 'Die Beziehung färbt nicht mehr');
    expect(lineOf(tester, 'Schwarz').color, g.s3);
    expect(lineOf(tester, 'Schwarz').dash, isNotNull);
    expect(lineOf(tester, 'Mein Blauer').dash, isNull);
    expect(lineOf(tester, 'Ohne').color, g.ungraded);
    final closed = lineOf(tester, 'Gesperrt');
    expect(closed.color, g.s0, reason: 'die Meldung übermalt die Schwierigkeit nicht');
    expect(closed.borderColor, AppColors.mapLines.warning);
    expect(lineOf(tester, 'Mein Blauer').borderColor, AppColors.mapLines.halo);
    // Der Name fließt entlang der Linie; die Linie ist fürs Bild geglättet,
    // Anfang und Ende bleiben die gespeicherten.
    final blue = lineOf(tester, 'Mein Blauer');
    expect(blue.label, 'Mein Blauer');
    final t = blue.hitValue! as Trail;
    expect(blue.points.length, greaterThan(t.points.length));
    expect(blue.points.first, t.points.first);
    expect(blue.points.last, t.points.last);
    expect(lineOf(tester, 'Auffahrt').color, g.uphill, reason: 'Uphill schlägt die Stufe (S2 wäre rot)');
  });

  testWidgets('Liste: Streifen in der Stufenfarbe des Modus, gleich für meinen und Bobs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);

    Future<Color> stripeOf(String name) async {
      await scrollTo(tester, find.text(name));
      final card = find.ancestor(of: find.text(name), matching: find.byType(Card));
      final stripe = find.descendant(of: card, matching: find.byKey(const ValueKey('trail-stripe')));
      return ((tester.widget<Container>(stripe).decoration as BoxDecoration).color)!;
    }

    const p = AppColors.light;
    expect(await stripeOf('Mein Blauer'), p.grade.s1);
    expect(await stripeOf('Bobs Blauer'), p.grade.s1);
    expect(await stripeOf('Gesperrt'), p.grade.s0);
    expect(await stripeOf('Ohne'), p.grade.ungraded);
    expect(await stripeOf('Auffahrt'), p.grade.uphill);
    expect(findLabel('Uphill, Schwierigkeit S2: größere Wurzeln, flache Stufen'), findsOneWidget);
  });
}
