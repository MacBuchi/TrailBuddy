// Bereiche speichern (Konzept-Schritt 3), vom Blatt bis zur Liste: Die
// Größe steht vor dem Speichern da, der Download legt den Bereich ab,
// „Meine Bereiche" zeigt ihn mit Größe und Stand, Löschen räumt ab —
// und ohne Kartenhost sagt das Blatt, dass es keinen Bereich gibt.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/offline_areas/area_draw.dart';
import 'package:trailbuddy/features/offline_areas/area_overlay.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

const _manifest = MapManifest(
  file: 'dach-20260928.pmtiles',
  maxZoom: 10,
  bytes: 1,
  sourceBuild: '20260928',
);

/// Das Archiv des „Hosts": Zoom 8–10 rund um den Trail des Harness
/// (48,0° N, 9,0° O).
Uint8List _sourceBytes() {
  const wide = AreaBounds(south: 47.5, west: 8.5, north: 48.5, east: 9.5);
  return writePmTiles(
    tiles: [
      for (final t in tilesCovering(wide, maxZoom: 10))
        TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('t${t.z}/${t.x}/${t.y}'))),
    ],
    tileCompression: Compression.none,
    bounds: const TileBounds(west: 8.5, south: 47.5, east: 9.5, north: 48.5),
  );
}

