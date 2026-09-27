// Der GPX-Import (Konzept 5.2) einmal durch: Dateien wählen, Einordnung
// lesen, beisteuern, in der Liste wiederfinden. Der Abgleich selbst ist
// Sache der Datenbank (tool/matcher_check.sql); hier zählt, was die App
// aus einer Datei macht und was sie dem Nutzer sagt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// Eine Spur nach Norden ab 48°/9°: [lengthM] lang, mit Höhe von
/// [eleStart] nach [eleEnd], Zeiten für ~18 km/h wenn [timed].
String gpx(String name, double lengthM,
    {double eleStart = 600, double eleEnd = 500, bool timed = true}) {
  const step = 20.0;
  final n = (lengthM / step).round();
  final b = StringBuffer('<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
      '<trk><name>$name</name><trkseg>');
  for (var i = 0; i <= n; i++) {
    final lat = 48.0 + i * step / 111320.0;
    final ele = eleStart + (eleEnd - eleStart) * i / n;
    final t = DateTime.utc(2026, 5, 1, 10).add(Duration(seconds: i * 4));
    b.write('<trkpt lat="$lat" lon="9.0"><ele>$ele</ele>'
        '${timed ? '<time>${t.toIso8601String()}</time>' : ''}</trkpt>');
  }
  b.write('</trkseg></trk></gpx>');
  return b.toString();
}

void main() {
  testWidgets('kurze Abfahrt wird beigesteuert, Fahrt bleibt liegen', (tester) async {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    final files = [
      PickedGpx(name: 'wurzel.gpx', text: gpx('Wurzeltrail', 1200)),
      PickedGpx(name: 'runde.gpx', text: gpx('Sonntagsrunde', 12000, eleStart: 300, eleEnd: 320)),
      const PickedGpx(name: 'kaputt.gpx', text: '<kml/>'),
    ];
    await pumpApp(tester, backend, trails: trails, extraOverrides: [
      gpxPickerProvider.overrideWithValue(() async => files),
    ]);

    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    expect(find.text('GPX importieren'), findsWidgets);

    await tester.tap(find.text('GPX-Dateien wählen'));
    await settle(tester);

    // Zwei Spuren gefunden, eine davon als Trail; die Fahrt ist erklärt, die
    // kaputte Datei benannt.
    expect(find.text('2 Spuren gefunden, 1 davon als Trail'), findsOneWidget);
    expect(find.text('Wurzeltrail'), findsOneWidget);
    expect(find.textContaining('Fahrt — zerlegen kommt später'), findsOneWidget);
    expect(find.textContaining('kaputt.gpx:'), findsOneWidget);
    expect(find.textContaining('aufgezeichnet'), findsWidgets);

    await tester.tap(find.text('1 beisteuern'));
    await settle(tester, frames: 20);

    expect(trails.contributeCalls, 1);
    expect(trails.recordings.single.source, RecordingSource.import);
    expect(trails.recordings.single.recordedAt, isNotNull);
    expect(trails.details.single.name, 'Wurzeltrail');
    expect(find.textContaining('1 Trail beigesteuert'), findsOneWidget);
    expect(find.text('1 beigesteuert, 0 fehlgeschlagen.'), findsOneWidget);

    // Zurück in die Liste: der Trail steht unter „Meine Trails".
    await tester.tap(find.byType(BackButton));
    await settle(tester, frames: 20);
    expect(find.text('Meine Trails (1)'), findsOneWidget);
    expect(find.text('Wurzeltrail'), findsOneWidget);
  });

  testWidgets('ohne Zeiten wird es „geplant", ein Fehlschlag wird benannt', (tester) async {
    final backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    final trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    final files = [
      PickedGpx(name: 'plan.gpx', text: gpx('Geplante Linie', 900, timed: false)),
      PickedGpx(name: 'zwei.gpx', text: gpx('Zweiter', 800)),
    ];
    await pumpApp(tester, backend, trails: trails, extraOverrides: [
      gpxPickerProvider.overrideWithValue(() async => files),
    ]);
    await openTab(tester, 'Trails');
    await tester.tap(find.byTooltip('GPX importieren'));
    await settle(tester);
    await tester.tap(find.text('GPX-Dateien wählen'));
    await settle(tester);
    expect(find.textContaining('geplant (keine Fahrzeiten)'), findsOneWidget);

    trails.failNextContribute = Exception('Datenbank nicht erreichbar');
    await tester.tap(find.text('2 beisteuern'));
    await settle(tester, frames: 20);

    expect(find.text('1 beigesteuert, 1 fehlgeschlagen.'), findsOneWidget);
    expect(find.textContaining('Geplante Linie:'), findsOneWidget);
    expect(trails.recordings.single.source, RecordingSource.import);
    // Der gescheiterte Kandidat bleibt in der Liste, der andere ist weg.
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });
}
