// Der Wegegraph aus den gespeicherten Bereichen (Konzept-Routing 2.7):
// alle z13-Kacheln, die ein Rahmen berührt, aus den Bereichen, die sie
// tragen — derselbe Weg wie `loadRoads` für das Zerlege-Blatt, mit
// derselben Ehrlichkeit: `partial` heißt „nicht planbar", nicht „ein
// halber Plan". Danach die Höhen je Kante aus den Höhenkacheln der
// Bereiche (`HeightReader`); Kanten ohne Höhe bleiben flach und werden
// gezählt.
import 'package:vector_map_tiles/vector_map_tiles.dart' show ProviderException, TileIdentity;

import '../../core/line_geometry.dart';
import '../map/pmtiles_tile_provider.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/height_tiles.dart';
import '../rides/road_index.dart' show RoadCoverage;
import 'road_graph.dart';

typedef RoadGraphLoadResult = ({
  RoadGraph? graph,
  RoadCoverage coverage,
  int tilesNeeded,
  int tilesFound,
  int joins,
  int crossings,
  int edgesWithoutHeights,
});

/// Baut den Graphen für [box] (in Grad, mit einem Rand von
/// [marginM] Metern) aus [areas]. [open] liefert je Bereich die
/// Kachelquelle, [heights] die Höhen — null heißt: alle Kanten flach.
Future<RoadGraphLoadResult> loadRoadGraph({
  required List<StoredArea> areas,
  required LatBox box,
  required Future<PmTilesVectorTileProvider?> Function(StoredArea area) open,
  HeightReader? heights,
  double marginM = 0,
}) async {
  final dLat = marginM / 111320.0;
  final bounds = AreaBounds(
    south: box.s - dLat,
    west: box.w - dLat * 2,
    north: box.n + dLat,
    east: box.e + dLat * 2,
  );
  final tiles = tilesCovering(bounds, minZoom: kRoadGraphZoom, maxZoom: kRoadGraphZoom);
  final candidates = [
    for (final a in areas)
      if (a.maxZoom >= kRoadGraphZoom && a.bounds.intersects(bounds)) a,
  ];
  RoadGraphLoadResult none(RoadCoverage c, int found) =>
      (graph: null, coverage: c, tilesNeeded: tiles.length, tilesFound: found, joins: 0, crossings: 0, edgesWithoutHeights: 0);
  if (candidates.isEmpty || tiles.isEmpty) return none(RoadCoverage.none, 0);
  final opened = <PmTilesVectorTileProvider>[];
  final lines = <WayLine>[];
  var found = 0;
  try {
    for (final a in candidates) {
      try {
        final p = await open(a);
        if (p != null) opened.add(p);
      } catch (_) {
        // Ein Bereich, der nicht aufgeht, trägt keine Kacheln bei; die
        // Zählung unten sagt dann „nicht gedeckt".
      }
    }
    for (final t in tiles) {
      for (final p in opened) {
        try {
          final bytes = await p.provide(TileIdentity(t.z, t.x, t.y));
          lines.addAll(wayLinesFromTile(bytes, z: t.z, x: t.x, y: t.y));
          found++;
          break;
        } on ProviderException {
          continue;
        }
      }
    }
  } finally {
    for (final p in opened) {
      await p.close();
    }
  }
  if (found == 0) return none(RoadCoverage.none, 0);
  if (found < tiles.length) return none(RoadCoverage.partial, found);
  final build = buildRoadGraph(lines, lat0: (box.s + box.n) / 2);
  if (heights != null) await addClimbs(build.graph, heights);
  return (
    graph: build.graph,
    coverage: RoadCoverage.complete,
    tilesNeeded: tiles.length,
    tilesFound: found,
    joins: build.joins,
    crossings: build.crossings,
    edgesWithoutHeights: heights == null ? build.graph.edges.length : build.graph.edgesWithoutHeights,
  );
}
