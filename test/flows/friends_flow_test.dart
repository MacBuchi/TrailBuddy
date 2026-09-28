// Buddys: suchen, anfragen, annehmen, ablehnen, entfernen — komplette App
// gegen das In-Memory-Backend, das die Freundschafts-Regeln spiegelt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testrail');
    backend.signInAs(me.id);
    return (backend, me);
  }

  testWidgets('Buddy-Suche findet Nutzer und sendet eine Anfrage',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addUser(username: 'lilli92');
    await pumpApp(tester, backend);

    await openTab(tester, 'Buddys');
    await tester.enterText(
        find.widgetWithText(TextField, 'Buddy finden'), 'lilli');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    await tester.tap(find.text('Anfragen'));
    await settle(tester);

    expect(backend.friendships.single.requesterId, me.id);
    expect(backend.friendships.single.status, 'pending');
    expect(find.text('Gesendete Anfragen'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Die Suche findet über die EXAKTE Adresse, nicht über Teile',
      (tester) async {
    // Sonst wäre die Suche ein Adressverzeichnis: „example" lieferte
    // jedes Konto der Domain.
    final (backend, _) = loggedInBackend();
    backend.addUser(username: 'lilli92', email: 'lilli@example.org');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    await tester.enterText(
        find.widgetWithText(TextField, 'Buddy finden'), 'example.org');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Niemanden gefunden.'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Buddy finden'), 'lilli@example.org');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('lilli92'), findsOneWidget);
  });

  testWidgets('Eine eingehende Anfrage lässt sich annehmen — und die Karte sagt, was sich tut',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id, status: 'pending');
    // Konzept 6: ein gemeinsamer Trail (beide belegt), einer nur von
    // Lilli, einer nur von mir — und ein privater von mir, den Lilli
    // auch jetzt nicht sieht.
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(me.id, name: 'Hexentanz', trailId: 'shared');
    trails.seedTrail(lilli.id, name: 'Roots', trailId: 'shared', lat: 48.0, lon: 9.0);
    trails.seedTrail(lilli.id, name: 'Nur Lilli', lat: 48.1);
    trails.seedTrail(me.id, name: 'Nur ich', lat: 48.2);
    trails.seedTrail(me.id, name: 'Geheim', lat: 48.3, visibility: TrailVisibility.private);
    await pumpApp(tester, backend, trails: trails);
    await openTab(tester, 'Buddys');

    expect(find.text('Anfragen an dich'), findsOneWidget);
    await tester.tap(find.byTooltip('Annehmen'));
    await settle(tester, frames: 12);

    expect(backend.friendships.single.status, 'accepted');
    expect(find.text('Anfragen an dich'), findsNothing);
    // Der neue Buddy steht in der Liste — mit Alias-Knopf, denn erst
    // jetzt darf er einen bekommen.
    expect(find.text('lilli92'), findsWidgets);
    expect(find.byTooltip('Alias vergeben'), findsOneWidget);
    // Die Zusammenfassung NACH dem Annehmen: der private Trail zählt
    // nicht als „neu für Lilli".
    expect(find.text('Mit lilli92 verbunden: 1 Trail gemeinsam, 1 neu von lilli92, 1 neu für lilli92.'),
        findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Annehmen ohne Trails auf beiden Seiten sagt das', (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id, status: 'pending');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');
    await tester.tap(find.byTooltip('Annehmen'));
    await settle(tester, frames: 12);
    expect(find.textContaining('noch keine Trails'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Ablehnen löscht die Anfrage', (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id, status: 'pending');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    await tester.tap(find.byTooltip('Ablehnen'));
    await settle(tester, frames: 12);

    expect(backend.friendships, isEmpty);
    expect(find.text('lilli92'), findsNothing);
  });

  testWidgets('Eine gesendete Anfrage lässt sich zurückziehen',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(me.id, lilli.id, status: 'pending');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    expect(find.text('Gesendete Anfragen'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurückziehen'));
    await settle(tester, frames: 12);

    expect(backend.friendships, isEmpty);
    expect(find.text('Gesendete Anfragen'), findsNothing);
  });

  testWidgets('Entfernen fragt nach und beendet die Freundschaft',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(me.id, lilli.id);
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    await tester.tap(find.byTooltip('Buddy entfernen'));
    await settle(tester);
    expect(find.text('lilli92 als Buddy entfernen?'), findsOneWidget);

    // Abbrechen: alles bleibt.
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(backend.friendships, hasLength(1));

    await tester.tap(find.byTooltip('Buddy entfernen'));
    await settle(tester);
    await tester.tap(find.text('Entfernen'));
    await settle(tester, frames: 12);
    expect(backend.friendships, isEmpty);
    expect(find.textContaining('Noch keine Buddys verbunden'), findsOneWidget);
  });

  testWidgets('Ein schon verbundener Treffer bietet kein „Anfragen" mehr',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(me.id, lilli.id);
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    await tester.enterText(
        find.widgetWithText(TextField, 'Buddy finden'), 'lilli');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('Anfragen'), findsNothing);
  });
}
