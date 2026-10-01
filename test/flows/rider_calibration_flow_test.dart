// Lernen aus den eigenen Fahrten durch die echte Oberfläche (#158 Schritt
// 6): drei Fahrten mit Höhen auf einem Forstweg in einem gespeicherten
// Bereich, „Aus meinen Fahrten lernen" auf der Seite „Fahrerprofil", die
// gelernte Zahl in der Anzeige, der Planer rechnet damit, „zurücksetzen"
// holt die Vorgaben — und die Fälle ohne Fahrt und ohne Bereich sagen es.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';
import 'package:trailbuddy/features/routing/ride_calibrator.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_tiles.dart';
import '../fakes/test_app.dart';

final _tile = tileAt(48.0, 9.0, 13);
const _n = 1 << 13;
const _lon = 9.0;
final _bounds = tileBounds(13, _tile.x, _tile.y);
final _fromLat = math.max(_bounds.south + 0.0004, 48.0 - 0.003);

(int, int) _px(double lat, double lon, int x, int y) {
  final px = ((lon + 180) / 360 * _n - x) * kTileExtent;
  final r = lat * math.pi / 180;
  final py = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * _n - y) * kTileExtent;
  return (px.round(), py.round());
}

Future<MemoryAreaStore> _areaWithTrack() async {
  final store = MemoryAreaStore();
  final tiles = <TileToWrite>[];
  for (var dx = -1; dx <= 1; dx++) {
    for (var dy = -1; dy <= 1; dy++) {
      final x = _tile.x + dx, y = _tile.y + dy;
      tiles.add(TileToWrite(13, x, y,
          mvtTile([road([_px(_fromLat - 0.0002, _lon, x, y), _px(48.0 + 0.0095, _lon, x, y)], 'path', kindDetail: 'track')])));
    }
  }
  final bytes = writePmTiles(
    tiles: tiles,
    tileCompression: Compression.none,
    bounds: const TileBounds(west: 8.9, south: 47.9, east: 9.1, north: 48.1),
  );
  await store.putArchive('a', bytes);
  await store.saveIndex([
    StoredArea(
      id: 'a',
      name: 'Hausrunde',
      bounds: const AreaBounds(south: 47.9, west: 8.9, north: 48.1, east: 9.1),
      minZoom: 13,
      maxZoom: 13,
      build: '20260928',
      tiles: tiles.length,
      bytes: bytes.length,
      savedAt: DateTime.utc(2026, 9, 28),
    ),
  ]);
  return store;
}

/// Eine Fahrt den Forstweg hinauf: 1 km, 150 hm in 10 Minuten, Punkte
/// alle 10 s mit Höhe. Der Median über sieben Punkte kappt Anfang und
/// Gipfel um je 3,75 m — gelernt werden 142,5 hm in 600 s = 855 hm/h,
/// genau wie im Werkzeug, das dieselbe Glättung fährt.
Ride _climb(int k, {String? profile = 'bio', double hm = 150}) {
  final t0 = DateTime.utc(2026, 9, 20 + k, 9);
  final pts = [
    for (var i = 0; i <= 60; i++)
      RidePoint(
          lat: _fromLat + i * 0.009 / 60,
          lng: _lon,
          at: t0.add(Duration(seconds: i * 10)),
          accuracyM: 5,
          altM: 500 + i * hm / 60),
  ];
  return Ride(id: 'r$k', startedAt: t0, endedAt: pts.last.at, points: pts, profile: profile);
}

