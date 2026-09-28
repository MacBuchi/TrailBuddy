// Der Download eines Bereichs (Konzept 3.2), gegen ein Quellarchiv aus
// dem eigenen Schreiber: Der Plan zählt und misst, der Download holt
// über den `tiles()`-Strom, legt ein Archiv ab, das der Leser beider
// Engines öffnet, nimmt die Orte-Zellen mit, meldet Fortschritt, und ein
// Abbruch hinterlässt nichts.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/offline_areas/area_downloader.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';

const _manifest = MapManifest(
  file: 'dach-20260928.pmtiles',
  maxZoom: 10,
  bytes: 1,
  sourceBuild: '20260928',
);

/// Ein Quellarchiv: Zoom 8–10 über einem Rechteck, das größer ist als
/// der Bereich, den die Tests speichern.
Future<PmTilesArchive> _source() async {
  const wide = AreaBounds(south: 47.0, west: 10.0, north: 48.5, east: 12.5);
  final tiles = [
    for (final t in tilesCovering(wide, maxZoom: 10))
      TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('t${t.z}/${t.x}/${t.y}' * (1 + t.x % 4)))),
  ];
  final bytes = writePmTiles(
      tiles: tiles,
      tileCompression: Compression.none,
      bounds: const TileBounds(west: 10, south: 47, east: 12.5, north: 48.5));
  return PmTilesArchive.fromBytes(bytes);
}

const _bounds = AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7);

