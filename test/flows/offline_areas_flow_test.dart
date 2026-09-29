// Bereiche speichern (Konzept-Schritt 3), seit 0.27.0 über die
// Werkzeugleiste „Ebenen": Der Ebenen-Knopf öffnet sie (links), die Karte
// dunkelt ab, was nicht liegt; Ausschnitt, Fläche dazu/weg und die Trails
// füllen einen Entwurf; „Speichern" misst Größe und Orte, fragt und lädt;
// X, Ebenen-Knopf und Zurück schließen — mit Rückfrage bei Änderungen.
// Dazu „Meine Bereiche" (Liste, Löschen, Aktualisieren).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/map/map_screen.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/map/poi.dart';
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

  /// Zwei Orte in jeder Wasser-Zelle rund um den Trail.
  const twoSprings = '{"format":1,"pois":['
      '{"id":"n1","kind":"spring","lat":48.0,"lng":9.0},'
      '{"id":"n2","kind":"spring","lat":48.001,"lng":9.001}]}';

  Future<void> start(WidgetTester tester, {bool host = true, bool pois = false}) async {
    final source = _sourceBytes();
    final cells = poiCellsCovering(47.5, 8.5, 48.5, 9.5);
    await pumpApp(tester, backend,
        trails: trails,
        areaStore: store,
        keepAlive: keepAlive,
        extraOverrides: [
          mapManifestLoaderProvider.overrideWithValue(() async => host ? _manifest : null),
          areaSourceOpenerProvider.overrideWithValue((_) => PmTilesArchive.fromBytes(source)),
          areaPoiManifestLoaderProvider.overrideWithValue(() async => pois
              ? PoiManifest(build: '20260928', prefix: 'pois-20260928', cells: {PoiGroup.water: cells.toSet()})
              : null),
          areaPoiFileLoaderProvider.overrideWithValue((_, _) async => twoSprings),
        ]);
    await settle(tester, frames: 20);
  }

  Future<void> openTools(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Ebenen und Orte'));
    await settle(tester);
  }

  Future<void> tapRail(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

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
    return text == '–' ? 0 : int.parse(text);
  }

  Iterable<MapViewPolygon> draftRects(WidgetTester tester) =>
      fakeMapLayers(tester).polygons.where((p) => p.fillColor == kAreaDraftFill);

  StoredArea oldArea({String build = '20260928'}) => StoredArea(
        id: 'old',
        name: 'Alt',
        bounds: const AreaBounds(south: 47.99, west: 8.99, north: 48.02, east: 9.01),
        minZoom: 8,
        maxZoom: 10,
        build: build,
        tiles: 5,
        bytes: 500,
        savedAt: DateTime.utc(2026, 9, 28),
      );

  testWidgets('Knöpfe rechts, Werkzeugleiste links — Maßstab und Quellenhinweis bleiben frei',
      (tester) async {
    await start(tester);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getCenter(find.byKey(const ValueKey('layers-button'))).dx, greaterThan(size.width / 2));
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing);
    await openTools(tester);
    final rail = tester.getRect(find.byKey(const ValueKey('offline-tool-rail')));
    expect(rail.center.dx, lessThan(size.width / 2));
    expect(rail.left, lessThan(24));
    // Unten links stehen Maßstab und Quellenhinweis: die Leiste endet
    // darüber (die Reiterleiste liegt noch unter der Karte).
    final map = tester.getRect(find.byType(MapScreen));
    expect(rail.bottom, lessThanOrEqualTo(map.bottom - 64));
    expect(rail.top, greaterThanOrEqualTo(map.top + 56));
    // Und jeder Knopf ist erreichbar, ohne zu scrollen.
    expect(tester.getRect(find.byKey(const ValueKey('offline-maps-close'))).bottom, lessThanOrEqualTo(rail.bottom));
  });

  testWidgets('Ebenen dunkelt ab, gespeicherte Kacheln bleiben hell — beim Zoomen DIESELBEN, bis zum Schließen',
      (tester) async {
    await store.putArchive('old', _sourceBytes());
    await store.saveIndex([oldArea()]);
    await start(tester);
    expect(fakeMapLayers(tester).polygons, isEmpty, reason: 'ohne Leiste keine Maske');

    await openTools(tester);
    final mask = fakeMapLayers(tester).polygons.single;
    expect(mask.fillColor, kOfflineDimColor);
    expect(mask.holes, isNotEmpty, reason: 'der Bereich liegt im Ausschnitt');
    // Die Löcher sind die Kacheln des Bereichs bei SEINEM Zoom (10).
    Set<TileXYZ> covered(List<List<LatLng>> holes) => {
          for (final h in holes)
            ...tilesCovering(
                AreaBounds(
                    south: h[2].latitude + 1e-7,
                    west: h[0].longitude + 1e-7,
                    north: h[0].latitude - 1e-7,
                    east: h[1].longitude - 1e-7),
                minZoom: 10,
                maxZoom: 10),
        };
    final before = covered(mask.holes);
    expect(before, oldArea().shape.tilesWithin(offlineOverlayBox(fakeMap(tester).camera.bounds), 10).toSet());

    // Herauszoomen: dieselben Kacheln, keine gröberen Eltern (0.27.0).
    fakeMap(tester).move(fakeMap(tester).camera.center, 9);
    await settle(tester);
    expect(covered(fakeMapLayers(tester).polygons.single.holes), before);

    // Ohne Änderung schließt das X ohne Rückfrage.
    await tapRail(tester, 'offline-maps-close');
    expect(find.text('Entwurf verwerfen?'), findsNothing);
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing);
    expect(fakeMapLayers(tester).polygons, isEmpty, reason: 'zu heißt: keine Maske mehr');
  });

  testWidgets('ohne Bereich ist alles abgedunkelt', (tester) async {
    await start(tester);
    await openTools(tester);
    final mask = fakeMapLayers(tester).polygons.single;
    expect(mask.holes, isEmpty);
    expect(draftTiles(tester), 0);
    final save = tester.widget<IconButton>(find.byKey(const ValueKey('area-draw-save')));
    expect(save.onPressed, isNull, reason: 'ohne Kachel nichts zu speichern');
  });

  testWidgets('Schnappschuss, Speichern mit Größe und Zahl der Orte, dann in der Liste und gelöscht',
      (tester) async {
    await start(tester, pois: true);
    fakeMap(tester).move(const LatLng(48.0, 9.0), 12);
    await settle(tester);
    await openTools(tester);
    await tapRail(tester, 'rail-snapshot');
    expect(draftTiles(tester), greaterThan(0));
    expect(draftRects(tester), isNotEmpty, reason: 'der Entwurf steht grün auf der Karte');

    await tapRail(tester, 'area-draw-save');
    await settle(tester, frames: 20);
    expect(find.text('Bereich speichern?'), findsOneWidget);
    final size = (tester.widget(find.byKey(const ValueKey('area-size'))) as Text).data!;
    expect(size, matches(RegExp(r'^\d+ kB · \d+ Kacheln · \d+ Orte$')));
    // Zwei Orte je Zelle, so viele Zellen wie der Ausschnitt berührt.
    final orte = int.parse(RegExp(r'(\d+) Orte').firstMatch(size)!.group(1)!);
    expect(orte, isPositive);
    expect(orte.isEven, isTrue);

    await tester.enterText(find.byKey(const ValueKey('area-name')), 'Roots-Runde');
    await tester.tap(find.byKey(const ValueKey('area-save')));
    await settle(tester, frames: 30);
    expect(find.text('Bereich speichern?'), findsNothing, reason: 'fertig heißt: Dialog zu');
    expect(find.textContaining('„Roots-Runde" gespeichert'), findsOneWidget);
    expect(keepAlive.starts, 1);
    expect(keepAlive.running, isFalse);

    final saved = (await store.list()).single;
    expect(saved.name, 'Roots-Runde');
    expect(saved.maxZoom, 10);
    expect(saved.shape, isA<TileSetShape>());
    expect(saved.poiFiles, isNotEmpty);
    final archive = await PmTilesArchive.fromBytes((await store.readArchive(saved.id))!);
    expect(archive.header.numberOfAddressedTiles, saved.tiles);
    // Der Entwurf ist erledigt, die Leiste bleibt offen, die neuen
    // Kacheln sind hell.
    expect(draftTiles(tester), 0);
    expect(draftRects(tester), isEmpty);
    expect(fakeMapLayers(tester).polygons.single.holes, isNotEmpty);

    // Verwalten: Karte mit Zahnrad → „Meine Bereiche".
    await tapRail(tester, 'manage-areas');
    expect(find.text('Roots-Runde'), findsOneWidget);
    expect(find.textContaining('Stand 28.09.2026'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('area-delete-${saved.id}')));
    await settle(tester);
    await tester.tap(find.text('Löschen'));
    await settle(tester);
    expect(find.text('Roots-Runde'), findsNothing);
    expect(await store.list(), isEmpty);
  });

  testWidgets('ohne Kartenhost gibt es keinen Bereich, und der Dialog sagt es', (tester) async {
    await start(tester, host: false);
    fakeMap(tester).move(const LatLng(48.0, 9.0), 12);
    await settle(tester);
    await openTools(tester);
    await tapRail(tester, 'rail-snapshot');
    await tapRail(tester, 'area-draw-save');
    await settle(tester, frames: 20);
    expect(find.textContaining('Ohne Empfang lässt sich kein Bereich speichern'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.byKey(const ValueKey('area-save')));
    expect(save.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('area-save-cancel')));
    await settle(tester);
    expect(draftTiles(tester), greaterThan(0), reason: 'Abbrechen lässt den Entwurf stehen');
  });

  testWidgets('Stift, Radierer, Rückgängig — und Speichern macht den Entwurf zum Bereich', (tester) async {
    await start(tester);
    // Weit draußen: Der Host des Tests endet bei Zoom 10, gezählt wird
    // bis dorthin — ein Strich soll mehrere 10er-Kacheln fassen.
    fakeMap(tester).move(const LatLng(48.0, 9.0), 8);
    await settle(tester);
    await openTools(tester);
    expect(find.byKey(const ValueKey('area-draw-surface')), findsNothing,
        reason: 'ohne Werkzeug lässt sich die Karte verschieben');

    await tapRail(tester, 'area-draw-add');
    expect(find.byKey(const ValueKey('area-draw-surface')), findsOneWidget);
    await stroke(tester, const [
      Offset(250, 120), Offset(450, 120), Offset(550, 170), Offset(450, 230), Offset(250, 230), Offset(250, 125),
    ]);
    expect(find.byKey(const ValueKey('area-draw-surface')), findsNothing,
        reason: 'nach dem Strich ist die Karte wieder frei');
    final added = draftTiles(tester);
    expect(added, greaterThan(5));
    expect(draftRects(tester), isNotEmpty);

    const erase = [Offset(240, 100), Offset(400, 100), Offset(400, 250), Offset(240, 250), Offset(240, 105)];
    await tapRail(tester, 'area-draw-remove');
    await stroke(tester, erase);
    final erased = draftTiles(tester);
    expect(erased, lessThan(added));
    expect(erased, greaterThan(0));

    await tapRail(tester, 'area-draw-undo');
    expect(draftTiles(tester), added);
    await tapRail(tester, 'area-draw-remove');
    await stroke(tester, erase);
    expect(draftTiles(tester), erased);

    await tapRail(tester, 'area-draw-save');
    await settle(tester, frames: 20);
    await tester.tap(find.byKey(const ValueKey('area-save')));
    await settle(tester, frames: 30);
    final saved = (await store.list()).single;
    expect((saved.shape as TileSetShape).countTiles(maxZoom: 10), erased);
    expect(draftTiles(tester), 0);
  });

  testWidgets('Schließen mit Änderungen fragt nach: X, Ebenen-Knopf und Zurück-Taste', (tester) async {
    await start(tester);
    await openTools(tester);
    await tapRail(tester, 'area-draw-trails');
    final along = draftTiles(tester);
    expect(along, greaterThan(0));

    // X: „Weiter bearbeiten" lässt alles offen.
    await tapRail(tester, 'offline-maps-close');
    expect(find.text('Entwurf verwerfen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draft-keep')));
    await settle(tester);
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsOneWidget);
    expect(draftTiles(tester), along);

    // Zurück-Taste: dieselbe Frage statt die App zu verlassen.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Entwurf verwerfen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draft-keep')));
    await settle(tester);
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsOneWidget);

    // Ein armiertes Werkzeug geht beim Schließen mit.
    await tapRail(tester, 'area-draw-add');
    expect(find.byKey(const ValueKey('area-draw-surface')), findsOneWidget);

    // Ebenen-Knopf: verwerfen.
    await tester.tap(find.byTooltip('Ebenen und Orte'));
    await settle(tester);
    expect(find.text('Entwurf verwerfen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draft-discard')));
    await settle(tester);
    expect(find.byKey(const ValueKey('offline-tool-rail')), findsNothing);
    expect(find.byKey(const ValueKey('area-draw-surface')), findsNothing);
    expect(fakeMapLayers(tester).polygons, isEmpty);

    // Wieder geöffnet: ein leerer Entwurf, kein Werkzeug.
    await openTools(tester);
    expect(draftTiles(tester), 0);
    expect(find.byKey(const ValueKey('area-draw-surface')), findsNothing);
  });

  testWidgets('ein älterer Bereich bekommt das Angebot, auf den neuen Stand zu kommen',
      (tester) async {
    await store.putArchive('old', _sourceBytes());
    await store.saveIndex([oldArea(build: '20260801')]);
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