void main() {
  late FakeBackend backend;
  late FakeRideStore rides;
  late FakeSettings settings;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    rides = FakeRideStore()..uid = anna.id;
    settings = FakeSettings();
  });

  Future<void> open(WidgetTester tester, {MemoryAreaStore? areaStore}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend, rideStore: rides, areaStore: areaStore, settings: settings);
    await openProfilePage(tester, 'rider');
  }

  Future<void> learn(WidgetTester tester) async {
    await scrollTo(tester, find.byKey(const ValueKey('rider-learn')));
    await tester.tap(find.byKey(const ValueKey('rider-learn')));
    await settle(tester, frames: 30);
  }

  testWidgets('drei Fahrten bergauf: 855 hm/h gelernt, angezeigt, gemerkt, zurücksetzbar', (tester) async {
    rides.rides.addAll([_climb(1), _climb(2), _climb(3, hm: 120)]);
    await open(tester, areaStore: await _areaWithTrack());
    expect(find.textContaining('Vorgaben — noch nichts gelernt'), findsNWidgets(2));
    await learn(tester);
    expect(find.textContaining('Gelernt: Bio-Bike aus 3 Fahrten (3 Aufstiege)'), findsOneWidget);
    final line = tester.widget<Text>(find.byKey(const ValueKey('rider-calib-bio'))).data!;
    expect(line, contains('Forstweg 855 hm/h'));
    expect(line, contains('aus 3 Fahrten (3 Aufstiege)'));
    expect(tester.widget<Text>(find.byKey(const ValueKey('rider-calib-ebike'))).data, contains('Vorgaben'));
    final numbers = tester.widget<Text>(find.byKey(const ValueKey('rider-profile-numbers'))).data!;
    expect(numbers, contains('Steigrate Forstweg: 855 hm/h (gelernt)'));
    expect(numbers, contains('Pfad: 350 hm/h ·'), reason: 'ohne Pfad-Messung die Vorgabe, ohne „(gelernt)"');
    expect(settings.riderCalibration, contains('"bio"'));
    // Der Planer rechnet mit dem gelernten Profil.
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('rider-learn'))));
    expect(container.read(calibratedRiderProvider(RiderProfile.bio)).climbTrackMPerH, closeTo(855, 1e-6));
    expect(container.read(calibratedRiderProvider(RiderProfile.ebike)).climbTrackMPerH, RiderProfile.ebike.climbTrackMPerH);

    await scrollTo(tester, find.byKey(const ValueKey('rider-reset')));
    await tester.tap(find.byKey(const ValueKey('rider-reset')));
    await settle(tester);
    expect(find.textContaining('Vorgaben — noch nichts gelernt'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('rider-reset')), findsNothing);
    expect(settings.riderCalibration, isNull);
    expect(container.read(calibratedRiderProvider(RiderProfile.bio)).climbTrackMPerH, RiderProfile.bio.climbTrackMPerH);
  });

  testWidgets('zu wenige Aufstiege, Fahrt ohne Profil, geplante Fahrt: nichts gelernt', (tester) async {
    rides.rides.addAll([
      _climb(1),
      _climb(2),
      _climb(3, profile: null),
      Ride(id: 'p', startedAt: DateTime.utc(2026, 9, 1), endedAt: DateTime.utc(2026, 9, 1), points: _climb(4).points,
          profile: 'bio', planned: true, name: 'Runde'),
    ]);
    await open(tester, areaStore: await _areaWithTrack());
    await learn(tester);
    // Zwei brauchbare Fahrten liefern zwei Aufstiege — unter der Mindestzahl.
    expect(find.textContaining('Gelernt: Bio-Bike aus 2 Fahrten (2 Aufstiege)'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('rider-calib-bio'))).data, contains('Vorgaben'));
    expect(find.byKey(const ValueKey('rider-reset')), findsNothing);
  });

  testWidgets('ohne Fahrt und ohne Bereich sagt es die Leiste', (tester) async {
    await open(tester);
    await learn(tester);
    expect(find.textContaining('Keine Fahrt auf diesem Gerät'), findsOneWidget);
    await drainSnackbars(tester);
    rides.rides.addAll([_climb(1), _climb(2), _climb(3)]);
    await learn(tester);
    expect(find.textContaining('Kein gespeicherter Bereich deckt deine Fahrten'), findsOneWidget);
    expect(settings.riderCalibration, isNull);
  });
}
