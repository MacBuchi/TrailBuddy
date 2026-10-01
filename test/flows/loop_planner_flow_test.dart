// Der Rundenplaner durch die echte Oberfläche (#158 Schritt 5): vom Knopf
// auf der Karte über Regler, Pool und Rechnen zum Ergebnis — Summen, die
// Trails in Reihenfolge, die Vorschau als Linien der Fassade, „Als Fahrt
// speichern" (geplante Fahrt in „Meine Fahrten", ohne Schere) und „Als
// GPX"; der getippte Start über die Karte, und die beiden Fälle, in denen
// nichts gerechnet werden kann (kein Bereich, kein Standort).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/gpx_share.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/routing/trail_head_providers.dart' show RouteMode;
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/trails/gpx.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_rides.dart';
import '../fakes/fake_tiles.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

/// Der Trail von `seedTrail` läuft von 48,0° N / 9,0° O 1 km nach Norden;
/// der Standort liegt südlich davon. Ein Forstweg entlang 9,0° O verbindet
/// Standort, Trailkopf und Trailende — die Runde ist Weg hinauf, Trail
/// hinunter … nein: Trail hinauf (er läuft nach Norden) und Weg zurück.
final _tile = tileAt(48.0, 9.0, 13);
const _n = 1 << 13;
const _lon = 9.0;
final _bounds = tileBounds(13, _tile.x, _tile.y);
final _fromLat = math.max(_bounds.south + 0.0004, 48.0 - 0.003);

/// Grad → Kachel-Pixel der Kachel [x]/[y]; außerhalb der Kachel darf das
/// Ergebnis liegen — `wayLinesFromTile` schneidet die Linie zu.
(int, int) _px(double lat, double lon, int x, int y) {
  final px = ((lon + 180) / 360 * _n - x) * kTileExtent;
  final r = lat * math.pi / 180;
  final py = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * _n - y) * kTileExtent;
  return (px.round(), py.round());
}

