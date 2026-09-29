// Das Schild am Trailanfang (Design 4c, Schritt 6b): ab Zoom 13, am
// Anfang in Trail-Richtung, mit Grad und Merkmalen in der Farbe der Linie;
// ein Tipp öffnet den Trail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/trail_badges.dart';
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
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(anna.id, name: 'Hexentanz', grade: 3, traits: {TrailTrait.rocky});
    // Gegen die Trail-Richtung aufgenommen: Anfang ist das Ende der Linie.
    trails.seedTrail(anna.id, name: 'Rückwärts', lat: 48.02, grade: 1, reversed: true);
    trails.seedTrail(anna.id, name: 'Auffahrt', lat: 48.04, traits: {TrailTrait.uphill});
    // Ohne Grad und ohne Merkmale: kein Schild.
    trails.seedTrail(anna.id, name: 'Nackt', lat: 48.06);
  });

  MapViewMarker? badgeOf(WidgetTester tester, String name) {
    for (final m in fakeMapLayers(tester).markers) {
      if (m.hitValue is Trail && (m.hitValue as Trail).displayName == name) return m;
    }
    return null;
  }

  testWidgets('erst ab Zoom 13, am Anfang in Trail-Richtung, nur mit etwas zu sagen', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);

    fakeMap(tester).move(const LatLng(48.03, 9.0), kTrailBadgeMinZoom - 1);
    await settle(tester);
    expect(badgeOf(tester, 'Hexentanz'), isNull, reason: 'darunter stünden die Schilder übereinander');

    fakeMap(tester).move(const LatLng(48.03, 9.0), kTrailBadgeMinZoom);
    await settle(tester);
    expect(badgeOf(tester, 'Hexentanz')!.point, const LatLng(48.0, 9.0));
    expect(badgeOf(tester, 'Rückwärts')!.point, const LatLng(48.029, 9.0));
    // Neben der Linie, nicht auf ihr: Hexentanz führt nach Norden, das
    // Schild steht darunter; Rückwärts führt nach Süden, es steht darüber.
    expect(badgeOf(tester, 'Hexentanz')!.alignment, Alignment.bottomCenter);
    expect(badgeOf(tester, 'Rückwärts')!.alignment, Alignment.topCenter);
    expect(badgeOf(tester, 'Auffahrt'), isNotNull, reason: 'Uphill ohne Grad trägt den Pfeil');
    expect(badgeOf(tester, 'Nackt'), isNull);
    expect(findLabel('Schwierigkeit S3: verblockt, hohe Stufen, enge Kehren, Verblockt'), findsOneWidget);
    expect(findLabel('Uphill'), findsOneWidget);
  });

  testWidgets('ein Tipp auf das Schild öffnet den Trail', (tester) async {
    await pumpApp(tester, backend, trails: trails);
    await settle(tester, frames: 20);
    fakeMap(tester).move(const LatLng(48.0, 9.0), 15);
    await settle(tester);

    await tester.tap(find.byKey(badgeOf(tester, 'Hexentanz')!.key!));
    await settle(tester);
    expect(find.text('HEXENTANZ'), findsOneWidget);
  });
}