void main() {
  late FakeBackend backend;
  late FakeTrailRepository trails;
  late MemoryAreaStore store;
  late FakeKeepAlive keepAlive;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    trails = FakeTrailRepository(
        myId: () => backend.currentUserId ?? '', areFriends: backend.areFriends);
    trails.seedTrail(backend.currentUserId!, name: 'Roots');
    store = MemoryAreaStore();
    keepAlive = FakeKeepAlive();
  });

  Future<void> start(WidgetTester tester, {bool host = true}) async {
    final source = _sourceBytes();
    await pumpApp(tester, backend,
        trails: trails,
        areaStore: store,
        keepAlive: keepAlive,
        extraOverrides: [
          mapManifestLoaderProvider.overrideWithValue(() async => host ? _manifest : null),
          areaSourceOpenerProvider.overrideWithValue((_) => PmTilesArchive.fromBytes(source)),
          areaPoiManifestLoaderProvider.overrideWithValue(() async => null),
        ]);
    await settle(tester, frames: 20);
  }

  Future<void> openSaveSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Ebenen und Orte'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('offline-maps-tile')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('save-area-tile')));
    await settle(tester, frames: 20);
  }

  testWidgets('„Offline-Karten" dunkelt die Karte ab, gespeicherte Kacheln bleiben hell — bis das Blatt zugeht',
      (tester) async {
    // Ein Bereich liegt schon: seine Kacheln sind die Löcher der Maske.
    await store.putArchive('old', _sourceBytes());
    await store.saveIndex([
      StoredArea(
        id: 'old',
        name: 'Alt',
        bounds: const AreaBounds(south: 47.99, west: 8.99, north: 48.02, east: 9.01),
        minZoom: 8,
        maxZoom: 10,
        build: '20260928',
        tiles: 5,
        bytes: 500,
        savedAt: DateTime.utc(2026, 9, 28),
      ),
    ]);
    await start(tester);
    expect(fakeMapLayers(tester).polygons, isEmpty, reason: 'ohne Blatt keine Maske');

    await tester.tap(find.byTooltip('Ebenen und Orte'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('offline-maps-tile')));
    await settle(tester);
    expect(find.text('Offline-Karten'), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-area-old')), findsOneWidget);
    final mask = fakeMapLayers(tester).polygons.single;
    expect(mask.fillColor, kOfflineDimColor);
    expect(mask.holes, isNotEmpty, reason: 'der Bereich liegt im Ausschnitt');
    // Jedes Loch ist eine Kachel des Bereichs (bei dessen Zoom 10).
    final z = offlineOverlayZoom(fakeMap(tester).camera.zoom).clamp(8, 10);
    for (final hole in mask.holes) {
      final t = tileAt(hole.first.latitude - 1e-6, hole.first.longitude + 1e-6, z);
      expect(tileBounds(z, t.x, t.y).contains(hole[2]), isTrue);
    }

    // Antippen zeigt den Bereich; die Karte bleibt bedienbar.
    await tester.tap(find.byKey(const ValueKey('offline-area-old')));
    await settle(tester);
    expect(fakeMap(tester).camera.center.latitude, closeTo(48.005, 0.01));

    await tester.tap(find.byKey(const ValueKey('offline-maps-close')));
    await settle(tester);
    expect(find.byKey(const ValueKey('offline-area-old')), findsNothing);
    expect(fakeMapLayers(tester).polygons, isEmpty, reason: 'zu heißt: keine Maske mehr');
  });

  /// Ein Strich über die Karte, als geschlossene Schleife durch [pts].
  Future<void> stroke(WidgetTester tester, List<Offset> pts) async {
    final g = await tester.startGesture(pts.first);
    for (final p in pts.skip(1)) {
      await g.moveTo(p);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(tester);
  }

  int draftTiles(WidgetTester tester) {
    final text = (tester.widget(find.byKey(const ValueKey('area-draw-count'))) as Text).data!;
    return int.parse(RegExp(r'^(\d+) Kacheln').firstMatch(text)!.group(1)!);
  }

  testWidgets('Bereich zeichnen: Stift, Radierer, Rückgängig, Speichern — der Entwurf wird zum Bereich',
      (tester) async {
    await start(tester);
    // Weit draußen: Der Host des Tests endet bei Zoom 10, gezählt wird
    // bis dorthin — ein Strich soll mehrere 10er-Kacheln fassen.
    fakeMap(tester).move(const LatLng(48.0, 9.0), 8);
    await settle(tester);

    await tester.tap(find.byTooltip('Ebenen und Orte'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('offline-maps-tile')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('draw-area-tile')));
    await settle(tester);
    expect(find.text('Bereich zeichnen'), findsOneWidget);
    expect(find.text('Noch keine Kachel'), findsOneWidget);
    // Ohne Werkzeug liegt keine Zeichenfläche: Die Karte lässt sich
    // verschieben.
    expect(find.byKey(const ValueKey('area-draw-surface')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('area-draw-add')));
    await settle(tester);
    expect(find.byKey(const ValueKey('area-draw-surface')), findsOneWidget);
    expect(find.byKey(const ValueKey('area-draw-hint')), findsOneWidget);
    await stroke(tester, const [
      Offset(250, 120), Offset(450, 120), Offset(550, 170), Offset(450, 230), Offset(250, 230), Offset(250, 125),
    ]);
    // Nach dem Strich ist das Werkzeug weg und die Karte wieder frei.
    expect(find.byKey(const ValueKey('area-draw-surface')), findsNothing);
    final added = draftTiles(tester);
    expect(added, greaterThan(5));
    final draft = fakeMapLayers(tester).polygons.where((p) => p.fillColor == kAreaDraftFill);
    expect(draft, isNotEmpty, reason: 'der Entwurf steht grün auf der Karte');
    expect(fakeMapLayers(tester).polygons.first.fillColor, kOfflineDimColor,
        reason: 'unter der Abdunkelung liegt nichts, darüber der Entwurf');

    // Der Radierer umfährt die linke Hälfte.
    const erase = [Offset(240, 100), Offset(400, 100), Offset(400, 250), Offset(240, 250), Offset(240, 105)];
    await tester.tap(find.byKey(const ValueKey('area-draw-remove')));
    await settle(tester);
    await stroke(tester, erase);
    final erased = draftTiles(tester);
    expect(erased, lessThan(added));
    expect(erased, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('area-draw-undo')));
    await settle(tester);
    expect(draftTiles(tester), added);
    await tester.tap(find.byKey(const ValueKey('area-draw-remove')));
    await settle(tester);
    await stroke(tester, erase);
    expect(draftTiles(tester), erased);

    // Speichern: das bekannte Blatt, die gezeichnete Fläche vorgewählt,
    // die Größe gemessen.
    await tester.tap(find.byKey(const ValueKey('area-draw-save')));
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('area-choice-drawn')), findsOneWidget);
    expect(find.byKey(const ValueKey('area-size')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('area-name')), 'Gezeichnet');
    await tester.tap(find.byKey(const ValueKey('area-save')));
    await settle(tester, frames: 30);
    expect(find.textContaining('„Gezeichnet" gespeichert'), findsOneWidget);
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    final saved = (await store.list()).single;
    final shape = saved.shape as TileSetShape;
    expect(shape.zoom, kAreaShapeZoom);
    // Gespeichert ist der Entwurf — Zoom 8–10 aus den 13er-Kacheln.
    expect(shape.countTiles(maxZoom: 10), erased);
    // Und der Entwurf ist erledigt: Das Blatt zeigt wieder die Liste.
    expect(find.byKey(const ValueKey('draw-area-tile')), findsOneWidget);
    expect(find.byKey(ValueKey('offline-area-${saved.id}')), findsOneWidget);
    expect(fakeMapLayers(tester).polygons.where((p) => p.fillColor == kAreaDraftFill), isEmpty);
  });

  testWidgets('der Entwurf überlebt das Schließen des Blatts, das Werkzeug nicht; Verwerfen räumt ab',
      (tester) async {
    await start(tester);
    fakeMap(tester).move(const LatLng(48.0, 9.0), 11);
    await settle(tester);
    await tester.tap(find.byTooltip('Ebenen und Orte'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('offline-maps-tile')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('draw-area-tile')));
    await settle(tester);
    // Entlang der Trails als Ausgangspunkt.
    await tester.tap(find.byKey(const ValueKey('area-draw-trails')));
    await settle(tester);
    final along = draftTiles(tester);
    expect(along, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('area-draw-add')));
    await settle(tester);
    expect(find.byKey(const ValueKey('area-draw-surface')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('offline-maps-close')));
    await settle(tester);
    expect(find.byKey(const ValueKey('area-draw-surface')), findsNothing,
        reason: 'ohne Blatt kein Werkzeug — sonst stünde die Karte fest');
    expect(fakeMapLayers(tester).polygons, isEmpty);

    await tester.tap(find.byTooltip('Ebenen und Orte'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('offline-maps-tile')));
    await settle(tester);
    expect(find.text('Bereich zeichnen'), findsOneWidget);
    expect(draftTiles(tester), along);
    expect(find.byKey(const ValueKey('area-draw-surface')), findsNothing,
        reason: 'wiedergeöffnet steht die Karte nicht fest — das Werkzeug ging mit dem Blatt');

    await tester.tap(find.byKey(const ValueKey('area-draw-discard')));
    await settle(tester);
    expect(find.byKey(const ValueKey('draw-area-tile')), findsOneWidget);
    expect(fakeMapLayers(tester).polygons.where((p) => p.fillColor == kAreaDraftFill), isEmpty);
  });

  testWidgets('ohne Bereich ist alles abgedunkelt, und das Blatt sagt es', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('Ebenen und Orte'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('offline-maps-tile')));
    await settle(tester);
    expect(find.textContaining('Noch kein Bereich gespeichert'), findsOneWidget);
    final mask = fakeMapLayers(tester).polygons.single;
    expect(mask.holes, isEmpty);
  });

  testWidgets('Größe vorher, dann gespeichert, in der Liste, gelöscht', (tester) async {
    await start(tester);
    await openSaveSheet(tester);
    expect(find.text('Bereich für unterwegs speichern'), findsOneWidget);
    // Die Größe ist gemessen, nicht geschätzt: Kacheln und Bytes.
    final size = find.byKey(const ValueKey('area-size'));
    expect(size, findsOneWidget);
    expect((tester.widget(size) as Text).data, matches(RegExp(r'^\d+ Kacheln, \d+ kB$')));

    await tester.tap(find.byKey(const ValueKey('area-choice-trails')));
    await settle(tester, frames: 20);
    expect(find.byKey(const ValueKey('area-size')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('area-name')), 'Roots-Runde');
    await tester.tap(find.byKey(const ValueKey('area-save')));
    await settle(tester, frames: 30);
    expect(find.textContaining('„Roots-Runde" gespeichert'), findsOneWidget);
    // Der Vordergrunddienst lief als Download und ist wieder aus.
    expect(keepAlive.starts, 1);
    expect(keepAlive.running, isFalse);
    expect(keepAlive.titles.first, 'Bereich wird gespeichert');
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    final saved = (await store.list()).single;
    expect(saved.name, 'Roots-Runde');
    expect(saved.maxZoom, 10);
    expect(saved.build, '20260928');
    expect(saved.tiles, greaterThan(0));
    // Die Kacheln entlang des Trails (0.24.0), die Hülle umschließt ihn.
    expect(saved.shape, isA<TileSetShape>());
    expect(saved.bounds.south, lessThan(48.0));
    expect(saved.bounds.north, greaterThan(48.009));
    // Das Archiv liest der Leser beider Engines.
    final archive = await PmTilesArchive.fromBytes((await store.readArchive(saved.id))!);
    expect(archive.header.numberOfAddressedTiles, saved.tiles);

    await openTab(tester, 'Profil');
    await scrollTo(tester, find.text('Meine Bereiche'));
    await tester.tap(find.text('Meine Bereiche'));
    await settle(tester);
    expect(find.text('Roots-Runde'), findsOneWidget);
    expect(find.textContaining('Stand 28.09.2026'), findsOneWidget);
    expect(find.textContaining('Neuerer Kartenstand'), findsNothing);

    await tester.tap(find.byKey(ValueKey('area-delete-${saved.id}')));
    await settle(tester);
    await tester.tap(find.text('Löschen'));
    await settle(tester);
    expect(find.text('Roots-Runde'), findsNothing);
    expect(await store.list(), isEmpty);
    expect(await store.readArchive(saved.id), isNull);
  });

  testWidgets('ohne Kartenhost gibt es keinen Bereich, und das Blatt sagt es', (tester) async {
    await start(tester, host: false);
    await openSaveSheet(tester);
    expect(find.textContaining('Ohne Empfang lässt sich kein Bereich speichern'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.byKey(const ValueKey('area-save')));
    expect(save.onPressed, isNull);
  });

  testWidgets('ein älterer Bereich bekommt das Angebot, auf den neuen Stand zu kommen',
      (tester) async {
    await store.putArchive('old', _sourceBytes());
    await store.saveIndex([
      StoredArea(
        id: 'old',
        name: 'Alt',
        bounds: const AreaBounds(south: 47.99, west: 8.99, north: 48.02, east: 9.01),
        minZoom: 8,
        maxZoom: 10,
        build: '20260801',
        tiles: 5,
        bytes: 500,
        savedAt: DateTime.utc(2026, 8, 1),
      ),
    ]);
    await start(tester);
    await openTab(tester, 'Profil');
    await scrollTo(tester, find.text('Meine Bereiche'));
    await tester.tap(find.text('Meine Bereiche'));
    await settle(tester);
    expect(find.textContaining('Neuerer Kartenstand verfügbar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('area-update-old')));
    await settle(tester, frames: 40);
    final areas = await store.list();
    expect(areas.single.id, 'old', reason: 'ersetzt unter derselben Id');
    expect(areas.single.build, '20260928');
    expect(find.textContaining('Neuerer Kartenstand'), findsNothing);
  });
}
