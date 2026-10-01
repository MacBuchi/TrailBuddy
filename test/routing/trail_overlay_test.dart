// Die eigenen Trails auf dem Wegegraphen (#174, #185): nie gegen die
// Richtung eines Trails (außer „in beide Richtungen"), Uphill-Trails und
// Verbinder als belohnter Weg bergauf, auch wenn die Karte sie nicht kennt,
// und dass das Anheften (splitEdge) beides an die zweite Hälfte weitergibt.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/line_geometry.dart';
import 'package:trailbuddy/features/routing/loop_planner.dart';
import 'package:trailbuddy/features/routing/road_graph.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';
import 'package:trailbuddy/features/routing/route_search.dart';
import 'package:trailbuddy/features/routing/trail_overlay.dart';

const _lat0 = 47.5;

List<LatLng> _m(List<(double, double)> xy) {
  final proj = FlatProjection(_lat0);
  final o = proj.xy(const LatLng(_lat0, 11.5));
  return [for (final (x, y) in xy) proj.latLng(math.Point(o.x + x, o.y + y))];
}

WayLine _way(List<(double, double)> xy, {WayClass cls = WayClass.forstweg}) =>
    WayLine(cls: cls, oneway: false, points: _m(xy));

/// Ein Pfad (0,0)→(0,1000) direkt hinauf, daneben der Umweg über Forstweg
/// (0,0)→(3000,0)→(3000,1000)→(0,1000) — lang genug, dass der Pfad trotz
/// Aufschlag günstiger ist. Hinauf 100 hm, hinunter 100 hm.
RoadGraph _graph({bool withPath = true}) {
  final g = buildRoadGraph([
    if (withPath) _way([(0, 0), (0, 500), (0, 1000)], cls: WayClass.wanderweg),
    _way([(0, 0), (3000, 0)]),
    _way([(3000, 0), (3000, 1000)]),
    _way([(3000, 1000), (0, 1000)]),
  ], lat0: _lat0).graph;
  for (final e in g.edges) {
    final dy = g.nodes[e.b].y - g.nodes[e.a].y;
    e
      ..gain = dy > 1 ? 100 : 0
      ..loss = dy < -1 ? 100 : 0
      ..hasHeights = true;
  }
  return g;
}

GraphTrail _trail(TrailRole role, {bool up = false, bool twoWay = false}) => GraphTrail(
      id: 't',
      name: 'Hang',
      // 3 m neben dem Pfad — GPS-Versatz, im Korridor.
      points: _m(up ? [(3, 0), (3, 500), (3, 1000)] : [(3, 1000), (3, 500), (3, 0)]),
      role: role,
      twoWay: twoWay,
      gainM: up ? 100 : 0,
      lossM: up ? 0 : 100,
    );

const _bio = RiderProfile.bio;

/// Der günstigste Weg von unten nach oben (oder umgekehrt) — und ob er
/// über den Pfad geht.
({bool viaPath, PathSummary summary}) _route(RoadGraph g, {bool upward = true}) {
  final bottom = g.attach(_m([(0, 0)]).single)!, top = g.attach(_m([(0, 1000)]).single)!;
  final from = upward ? bottom : top, to = upward ? top : bottom;
  final r = shortestPath(g, from, to, _bio)!;
  return (
    viaPath: r.edges.any((ei) => g.edges[ei].cls == WayClass.wanderweg),
    summary: summarizePath(g, r.edges, from, _bio),
  );
}

