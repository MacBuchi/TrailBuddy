// Die Glühbirne: Idee oder Fehler an den Betreiber. Der Bot macht daraus
// ein ÖFFENTLICHES Issue (tool/feedback_bot.py) — deshalb zählt hier
// auch, dass der Dialog das vor dem Schreiben sagt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('von der Karte: Fehler melden, mit Version, Hinweis auf öffentlich',
      (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    await pumpApp(tester, backend, appVersion: '0.2.0');

    await tester.tap(find.byTooltip('Idee oder Fehler melden'));
    await settle(tester);
    expect(find.text('Wünsch dir was!'), findsOneWidget);
    expect(find.textContaining('öffentlicher Eintrag auf GitHub'), findsOneWidget);
    expect(find.textContaining('keine Trailnamen'), findsOneWidget);

    await tester.tap(find.text('Fehler'));
    await settle(tester);
    // Unter drei Zeichen ist „Senden" gar nicht erst aktiv.
    await tester.enterText(find.byType(TextField), 'ab');
    await settle(tester);
    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Senden')).onPressed,
        isNull);

    await tester.enterText(find.byType(TextField), '  Import bleibt hängen  ');
    await settle(tester);
    await tester.tap(find.text('Senden'));
    await settle(tester);

    expect(backend.feedback, [
      {
        'user_id': backend.currentUserId,
        'type': 'bug',
        'message': 'Import bleibt hängen',
        'app_version': '0.2.0',
      }
    ]);
    expect(find.textContaining('Danke für die Meldung'), findsOneWidget);
  });

  testWidgets('aus dem Profil: Idee, und ohne Netz sagt es das', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    await pumpApp(tester, backend);
    await openTab(tester, 'Profil');
    // In die Mitte holen: am unteren Rand läge die Zeile unter der
    // Navigationsleiste, und der Tipp träfe die.
    final tile = find.text('Idee oder Fehler melden');
    await tester.scrollUntilVisible(tile, 200);
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(tile), alignment: 0.5));
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);

    expect(find.text('Wünsch dir was!'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Höhenprofil wäre toll');
    await settle(tester);
    backend.offline = true;
    await tester.tap(find.text('Senden'));
    await settle(tester);

    expect(backend.feedback, isEmpty);
    expect(find.textContaining('Keine Verbindung'), findsOneWidget);
  });

  testWidgets('Abbrechen schickt nichts', (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'anna').id);
    await pumpApp(tester, backend);
    await tester.tap(find.byTooltip('Idee oder Fehler melden'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'nur so');
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(backend.feedback, isEmpty);
    expect(find.text('Wünsch dir was!'), findsNothing);
  });
}