/// Ein Bereich mit der Kachel des Trails und ihren acht Nachbarn; der
/// Forstweg liegt in jeder Kachel, die er berührt (die Schere je Kachel).
/// [onlyCenter]: nur die Kachel des Trails — wie ein Bereich „Entlang
/// meiner Trails", der das Rechteck um die Runde nie ganz deckt.
Future<MemoryAreaStore> _areaWithTrack({bool onlyCenter = false}) async {
  final store = MemoryAreaStore();
  final tiles = <TileToWrite>[];
  final reach = onlyCenter ? 0 : 1;
  for (var dx = -reach; dx <= reach; dx++) {
    for (var dy = -reach; dy <= reach; dy++) {
      final x = _tile.x + dx, y = _tile.y + dy;
      tiles.add(TileToWrite(
        13,
        x,
        y,
        mvtTile([road([_px(_fromLat - 0.0002, _lon, x, y), _px(48.0 + 0.0095, _lon, x, y)], 'path', kindDetail: 'track')]),
      ));
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

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late FakeRideStore rides;
  late String hex, sperr;
  late List<({String fileName, String xml})> shared;

  Future<GpxShareOutcome> recorder({required String fileName, required String xml}) async {
    shared.add((fileName: fileName, xml: xml));
    return GpxShareOutcome.shared;
  }

  setUp(() {
    shared = [];
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    hex = trails.seedTrail(anna.id, name: 'Hexentanz', grade: 2, rating: 4);
    // Gemeldet: steht abseits, nicht vorgewählt. Zu weit: 30 km nördlich.
    sperr = trails.seedTrail(anna.id, name: 'Sperrgebiet', grade: 1, status: TrailStatus.closed, lat: 48.0, lon: 9.004);
    trails.seedTrail(anna.id, name: 'Fernweh', grade: 1, lat: 48.3);
    rides = FakeRideStore();
  });

  Future<void> start(WidgetTester tester,
      {MemoryAreaStore? areaStore, FakePositionFix? positionFix, FakeSettings? settings}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, backend,
        trails: trails,
        areaStore: areaStore,
        rideStore: rides,
        positionFix: positionFix ?? FakePositionFix(fakePosition(_fromLat, _lon)),
        settings: settings,
        extraOverrides: [gpxShareProvider.overrideWithValue(recorder)]);
    await settle(tester, frames: 20);
  }

  /// Das Blatt ist halb offen; was unter dem Rand liegt, erst hochziehen.
  Future<void> inSheet(WidgetTester tester, Finder finder) async {
    final list = find
        .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
        .first;
    for (var i = 0; i < 6 && finder.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    await tester.drag(list, const Offset(0, -300));
    await settle(tester, frames: 4);
    await tester.ensureVisible(finder);
    await settle(tester);
  }

  Future<void> tapInSheet(WidgetTester tester, Key key) async {
    await inSheet(tester, find.byKey(key));
    await tester.tap(find.byKey(key));
    await settle(tester, frames: 30);
  }

  /// Das Navi-Symbol der Zeile — die Zeile steht so tief, dass die untere
  /// Hälfte des Symbols unter der Reiterleiste liegt; getippt wird oben.
  Future<void> tapNav(WidgetTester tester) async {
    final rect = tester.getRect(find.byKey(ValueKey('trail-nav-$hex')));
    await tester.tapAt(rect.topCenter + const Offset(0, 8));
  }

  Future<void> openPlanner(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('loop-button')));
    await settle(tester, frames: 20);
    expect(find.text('Runde planen'), findsOneWidget);
  }

  Iterable<dynamic> connectionLines(WidgetTester tester) =>
      fakeMapLayers(tester).polylines.where((l) => l.width == 5);
  Iterable<dynamic> trailLines(WidgetTester tester) =>
      fakeMapLayers(tester).polylines.where((l) => l.width == 9);

  testWidgets('vom Knopf zur Runde: Pool, Ergebnis, Vorschau, Fahrt, GPX', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    await openPlanner(tester);
    expect(find.byKey(const ValueKey('loop-start')), findsOneWidget);
    expect(find.textContaining('mein Standort'), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-time')), findsOneWidget);

    await tapInSheet(tester, const ValueKey('loop-next'));
    // Der Pool: Hexentanz vorgewählt, Sperrgebiet abseits und aus, Fernweh
    // zu weit und nur gezählt.
    expect(find.text('Trails in Reichweite (1)'), findsOneWidget);
    expect(find.text('Gemeldet (1)'), findsOneWidget);
    expect(find.textContaining('1 Trail liegt weiter als'), findsOneWidget);
    expect(find.text('Fernweh'), findsNothing);
    expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('loop-trail-$hex'))).value, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('loop-trail-$sperr'))).value, isFalse);
    expect(find.text('Runde rechnen (1)'), findsOneWidget);

    await tapInSheet(tester, const ValueKey('loop-compute'));
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
    expect(find.textContaining('hm bergauf'), findsOneWidget);
    // Hexentanz trägt 4 Sterne: Die zweite Abfahrt bringt noch 30 %, und
    // das Budget reicht — also zweimal, 1,3 km Trail-Meter, „noch einmal".
    expect(find.textContaining('1,3 km Trail'), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-stop-0')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('loop-stop-0')), matching: find.text('Hexentanz')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('loop-stop-1')), matching: find.textContaining('noch einmal')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('loop-stop-2')), findsNothing, reason: 'höchstens zweimal');
    expect(find.textContaining('Untergrenze'), findsOneWidget, reason: 'der Bereich hat keine Höhen');
    expect(find.byKey(const ValueKey('loop-notice')), findsNothing);
    // Die Vorschau: der Trail als Saum, die Verbindungen als Linien, die
    // ganze Linie beginnt und endet am Standort.
    expect(trailLines(tester), hasLength(2));
    expect(connectionLines(tester), isNotEmpty);
    final whole = fakeMapLayers(tester).polylines.where((l) => l.width == 2).single;
    expect(whole.points.first.latitude, closeTo(_fromLat, 1e-9));
    expect(whole.points.last.latitude, closeTo(_fromLat, 1e-9));

    // Als Fahrt speichern: eine geplante Fahrt im Speicher, mit Namen.
    await tapInSheet(tester, const ValueKey('loop-save'));
    expect(rides.rides, hasLength(1));
    expect(rides.rides.single.planned, isTrue);
    expect(rides.rides.single.name, 'Runde: Hexentanz');
    expect(rides.rides.single.points.first.lat, closeTo(_fromLat, 1e-9));
    expect(find.textContaining('Als geplante Fahrt gespeichert'), findsOneWidget);

    await tapInSheet(tester, const ValueKey('loop-gpx'));
    expect(shared, hasLength(1));
    expect(shared.single.fileName, 'trailbuddy-runde-hexentanz.gpx');
    final track = parseGpx(shared.single.xml).single;
    expect(track.name, 'Runde: Hexentanz');
    expect(track.points.every((p) => p.ele == null && p.time == null), isTrue);

    // Die Runde liegt ÜBER dem eingeklappten Blatt (Feldbericht 0.73.0).
    expect(fakeMap(tester).lastFitBottomInset, greaterThan(100));
    // Runterziehen verkleinert, schließt nie.
    final sheetList = find
        .descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable))
        .first;
    for (var i = 0; i < 4; i++) {
      await tester.drag(sheetList, const Offset(0, 1500));
      await settle(tester, frames: 4);
    }
    expect(find.text('Runde planen'), findsOneWidget);
    expect(trailLines(tester), hasLength(2));

    // Blatt zu (X) ⇒ Vorschau weg.
    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
    expect(trailLines(tester), isEmpty);

    // „Meine Fahrten": die geplante Fahrt mit Name und Datum, ohne Schere.
    await drainSnackbars(tester);
    await openTab(tester, 'Profil');
    await tester.tap(find.text('Meine Fahrten'));
    await settle(tester);
    expect(find.text('Runde: Hexentanz'), findsOneWidget);
    expect(find.textContaining('Geplant am'), findsOneWidget);
    expect(find.byKey(ValueKey('ride-split-${rides.rides.single.id}')), findsNothing);
    expect(find.byKey(ValueKey('ride-menu-${rides.rides.single.id}')), findsOneWidget);
  });

  testWidgets('den Start auf der Karte tippen — und abbrechen', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    await openPlanner(tester);
    await tester.tap(find.byKey(const ValueKey('loop-pick')));
    await settle(tester, frames: 20);
    expect(find.text('Runde planen'), findsNothing, reason: 'das Blatt macht der Karte Platz');
    expect(find.byKey(const ValueKey('loop-pick-banner')), findsOneWidget);
    await tapMapAt(tester, LatLng(_fromLat + 0.0005, _lon));
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing);
    expect(find.text('Runde planen'), findsOneWidget);
    expect(find.textContaining('getippter Punkt'), findsOneWidget);
    // Der getippte Punkt trägt die Planung; „Mein Standort" nimmt ihn zurück.
    await tester.tap(find.byKey(const ValueKey('loop-start-me')));
    await settle(tester);
    expect(find.textContaining('mein Standort'), findsOneWidget);

    // Abbrechen über das Banner: kein Blatt, kein Start.
    await tester.tap(find.byKey(const ValueKey('loop-pick')));
    await settle(tester, frames: 20);
    await tester.tap(find.byKey(const ValueKey('loop-pick-cancel')));
    await settle(tester);
    expect(find.byKey(const ValueKey('loop-pick-banner')), findsNothing);
    expect(find.text('Runde planen'), findsNothing);
  });

  testWidgets('ohne gespeicherten Bereich: ein Satz, keine Runde', (tester) async {
    await start(tester);
    await openPlanner(tester);
    await tapInSheet(tester, const ValueKey('loop-next'));
    await tapInSheet(tester, const ValueKey('loop-compute'));
    expect(find.textContaining('Kein gespeicherter Bereich'), findsOneWidget);
    expect(find.byKey(const ValueKey('loop-summary')), findsNothing);
    expect(trailLines(tester), isEmpty);
    expect(rides.rides, isEmpty);
  });

  testWidgets('ohne Standort: ein Satz, gefragt wurde genau einmal', (tester) async {
    final fix = FakePositionFix(null);
    await start(tester, areaStore: await _areaWithTrack(), positionFix: fix);
    await openPlanner(tester);
    await tapInSheet(tester, const ValueKey('loop-next'));
    expect(find.textContaining('Kein Standort'), findsOneWidget);
    expect(fix.calls, 1);
    expect(find.byKey(const ValueKey('loop-compute')), findsNothing);
  });

  testWidgets('#178: im Pool wählt ein Tipp auf den Trail der Karte ihn ab und wieder an', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    await openPlanner(tester);
    await tapInSheet(tester, const ValueKey('loop-next'));
    expect(find.byKey(const ValueKey('loop-map-pick-hint')), findsOneWidget);
    bool checked() => tester.widget<CheckboxListTile>(find.byKey(ValueKey('loop-trail-$hex'))).value!;
    Iterable<dynamic> picked() => fakeMapLayers(tester).polylines.where((l) => l.width == 8);
    expect(checked(), isTrue);
    expect(picked(), hasLength(1), reason: 'der gewählte Trail leuchtet');
    // Die Karte zeigt Start und Pool über dem Blatt — nah genug zum Tippen.
    expect(fakeMap(tester).zoom, greaterThan(13));

    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    expect(checked(), isFalse);
    expect(picked(), isEmpty);
    expect(find.text('HEXENTANZ'), findsNothing, reason: 'kein Trail-Blatt, solange der Pool offen ist');

    await tapMapAt(tester, const LatLng(48.004, _lon));
    await settle(tester);
    expect(checked(), isTrue);
  });

  testWidgets('Bereich deckt das Rechteck nur zum Teil: trotzdem eine Runde, mit Satz', (tester) async {
    await start(tester, areaStore: await _areaWithTrack(onlyCenter: true));
    await openPlanner(tester);
    await tapInSheet(tester, const ValueKey('loop-next'));
    await tapInSheet(tester, const ValueKey('loop-compute'));
    expect(find.byKey(const ValueKey('loop-blocker')), findsNothing);
    expect(find.byKey(const ValueKey('loop-summary')), findsOneWidget);
    await inSheet(tester, find.byKey(const ValueKey('loop-partial')));
    expect(find.byKey(const ValueKey('loop-partial')), findsOneWidget);
  });

  testWidgets('ohne Bereich steht der Grund OBEN im Blatt', (tester) async {
    await start(tester);
    await openPlanner(tester);
    await tapInSheet(tester, const ValueKey('loop-next'));
    await tapInSheet(tester, const ValueKey('loop-compute'));
    final blocker = find.byKey(const ValueKey('loop-blocker'));
    expect(blocker, findsOneWidget);
    expect(tester.getTopLeft(blocker).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('loop-compute'))).dy));
  });

  testWidgets('#177: langer Druck — „Route ab hier" plant ab dem Punkt, „Route bis hier" zeigt den Weg', (tester) async {
    await start(tester, areaStore: await _areaWithTrack());
    final point = LatLng(_fromLat + 0.001, _lon);
    await longPressMapAt(tester, point);
    await settle(tester);
    expect(find.byKey(const ValueKey('map-press-pin')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-menu-from')));
    await settle(tester, frames: 20);
    expect(find.text('Runde planen'), findsOneWidget);
    expect(find.textContaining('getippter Punkt'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-press-pin')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('loop-close')));
    await settle(tester);

    await longPressMapAt(tester, const LatLng(48.009, _lon));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('map-menu-to')));
    await settle(tester, frames: 30);
    expect(find.text('Route hierher'), findsOneWidget);
    expect(find.byKey(const ValueKey('trail-head-summary')), findsOneWidget);
    expect(connectionLines(tester), isNotEmpty);
  });

  testWidgets('#176: das Navi-Symbol fragt, merkt sich den Standard, „spaßig" öffnet den Weg auf der Karte',
      (tester) async {
    final settings = FakeSettings();
    await start(tester, areaStore: await _areaWithTrack(), settings: settings);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 10);
    await tapNav(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('nav-choice-external')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-remember')));
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const ValueKey('nav-choice-fun')));
    await settle(tester, frames: 30);
    expect(settings.navDefault, 'fun');
    expect(find.text('Zum Trailkopf'), findsOneWidget);
    final mode = tester.widget<SegmentedButton<RouteMode>>(find.byKey(const ValueKey('route-mode')));
    expect(mode.selected.single, RouteMode.fun);
    await tester.tap(find.byKey(const ValueKey('trail-head-close')));
    await settle(tester);

    // Mit Standard fragt es nicht mehr.
    await openTab(tester, 'Trails');
    await settle(tester, frames: 10);
    await tapNav(tester);
    await settle(tester, frames: 30);
    expect(find.byKey(const ValueKey('nav-choice-external')), findsNothing);
    expect(find.text('Zum Trailkopf'), findsOneWidget);
  });
}
