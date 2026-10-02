// Der Rechen-Isolate des Planers (#188): rechnet dasselbe wie an Ort und
// Stelle, schickt jeden Graphen nur einmal, lässt den eigenen Graphen
// unverändert, meldet Fehler und erholt sich nach dem Freigeben.
//
// Echte Isolate — deshalb `test`, nicht `testWidgets` (in der Zone mit
// falscher Uhr antwortet keiner; der Harness nimmt die Inline-Fassung).
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner.dart';
import 'package:trailbuddy/features/routing/loop_plan_runner_io.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

List<LatLng> _m(List<(double, double)> xy) {
  final proj = FlatProjection(47.5);
  final o = proj.xy(const LatLng(47.5, 11.5));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

/// Das Quadrat aus `loop_planner_test.dart`: 1 km Forstweg je Kante,
/// 100 hm hinauf und hinunter.
RoadGraph _square() {
  WayLine way(List<(double, double)> xy) => WayLine(cls: WayClass.forstweg, oneway: false, points: _m(xy));
  final g = buildRoadGraph([
    way([(0, 0), (0, 1000)]),
    way([(0, 1000), (1000, 1000)]),
    way([(1000, 1000), (1000, 0)]),
    way([(1000, 0), (0, 0)]),
  ], lat0: 47.5).graph;
  for (final e in g.edges) {
    final dy = g.nodes[e.b].y - g.nodes[e.a].y;
    if (dy.abs() > 1) {
      e.gain = dy > 0 ? 100 : 0;
      e.loss = dy > 0 ? 0 : 100;
    }
    e.hasHeights = true;
  }
  return g;
}

PoolTrail _trail(String id, (double, double) from, (double, double) to) => PoolTrail(
      id: id,
      name: id,
      points: _m([from, ((from.$1 + to.$1) / 2, (from.$2 + to.$2) / 2), to]),
      lengthM: 1000,
      grade: 2,
      lossM: 100,
    );

LoopRequest _request({RiderParams profile = RiderProfile.bio}) => LoopRequest(
      start: _m([(5, 0)]).single,
      profile: profile,
      budget: const LoopBudget(timeS: 3 * 3600, climbM: 800, hikingM: 2000),
      pool: [_trail('A', (10, 990), (990, 10)), _trail('B', (1010, 990), (1010, 10))],
      searchBudget: const Duration(milliseconds: 50),
    );

/// Ein Profil, das beim ersten Blick der Suche wirft — sendbar, weil es
/// nur eine gewöhnliche Klasse ist.
class _BrokenRider implements RiderParams {
  const _BrokenRider();
  @override
  RiderProfile get profile => RiderProfile.bio;
  @override
  double get climbTrackMPerH => throw StateError('kaputtes Profil');
  @override
  double get climbPathMPerH => throw StateError('kaputtes Profil');
  @override
  double get pushRateMPerH => throw StateError('kaputtes Profil');
  @override
  double get vFlatKmh => throw StateError('kaputtes Profil');
  @override
  double get vPathUpKmh => throw StateError('kaputtes Profil');
  @override
  double get vPushKmh => throw StateError('kaputtes Profil');
  @override
  double get vDownKmh => throw StateError('kaputtes Profil');
  @override
  double get pathUpFactor => throw StateError('kaputtes Profil');
  @override
  double get pathDownFactor => throw StateError('kaputtes Profil');
  @override
  double get budgetClimbM => throw StateError('kaputtes Profil');
  @override
  RoutePrefs get prefs => const RoutePrefs();
}

void main() {
  test('rechnet dasselbe wie an Ort und Stelle, und der eigene Graph bleibt, wie er war', () async {
    final inline = await InlineLoopPlanRunner().plan(_square(), _request());
    final runner = IsolateLoopPlanRunner();
    addTearDown(runner.dispose);
    final g = _square();
    final edges = g.edges.length, nodes = g.nodes.length;
    final plan = await runner.plan(g, _request());
    expect(plan.outcome, LoopOutcome.ok);
    expect(plan.stops.map((s) => s.trail.id), inline.stops.map((s) => s.trail.id));
    expect(plan.summary!.trailM, inline.summary!.trailM);
    expect(plan.summary!.gainM, inline.summary!.gainM);
    expect(plan.summary!.timeS, inline.summary!.timeS);
    expect(plan.points.length, inline.points.length);
    expect((g.edges.length, g.nodes.length), (edges, nodes),
        reason: 'angeheftet wird drüben, auf der Kopie');
  });

  test('derselbe Graph geht nur einmal hinüber, ein neuer wieder', () async {
    final runner = IsolateLoopPlanRunner();
    addTearDown(runner.dispose);
    final g = _square();
    await runner.plan(g, _request());
    await runner.plan(g, _request());
    expect(runner.graphSends, 1);
    await runner.plan(_square(), _request());
    expect(runner.graphSends, 2);
  });

  test('ein Fehler in der Rechnung kommt als Fehler an, der Isolate rechnet weiter', () async {
    final runner = IsolateLoopPlanRunner();
    addTearDown(runner.dispose);
    final g = _square();
    await expectLater(runner.plan(g, _request(profile: const _BrokenRider())),
        throwsA(isA<RemoteError>().having((e) => e.toString(), 'Meldung', contains('kaputtes Profil'))));
    final plan = await runner.plan(g, _request());
    expect(plan.outcome, LoopOutcome.ok);
    expect(runner.graphSends, 1);
  });

  test('Freigeben während des Starts lässt die Rechnung scheitern, die nächste legt neu an', () async {
    final runner = IsolateLoopPlanRunner();
    final g = _square();
    final pending = runner.plan(g, _request());
    runner.dispose();
    await expectLater(pending, throwsA(isA<StateError>()));
    final plan = await runner.plan(g, _request());
    expect(plan.outcome, LoopOutcome.ok);
    expect(runner.graphSends, 1, reason: 'der erste Start kam nie so weit');
    runner.dispose();
  });

  test('Freigeben nach einer Rechnung: der neue Isolate bekommt den Graphen noch einmal', () async {
    final runner = IsolateLoopPlanRunner();
    final g = _square();
    await runner.plan(g, _request());
    runner.dispose();
    final plan = await runner.plan(g, _request());
    expect(plan.outcome, LoopOutcome.ok);
    expect(runner.graphSends, 2);
    runner.dispose();
  });

  test('auf dem Telefon ist der Planer-Runner der Rechen-Isolate', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final runner = container.read(loopPlanRunnerFactoryProvider)();
    addTearDown(runner.dispose);
    expect(runner, isA<IsolateLoopPlanRunner>());
  });
}
