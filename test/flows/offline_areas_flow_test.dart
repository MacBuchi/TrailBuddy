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
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_keep_alive.dart';
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
    await tester.tap(find.byKey(const ValueKey('save-area-tile')));
    await settle(tester, frames: 20);
  }

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
    // Der Rahmen um die Trails, mit Rand.
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