void main() {
  late PmTilesArchive source;
  late MemoryAreaStore store;
  late List<String> poiAsked;

  setUp(() async {
    source = await _source();
    store = MemoryAreaStore();
    poiAsked = [];
  });

  AreaDownloader make({PoiManifest? poiManifest}) => AreaDownloader(
        archive: source,
        manifest: _manifest,
        store: store,
        poiManifest: poiManifest,
        fetchPoiFile: (name) async {
          poiAsked.add(name);
          return name.endsWith('.water.json') ? '{"format":1,"pois":[]}' : null;
        },
        chunkSize: 7,
        now: () => DateTime.utc(2026, 9, 28, 19),
      );

  test('der Plan zählt die Kacheln des Hosts und summiert ihre Bytes', () async {
    final plan = await make().plan(const RectShape(_bounds));
    expect(plan.maxZoom, 10);
    expect(plan.tiles, isNotEmpty);
    var expected = 0;
    for (final t in plan.tiles) {
      expected += (await source.lookup(tileIdOf(t)))!.length;
    }
    expect(plan.bytes, expected);
    // Außerhalb der Quelle: keine Kachel, keine Bytes — kein Fehler.
    final sea = await make().plan(const RectShape(AreaBounds(south: 30, west: -30, north: 30.1, east: -29.9)));
    expect(sea.tiles, isEmpty);
    expect(sea.bytes, 0);
  });

  test('eine Kachelmenge holt genau ihre Kacheln und nur die Orte-Zellen der Kacheln', () async {
    // Zwei Trails weit auseinander: Das Archiv trägt zwei Streifen, die
    // Orte-Zellen sind die der Kacheln, nicht die des Rahmens dazwischen.
    final near = [for (var i = 0; i <= 5; i++) LatLng(47.90 + i * 0.005, 11.60)];
    final far = [for (var i = 0; i <= 5; i++) LatLng(47.90 + i * 0.005, 12.40)];
    final shape = AreaShape.alongLines([near, far])!;
    final hull = shape.hull;
    final allCells = poiCellsCovering(hull.south, hull.west, hull.north, hull.east);
    final poiManifest = PoiManifest(
      build: '20260928',
      prefix: 'pois-20260928',
      cells: {PoiGroup.water: allCells.toSet()},
    );
    final downloader = make(poiManifest: poiManifest);
    final plan = await downloader.plan(shape);
    expect(plan.shape, same(shape));
    expect(plan.tiles.toSet(), shape.tiles(maxZoom: 10).toSet(),
        reason: 'die Quelle deckt die Streifen ganz');
    final area = await downloader.download(plan, name: 'Zwei Streifen');
    expect(area.shape, isA<TileSetShape>());
    expect(area.tiles, plan.tiles.length);
    expect(area.poiFiles.length, shape.poiCells().length);
    expect(area.poiFiles.length, lessThan(allCells.length));
    // Der Index-Rundlauf behält die Form — „Aktualisieren" braucht sie.
    final back = StoredArea.fromJson(area.toJson());
    expect((back.shape as TileSetShape).keys, shape.keys);
    expect(back.bounds.west, closeTo(hull.west, 1e-9));
  });

  test('zu groß wird abgelehnt, bevor eine Kachel nachgeschlagen ist', () async {
    const dach = AreaBounds(south: 45.5, west: 5.5, north: 55.5, east: 17.5);
    final downloader = AreaDownloader(
        archive: source,
        manifest: const MapManifest(file: 'dach-20260928.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20260928'),
        store: store,
        fetchPoiFile: (_) async => null);
    expect(() => downloader.plan(const RectShape(dach)), throwsA(isA<AreaTooLarge>()));
  });

  test('der Download legt ein lesbares Archiv ab, samt Orte-Zellen und Index', () async {
    final cells = poiCellsCovering(_bounds.south, _bounds.west, _bounds.north, _bounds.east);
    final poiManifest = PoiManifest(
      build: '20260928',
      prefix: 'pois-20260928',
      cells: {PoiGroup.water: cells.toSet(), PoiGroup.food: {cells.first}},
    );
    final downloader = make(poiManifest: poiManifest);
    final plan = await downloader.plan(const RectShape(_bounds));
    final progress = <AreaProgress>[];
    final area = await downloader.download(plan, name: 'Isartrails', onProgress: progress.add);

    expect(area.name, 'Isartrails');
    expect(area.tiles, plan.tiles.length);
    expect(area.build, '20260928');
    expect(area.minZoom, kAreaMinZoom);
    expect(area.maxZoom, 10);
    expect(area.savedAt, DateTime.utc(2026, 9, 28, 19));
    expect(area.poiBuild, '20260928');
    // Wasser für jede Zelle, Einkehr nur für die eine; die 404 fehlen.
    expect(area.poiFiles, [
      for (final c in cells) poiCellFileName(c, PoiGroup.water),
    ]..sort());
    expect(poiAsked, hasLength(cells.length + 1));
    expect(await store.readPoiFile(poiCellFileName(cells.first, PoiGroup.water)), contains('"pois"'));

    // Das Archiv: jede geplante Kachel, Byte für Byte wie die Quelle.
    final stored = await PmTilesArchive.fromBytes((await store.readArchive(area.id))!);
    expect(stored.header.numberOfAddressedTiles, plan.tiles.length);
    for (final t in plan.tiles) {
      final id = tileIdOf(t);
      expect((await stored.tile(id)).compressedBytes(), (await source.tile(id)).compressedBytes());
    }
    expect(area.bytes, greaterThan(0));
    expect((await store.list()).single.id, area.id);

    // Der Fortschritt: Kacheln, dann Orte, dann Schreiben, monoton.
    expect(progress.first.phase, AreaPhase.tiles);
    expect(progress.where((p) => p.phase == AreaPhase.tiles).last.done, plan.tiles.length);
    expect(progress.any((p) => p.phase == AreaPhase.pois), isTrue);
    expect(progress.last.phase, AreaPhase.writing);
  });

  test('ein zweiter Bereich mit derselben Id ersetzt den ersten im Index', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    await downloader.download(plan, name: 'A', id: 'x');
    await downloader.download(plan, name: 'B', id: 'x');
    final areas = await store.list();
    expect(areas.map((a) => a.name), ['B']);
  });

  test('Abbruch: nichts geschrieben, nichts im Index', () async {
    final downloader = make();
    final plan = await downloader.plan(const RectShape(_bounds));
    var calls = 0;
    await expectLater(
        downloader.download(plan, name: 'Abbruch', isCancelled: () => ++calls > 1),
        throwsA(isA<AreaCancelled>()));
    expect(store.archives, isEmpty);
    expect(await store.list(), isEmpty);
  });
}
