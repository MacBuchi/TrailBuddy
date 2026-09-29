// Hinweise für Buddys (Issue #7): „Baum liegt quer". Schreiben darf, wer
// den Trail sieht; sehen die direkten Buddys, die ihn auch sehen;
// entfernen, wer ihn sieht („erledigt"). Ein neuer Hinweis eines Buddys
// hebt den Trail in der Liste hervor, bis man ihn im Blatt gesehen hat,
// und beim Ändern des Status lässt sich einer gleich mitgeben.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late String annaId, bobId, carlaId;
  late String roots, bobsFlow;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    final bob = backend.addUser(username: 'bob');
    final carla = backend.addUser(username: 'carla');
    backend.addFriendship(anna.id, bob.id);
    backend.signInAs(anna.id);
    annaId = anna.id;
    bobId = bob.id;
    carlaId = carla.id;
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.usernames[bob.id] = 'bob';
    trails.usernames[carla.id] = 'carla';
    roots = trails.seedTrail(bob.id, name: 'Roots');
    trails.seedTrail(anna.id, trailId: roots);
    bobsFlow = trails.seedTrail(bob.id, name: 'Bobs Flow', lat: 48.1);
  });

  Future<void> openList(WidgetTester tester) async {
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
  }

  Future<void> openTrail(WidgetTester tester, String name) async {
    await openList(tester);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  testWidgets('neuer Hinweis eines Buddys: hervorgehoben, bis man ihn gesehen hat',
      (tester) async {
    trails.seedNote(bobId, bobsFlow, 'Baum liegt quer nach der zweiten Kehre',
        at: DateTime.now().subtract(const Duration(days: 1)));
    trails.seedNote(bobId, roots, 'Alter Hinweis',
        at: DateTime.now().subtract(const Duration(days: 30)));
    final settings = FakeSettings();
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);

    // Seit 0.38.0 (Design 1j) das Wort in Versalien und ein gelber
    // Rahmen um die Karte statt Symbol und getönter Zeile.
    expect(find.textContaining('NEUER HINWEIS'), findsOneWidget,
        reason: 'nur Bobs Flow — der Hinweis zu Roots ist älter als 7 Tage');
    Card card(String name) =>
        tester.widget<Card>(find.ancestor(of: find.text(name), matching: find.byType(Card)));
    expect((card('Bobs Flow').shape! as RoundedRectangleBorder).side.color,
        AppColors.light.map.note);
    expect((card('Roots').shape! as RoundedRectangleBorder).side.color,
        isNot(AppColors.light.map.note));

    await tester.tap(find.text('Bobs Flow'));
    await settle(tester);
    expect(find.text('Baum liegt quer nach der zweiten Kehre'), findsOneWidget);
    expect(find.text('bob · gestern gemeldet'), findsOneWidget);
    expect(find.byTooltip('Hinweis löschen'), findsNothing);
    expect(find.byTooltip('Erledigt — Hinweis entfernen'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(find.textContaining('NEUER HINWEIS'), findsNothing,
        reason: 'im Blatt gesehen — nicht mehr hervorgehoben');
    expect(settings.seenNoteIds, hasLength(1));

    // Und nach einem Neustart auch nicht.
    await pumpApp(tester, backend, trails: trails, settings: settings);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 20);
    expect(find.text('Bobs Flow'), findsOneWidget);
    expect(find.textContaining('NEUER HINWEIS'), findsNothing);
  });

  testWidgets('wer den Trail nur über einen Buddy sieht, darf schreiben und erledigen',
      (tester) async {
    trails.seedNote(bobId, bobsFlow, 'Baum liegt quer');
    await openTrail(tester, 'Bobs Flow');

    await tester.ensureVisible(find.byKey(const ValueKey('add-note')));
    await tester.tap(find.byKey(const ValueKey('add-note')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('note-text')), 'Umfahrung links');
    await settle(tester);
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 20);
    expect(trails.notes.where((n) => n.userId == annaId).single.trailId, bobsFlow);

    await tester.ensureVisible(find.byTooltip('Erledigt — Hinweis entfernen'));
    await tester.tap(find.byTooltip('Erledigt — Hinweis entfernen'));
    await settle(tester);
    expect(find.textContaining('auch für bob'), findsOneWidget);
    await tester.tap(find.text('Entfernen'));
    await settle(tester, frames: 20);
    expect(trails.notes.map((n) => n.body), ['Umfahrung links']);
    expect(find.text('Baum liegt quer'), findsNothing);
  });

  testWidgets('Hinweis schreiben und wieder löschen', (tester) async {
    await openTrail(tester, 'Roots');
    expect(find.textContaining('Noch keine.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('add-note')));
    await tester.tap(find.byKey(const ValueKey('add-note')));
    await settle(tester);
    expect(find.textContaining('Sehen deine Buddys'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('note-text')), '  Neuer Drop am Ende ');
    await settle(tester);
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 20);

    final note = trails.notes.single;
    expect(note.userId, annaId);
    expect(note.trailId, roots);
    expect(note.body, 'Neuer Drop am Ende');
    expect(find.text('Neuer Drop am Ende'), findsOneWidget);
    expect(find.text('Du · heute gemeldet'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Hinweis löschen'));
    await tester.tap(find.byTooltip('Hinweis löschen'));
    await settle(tester);
    await tester.tap(find.text('Löschen'));
    await settle(tester, frames: 20);
    expect(trails.notes, isEmpty);
    expect(find.text('Neuer Drop am Ende'), findsNothing);
  });

  testWidgets('Hinweise von Nicht-Buddys und zu privaten Beiträgen bleiben unsichtbar',
      (tester) async {
    trails.seedTrail(carlaId, trailId: roots);
    trails.seedNote(carlaId, roots, 'Carlas Hinweis');
    trails.seedNote(bobId, roots, 'Bobs Hinweis');
    trails.seedNote(bobId, bobsFlow, 'Bobs Hinweis zum Flow');
    // Bob hat seinen Beitrag zu Roots auf privat gestellt: Anna sieht den
    // Trail weiter (sie hat ihn selbst belegt), Bobs Hinweis dazu nicht.
    final i = trails.details.indexWhere((d) => d.userId == bobId && d.trailId == roots);
    trails.details[i] = trails.details[i].copyWith(visibility: TrailVisibility.private);

    // Mit Bobs Beitrag ist auch sein Name weg.
    await openTrail(tester, 'Trail ohne Namen');
    expect(find.text('Bobs Hinweis'), findsNothing);
    expect(find.text('Carlas Hinweis'), findsNothing);
    expect(find.textContaining('Noch keine.'), findsOneWidget);

    // Gegenprobe: Bobs geteilter Trail zeigt seinen Hinweis.
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await tester.tap(find.text('Bobs Flow'));
    await settle(tester);
    expect(find.text('Bobs Hinweis zum Flow'), findsOneWidget);
  });

  testWidgets('beim Status-Ändern geht ein Hinweis gleich mit', (tester) async {
    await openTrail(tester, 'Roots');
    expect(find.byKey(const ValueKey('status-note')), findsNothing);

    await tester.ensureVisible(find.text('Mein Beitrag'));
    await tester.tap(find.text('Mein Beitrag'));
    await settle(tester);
    expect(find.byKey(const ValueKey('status-note')), findsNothing,
        reason: 'nur angeboten, wenn sich der Status ändert');
    await tester.tap(find.text('Offen'));
    await settle(tester);
    await tester.tap(find.text('Gesperrt').last);
    await settle(tester);
    await tester.enterText(
        find.byKey(const ValueKey('status-note')), 'Forst sperrt bis Oktober');
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 20);

    expect(trails.details.singleWhere((d) => d.userId == annaId && d.trailId == roots).status,
        TrailStatus.closed);
    expect(trails.notes.single.body, 'Forst sperrt bis Oktober');
    expect(find.text('Forst sperrt bis Oktober'), findsOneWidget);
  });
}
