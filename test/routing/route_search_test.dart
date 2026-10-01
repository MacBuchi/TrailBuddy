// Die Suche: begrenzter Dijkstra, A* zum Ziel, Einbahn, Klassenaufschlag
// (der Forstweg gewinnt gegen die kürzere Bundesstraße), Budgetgrenze,
// und die Pfad-Zusammenfassung in beide Richtungen — dazu der Graph aus
// Bereichen über `loadRoadGraph` (vollständig, teilweise, gar nicht).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/map/pmtiles_tile_provider.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/height_tiles.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:trailbuddy/features/rides/road_index.dart' show RoadCoverage;
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/road_graph_loader.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';

import '../fakes/fake_tiles.dart';

/// Meter → Grad über DIESELBE Projektion wie der Graph, sonst sind
/// „1000 m" im Test 998,9 m im Graphen.
List<LatLng> _m(List<(double, double)> xy, {double lat0 = 47.5, double lon0 = 11.5}) {
  final proj = FlatProjection(lat0);
  final o = proj.xy(LatLng(lat0, lon0));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

WayLine _way(List<(double, double)> xy, {WayClass cls = WayClass.forstweg, bool oneway = false}) =>
    WayLine(cls: cls, oneway: oneway, points: _m(xy));

void main() {
  const bio = RiderProfile.bio;

  test('der Forstweg gewinnt gegen die kürzere Bundesstraße, und der Pfad ist die Linie', () {
    // Start (0,0) → Ziel (1000,0): Bundesstraße direkt (1 km, ×4), Forstweg
    // über (500, 300) (≈ 1,17 km, ×1).
    final g = buildRoadGraph([
      _way([(0, 0), (1000, 0)], cls: WayClass.bundesstrasse),
      _way([(0, 0), (500, 300), (1000, 0)]),
    ], lat0: 47.5).graph;
    final src = g.attach(_m([(0, 0)]).single)!, dst = g.attach(_m([(1000, 0)]).single)!;
    final r = shortestPath(g, src, dst, bio)!;
    expect(g.edges[r.edges.single].cls, WayClass.forstweg);
    final s = summarizePath(g, r.edges, src, bio);
    expect(s.lengthM, closeTo(2 * math.sqrt(500 * 500 + 300 * 300), 1));
    expect(s.mix.keys, [WayClass.forstweg]);
    expect(s.points.first.longitude, closeTo(_m([(0, 0)]).single.longitude, 1e-9));
    expect(s.points.last.longitude, closeTo(_m([(1000, 0)]).single.longitude, 1e-9));
    expect(s.heightsComplete, isFalse, reason: 'keine Höhen gelesen');
    expect(s.hikingM, 0);
    // Zeit = Strecke / 15 km/h ohne Höhen.
    expect(s.timeS, closeTo(s.lengthM / (15 / 3.6), 1e-6));
  });

  test('Einbahn: hin über die Straße, zurück nur über den Umweg', () {
    final g = buildRoadGraph([
      _way([(0, 0), (1000, 0)], cls: WayClass.nebenstrasse, oneway: true),
      _way([(0, 0), (500, 400), (1000, 0)]),
    ], lat0: 47.5).graph;
    final a = g.attach(_m([(0, 0)]).single)!, b = g.attach(_m([(1000, 0)]).single)!;
    expect(g.edges[shortestPath(g, a, b, bio)!.edges.single].cls, WayClass.nebenstrasse);
    expect(g.edges[shortestPath(g, b, a, bio)!.edges.single].cls, WayClass.forstweg);
  });

  test('das Budget begrenzt die Reichweite; Anstieg wird mitgezählt', () {
    final g = buildRoadGraph([
      _way([(0, 0), (1000, 0), (2000, 0), (3000, 0)]),
    ], lat0: 47.5).graph;
    final split = [for (final x in [0, 1000, 2000, 3000]) g.attach(_m([(x.toDouble(), 0)]).single)!];
    for (final e in g.edges) {
      e
        ..gain = 100
        ..loss = 0
        ..hasHeights = true;
    }
    // Je Kante 1 km und 100 hm: 1040 s. Mit 2500 s Budget sind zwei
    // Kanten drin, die dritte nicht.
    final r = dijkstra(g, split[0], bio, limit: 2500);
    expect(r.reached(split[2]), isTrue);
    expect(r.reached(split[3]), isFalse);
    expect(r.climb[split[2]], closeTo(200, 1e-9));
    expect(r.dist[split[2]], closeTo(2080, 1e-6));
    // Zurück: bergab, nur Strecke, 25 km/h.
    final back = dijkstra(g, split[3], bio);
    expect(back.dist[split[0]], closeTo(3 * 1000 / (25 / 3.6), 1e-6));
    expect(back.climb[split[0]], 0);
    final s = summarizePath(g, back.pathTo(split[0])!, split[3], bio);
    expect(s.gainM, 0);
    expect(s.lossM, closeTo(300, 1e-9));
    expect(s.heightsComplete, isTrue);
  });

  test('kein Weg: null', () {
    final g = buildRoadGraph([_way([(0, 0), (100, 0)]), _way([(500, 0), (600, 0)])], lat0: 47.5).graph;
    expect(shortestPath(g, 0, 2, bio), isNull);
    expect(dijkstra(g, 0, bio).pathTo(2), isNull);
  });

  group('loadRoadGraph', () {
    // Eine z13-Kachel um 48,0° N / 9,0° O mit einem Forstweg quer durch
    // und einem Trail-Ende daneben; ein Bereich trägt sie.
    final t = tileAt(48.0, 9.0, 13);
    final tile = mvtTile([
      road([(0, 2048), (4096, 2048)], 'path', kindDetail: 'track'),
      road([(2048, 0), (2048, 4096)], 'minor_road', kindDetail: 'residential'),
    ]);
    final bounds = tileBounds(13, t.x, t.y);
    final box = LatBox(bounds.south + 1e-4, bounds.west + 1e-4, bounds.north - 1e-4, bounds.east - 1e-4);

    Future<MemoryAreaStore> seed({required bool withTile}) async {
      final store = MemoryAreaStore();
      final tiles = [
        if (withTile) TileToWrite(13, t.x, t.y, tile),
        TileToWrite(12, t.x >> 1, t.y >> 1, Uint8List.fromList([1])),
      ];
      final bytes = writePmTiles(
        tiles: tiles,
        tileCompression: Compression.none,
        bounds: TileBounds(west: bounds.west, south: bounds.south, east: bounds.east, north: bounds.north),
      );
      await store.putArchive('a', bytes);
      await store.saveIndex([
        StoredArea(
          id: 'a',
          name: 'a',
          bounds: bounds,
          minZoom: 12,
          maxZoom: 13,
          build: '20260928',
          tiles: tiles.length,
          bytes: bytes.length,
          savedAt: DateTime.utc(2026, 10, 1),
        ),
      ]);
      return store;
    }

    Future<PmTilesVectorTileProvider?> Function(StoredArea) openFrom(MemoryAreaStore store) => (a) async {
          final bytes = await store.readArchive(a.id);
          return bytes == null ? null : PmTilesVectorTileProvider.openBytes(bytes);
        };

    test('vollständig: der Graph steht, die Kreuzung ist geteilt, Höhen aus dem Leser', () async {
      final store = await seed(withTile: true);
      final values = [for (var i = 0; i < kHeightGrid * kHeightGrid; i++) 700];
      final heights = HeightReader([
        MemoryHeightSource({(x: t.x, y: t.y): HeightTile(Int16List.fromList(values))}),
      ]);
      final r = await loadRoadGraph(areas: await store.list(), box: box, open: openFrom(store), heights: heights);
      expect(r.coverage, RoadCoverage.complete);
      expect(r.tilesFound, 1);
      expect(r.crossings, 1);
      final g = r.graph!;
      expect(g.edges, hasLength(4));
      expect(r.edgesWithoutHeights, 0);
      expect(g.components(), hasLength(1));
      // Von der West- zur Ostkante über die Kreuzung.
      final src = g.attach(LatLng((bounds.north + bounds.south) / 2, bounds.west))!;
      final dst = g.attach(LatLng((bounds.north + bounds.south) / 2, bounds.east))!;
      final p = shortestPath(g, src, dst, bio)!;
      expect(p.edges, hasLength(2));
      expect(summarizePath(g, p.edges, src, bio).gainM, 0);
    });

    test('ohne Höhenleser zählt jede Kante als ohne Höhe', () async {
      final store = await seed(withTile: true);
      final r = await loadRoadGraph(areas: await store.list(), box: box, open: openFrom(store));
      expect(r.coverage, RoadCoverage.complete);
      expect(r.edgesWithoutHeights, r.graph!.edges.length);
    });

    test('fehlt die Kachel, gibt es keinen Graphen — und ohne Bereich auch nicht', () async {
      final store = await seed(withTile: false);
      final r = await loadRoadGraph(areas: await store.list(), box: box, open: openFrom(store));
      expect(r.coverage, RoadCoverage.none);
      expect(r.graph, isNull);
      final empty = await loadRoadGraph(areas: const [], box: box, open: openFrom(store));
      expect(empty.coverage, RoadCoverage.none);
      // Ein Rahmen über zwei Kacheln, nur eine da: teilweise, kein Graph.
      final full = await seed(withTile: true);
      final wide = LatBox(bounds.south + 1e-4, bounds.west + 1e-4, bounds.north - 1e-4, bounds.east + 0.01);
      final partial = await loadRoadGraph(areas: await full.list(), box: wide, open: openFrom(full));
      expect(partial.coverage, RoadCoverage.partial);
      expect(partial.graph, isNull);
      expect(partial.tilesNeeded, 2);
      expect(partial.tilesFound, 1);
    });
  });
}