void main() {
  test('ohne Trails: hinauf über den Pfad — der kürzere Weg', () {
    expect(_route(_graph()).viaPath, isTrue);
  });

  test('#174: eine Abfahrt wird nie hinauf gefahren, hinunter schon', () {
    final g = _graph();
    final r = applyTrails(g, [_trail(TrailRole.downhill)]);
    expect(r.edgesOnTrails, 1, reason: 'die Pfadkante, nicht der Forstweg daneben');
    expect(r.blocked, 1);
    expect(_route(g).viaPath, isFalse, reason: 'hinauf über den Umweg');
    expect(_route(g, upward: false).viaPath, isTrue, reason: 'in Trail-Richtung bleibt er ein Weg');
  });

  test('#174: in beide Richtungen fahrbar — dann wieder hinauf', () {
    final g = _graph();
    applyTrails(g, [_trail(TrailRole.downhill, twoWay: true)]);
    expect(_route(g).viaPath, isTrue);
  });

  test('#185: ein Uphill-Trail ist der belohnte Weg hinauf, kein Wanderweg, nie hinunter', () {
    final g = _graph();
    applyTrails(g, [_trail(TrailRole.uphill, up: true)]);
    final up = _route(g);
    expect(up.viaPath, isTrue);
    expect(up.summary.hikingM, 0, reason: 'zählt nicht gegen „höchstens Wanderweg"');
    expect(up.summary.trailUpM, closeTo(1000, 1));
    expect(_route(g, upward: false).viaPath, isFalse, reason: 'gegen seine Richtung gesperrt');
    // Billiger als derselbe Pfad ohne Trail: der Aufschlag ist 0,8 statt 1,4.
    final plain = _graph();
    final bottom = plain.attach(_m([(0, 0)]).single)!, top = plain.attach(_m([(0, 1000)]).single)!;
    final rewarded = shortestPath(g, g.attach(_m([(0, 0)]).single)!, g.attach(_m([(0, 1000)]).single)!, _bio)!;
    expect(rewarded.costS, lessThan(shortestPath(plain, bottom, top, _bio)!.costS));
  });

  test('#185: ein Verbinder geht in beide Richtungen', () {
    final g = _graph();
    applyTrails(g, [_trail(TrailRole.connector, up: true)]);
    expect(_route(g).viaPath, isTrue);
    expect(_route(g, upward: false).viaPath, isTrue);
  });

  test('#185: ein Verbinder, den die Karte nicht kennt, wird eine eigene Kante', () {
    final g = _graph(withPath: false);
    expect(_route(g).viaPath, isFalse);
    final r = applyTrails(g, [_trail(TrailRole.uphill, up: true)]);
    expect(r.addedEdges, 1);
    final up = _route(g);
    expect(up.summary.trailUpM, greaterThan(900));
    expect(up.summary.gainM, closeTo(100, 1), reason: 'Höhen aus dem Trail');
    expect(_route(g, upward: false).summary.trailUpM, 0, reason: 'hinunter nicht');
    // Eine Abfahrt, die die Karte nicht kennt, kommt NICHT dazu — sie ist
    // ein Halt der Runde, kein Weg.
    final g2 = _graph(withPath: false);
    expect(applyTrails(g2, [_trail(TrailRole.downhill)]).addedEdges, 0);
  });

  test('Anheften teilt eine Kante: Sperre, Trail und Höhen gehen an beide Hälften', () {
    final g = _graph();
    applyTrails(g, [_trail(TrailRole.downhill)]);
    final before = g.edges.length;
    // Auf die Pfadkante, ein Viertel hinauf: eine Teilung.
    final mid = g.attach(_m([(0, 250)]).single)!;
    expect(g.edges.length, before + 1);
    final halves = [for (final ei in g.adj[mid]) g.edges[ei]];
    expect(halves, hasLength(2));
    for (final e in halves) {
      expect(e.trail?.name, 'Hang');
      expect(e.blockForward || e.blockBackward, isTrue);
      expect(e.hasHeights, isTrue);
    }
    expect(halves.fold(0.0, (s, e) => s + e.gain + e.loss), closeTo(100, 0.5),
        reason: 'die Kante trug 100 hm, jetzt anteilig auf beide');
    expect(halves.map((e) => e.gain + e.loss), everyElement(greaterThan(0)));
  });

  test('der Planer fährt eine Abfahrt, die auf dem Pfad liegt, nicht als Aufstieg', () {
    final g = _graph();
    applyTrails(g, [_trail(TrailRole.downhill)]);
    final pool = [
      PoolTrail(id: 't', name: 'Hang', points: _m([(3, 1000), (3, 500), (3, 0)]), lengthM: 1000, grade: 2, lossM: 100),
    ];
    final plan = planLoop(g,
        start: _m([(0, 0)]).single,
        profile: _bio,
        budget: const LoopBudget(timeS: 3 * 3600, climbM: 800, hikingM: 2000),
        pool: pool,
        searchBudget: const Duration(milliseconds: 20));
    expect(plan.outcome, LoopOutcome.ok);
    expect(plan.sections.where((s) => !s.isTrail).every((s) => s.cls == WayClass.forstweg), isTrue,
        reason: 'hinauf über den Forstweg, nicht den Trail hinauf');
    expect(plan.summary!.hikingM, 0);
  });

  test('ein Ziel statt der Runde: endet am Ziel', () {
    final g = _graph();
    final end = _m([(3000, 1000)]).single;
    final plan = planLoop(g,
        start: _m([(0, 0)]).single,
        profile: _bio,
        budget: const LoopBudget(timeS: 3 * 3600, climbM: 800, hikingM: 2000),
        pool: [
          PoolTrail(id: 't', name: 'Hang', points: _m([(3, 1000), (3, 0)]), lengthM: 1000, grade: 2, lossM: 100),
        ],
        end: end,
        searchBudget: const Duration(milliseconds: 20));
    expect(plan.outcome, LoopOutcome.ok);
    expect(plan.points.last, end);
    final off = planLoop(g,
        start: _m([(0, 0)]).single,
        profile: _bio,
        budget: const LoopBudget(timeS: 3600, climbM: 800, hikingM: 2000),
        pool: const [],
        end: _m([(5000, 5000)]).single);
    expect(off.outcome, LoopOutcome.endOffNetwork);
  });
}
