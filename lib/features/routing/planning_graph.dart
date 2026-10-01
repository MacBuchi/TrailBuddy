// Der Graph für eine Planung — EIN Weg für den Rundenplaner und den Weg zu
// einem Trail oder Punkt: Bereiche, Höhen, Wege aus den Kacheln, darauf
// die Trails des Netzes (Richtung, Verbinder; `trail_overlay.dart`).
//
// **Gerechnet wird über die Kacheln, die da sind** (seit 0.74.0). Bis
// 0.73.0 verlangte die Planung, dass das GANZE Rechteck um Start und Trails
// gespeichert ist — bei einem Bereich „Entlang meiner Trails" (Kacheln nur
// in 1 km um die Trails) war das praktisch nie der Fall, und das Blatt sagte
// „nur zum Teil gedeckt", obwohl jeder Weg dazwischen bekannt war
// (Feldbericht: „teils hat es nicht funktioniert ohne sichtbaren Grund").
// Jetzt plant die Suche über die gefundenen Kacheln; ein Weg außerhalb kann
// kürzer sein, und das Blatt sagt das ([PlanningGraph.partial]). Ohne eine
// einzige Kachel gibt es weiter keinen Plan.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/line_geometry.dart';
import '../../models/trail.dart';
import '../offline_areas/area_providers.dart';
import '../offline_areas/area_store.dart';
import '../offline_areas/height_tiles.dart';
import '../rides/road_index.dart' show RoadCoverage;
import '../trails/trail_providers.dart';
import 'loop_planner.dart' show graphTrailsOf;
import 'road_graph.dart';
import 'road_graph_loader.dart';
import 'trail_head_route.dart' show kTrailHeadMarginM;
import 'trail_overlay.dart';

class PlanningGraph {
  const PlanningGraph({
    required this.graph,
    required this.coverage,
    required this.tilesFound,
    required this.tilesNeeded,
  });

  /// Null: keine einzige Kachel im Rahmen — kein Plan.
  final RoadGraph? graph;
  final RoadCoverage coverage;
  final int tilesFound;
  final int tilesNeeded;

  /// Geplant über einen Teil der Kacheln: Ein Weg außerhalb kann kürzer
  /// sein, und das Blatt sagt es.
  bool get partial => graph != null && coverage == RoadCoverage.partial;
}

/// Lädt den Graphen für den Rahmen um [points] (plus [kTrailHeadMarginM])
/// und legt die sichtbaren Trails darauf. Wirft nie: Ein Fehler beim Lesen
/// wird gemeldet und ergibt „keine Kachel".
Future<PlanningGraph> loadPlanningGraph(Ref ref, LatBox box) async {
  List<StoredArea> areas;
  try {
    areas = await ref.read(storedAreasProvider.future);
  } catch (_) {
    areas = const [];
  }
  HeightReader? heights;
  try {
    heights = await ref.read(areaHeightReaderProvider.future);
  } catch (e, s) {
    // Ohne Höhen rechnet die Suche flach und sagt es; der Weg steht trotzdem.
    logError('Höhen für die Planung öffnen', e, s);
  }
  final store = ref.read(areaStoreProvider);
  final open = ref.read(areaArchiveOpenerProvider);
  RoadGraphLoadResult roads;
  try {
    roads = await loadRoadGraph(
      areas: areas,
      box: box,
      open: (a) => open(store, a),
      heights: heights,
      marginM: kTrailHeadMarginM,
      requireComplete: false,
    );
  } catch (e, s) {
    logError('Wege für die Planung lesen', e, s);
    return const PlanningGraph(graph: null, coverage: RoadCoverage.none, tilesFound: 0, tilesNeeded: 0);
  }
  final graph = roads.graph;
  if (graph != null) {
    final trails = ref.read(trailsProvider).valueOrNull ?? const <Trail>[];
    final near = [
      for (final t in trails)
        if (t.points.length >= 2 && LatBox.of(t.points).near(box, kTrailHeadMarginM)) t,
    ];
    applyTrails(graph, graphTrailsOf(near));
  }
  return PlanningGraph(
    graph: graph,
    coverage: roads.coverage,
    tilesFound: roads.tilesFound,
    tilesNeeded: roads.tilesNeeded,
  );
}

/// Ein Provider, damit die Blätter [loadPlanningGraph] mit IHREM `ref`
/// rufen können (`WidgetRef` ist kein `Ref`) und Tests die Naht haben.
final planningGraphLoaderProvider = Provider<Future<PlanningGraph> Function(LatBox box)>(
    (ref) => (box) => loadPlanningGraph(ref, box));
