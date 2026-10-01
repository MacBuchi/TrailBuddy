// Profil, Wegklassen und Kosten der Routing-Engine — Zahl für Zahl gegen
// `tool/route_measure.py` (die Zahlen hier sind dort gerechnet, am
// 2026-10-01, mit denselben Aufrufen).
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/routing/route_profile.dart';

void main() {
  test('classify: dieselben Antworten wie das Werkzeug', () {
    expect(classifyWay(kind: 'path', kindDetail: 'track'), WayClass.forstweg);
    expect(classifyWay(kind: 'path', kindDetail: 'path'), WayClass.wanderweg);
    expect(classifyWay(kind: 'path', kindDetail: 'bridleway'), WayClass.wanderweg);
    expect(classifyWay(kind: 'path', kindDetail: 'cycleway'), WayClass.radweg);
    expect(classifyWay(kind: 'path', kindDetail: 'footway'), WayClass.fussweg);
    expect(classifyWay(kind: 'path', kindDetail: 'steps'), WayClass.stufen);
    expect(classifyWay(kind: 'major_road', kindDetail: 'primary_link'), WayClass.bundesstrasse,
        reason: 'primary links count as primary');
    expect(classifyWay(kind: 'major_road', kindDetail: 'secondary'), WayClass.hauptstrasse);
    expect(classifyWay(kind: 'medium_road', kindDetail: 'tertiary'), WayClass.landstrasse);
    expect(classifyWay(kind: 'minor_road', kindDetail: 'residential'), WayClass.nebenstrasse);
    expect(classifyWay(kind: 'minor_road', kindDetail: 'service'), WayClass.zufahrt);
    expect(classifyWay(kind: 'minor_road', kindDetail: 'service', service: 'driveway'), isNull);
    expect(classifyWay(kind: 'minor_road', kindDetail: 'service', service: 'parking_aisle'), isNull);
    expect(classifyWay(kind: 'highway', kindDetail: 'motorway'), isNull);
    expect(classifyWay(kind: 'path', kindDetail: 'track', access: 'private'), isNull);
    expect(classifyWay(kind: 'path', kindDetail: 'track', access: 'no'), isNull);
    expect(classifyWay(kind: 'rail', kindDetail: null), isNull);
    expect(classifyWay(kind: 'other', kindDetail: 'raceway'), isNull);
    expect(classifyWay(kind: null, kindDetail: null), isNull);
  });

  test('Einbahn gilt nur auf Straßenklassen', () {
    for (final c in WayClass.values) {
      expect(c.isRoad, [WayClass.nebenstrasse, WayClass.zufahrt, WayClass.landstrasse, WayClass.hauptstrasse, WayClass.bundesstrasse].contains(c),
          reason: c.name);
    }
    expect(WayClass.values.where((c) => c.hiking).toList(), [WayClass.wanderweg, WayClass.fussweg, WayClass.stufen]);
  });

  test('Zeit und Kosten: die Zahlen des Werkzeugs', () {
    double t(RiderProfile p, WayClass c, double l, double g, double v) =>
        edgeTimeS(p, c, lengthM: l, gainM: g, lossM: v);
    double k(RiderProfile p, WayClass c, double l, double g, double v) =>
        edgeCostS(p, c, lengthM: l, gainM: g, lossM: v);
    const bio = RiderProfile.bio, e = RiderProfile.ebike;
    expect(t(bio, WayClass.forstweg, 1000, 100, 0), closeTo(1040.0, 1e-6));
    expect(k(bio, WayClass.forstweg, 1000, 100, 0), closeTo(1040.0, 1e-6));
    expect(t(bio, WayClass.wanderweg, 1000, 100, 0), closeTo(1478.571429, 1e-5));
    expect(k(bio, WayClass.wanderweg, 1000, 100, 0), closeTo(2070.0, 1e-5));
    expect(t(e, WayClass.wanderweg, 1000, 100, 0), closeTo(913.846154, 1e-5));
    expect(k(e, WayClass.wanderweg, 1000, 100, 0), closeTo(1827.692308, 1e-5));
    expect(k(e, WayClass.forstweg, 1000, 100, 0), closeTo(603.529412, 1e-5));
    expect(t(bio, WayClass.bundesstrasse, 1000, 0, 0), closeTo(240.0, 1e-6));
    expect(k(bio, WayClass.bundesstrasse, 1000, 0, 0), closeTo(960.0, 1e-6));
    expect(k(bio, WayClass.forstweg, 1000, 0, 100), closeTo(144.0, 1e-6), reason: 'bergab 25 km/h');
    expect(t(bio, WayClass.wanderweg, 1000, 0, 100), closeTo(360.0, 1e-6), reason: 'bergab wie Trail ohne Grad');
    expect(k(bio, WayClass.wanderweg, 1000, 0, 100), closeTo(720.0, 1e-6));
    expect(k(bio, WayClass.stufen, 200, 50, 0), closeTo(2520.0, 1e-6));
    expect(k(e, WayClass.stufen, 200, 50, 0), closeTo(3318.545455, 1e-5));
    expect(k(bio, WayClass.fussweg, 500, 0, 30), closeTo(562.5, 1e-6));
    expect(k(bio, WayClass.nebenstrasse, 2000, 150, 20), closeTo(2016.0, 1e-6));
    // Trails bergab nach Grad.
    expect(trailTimeS(lengthM: 1800, grade: 2), closeTo(720.0, 1e-6));
    expect(trailTimeS(lengthM: 1800, grade: null), closeTo(648.0, 1e-6));
    expect(trailDownKmh(5), trailDownKmh(4));
    // Die Regeln, in Worten: Wanderweg bergauf kostet mehr als ×1,4 Forstweg,
    // das E-Bike steigt schneller, der E-Bike-Aufschlag ist 2,0.
    expect(k(bio, WayClass.wanderweg, 1000, 100, 0), greaterThan(1040.0 * 1.4));
    expect(k(e, WayClass.forstweg, 1000, 100, 0), lessThan(1040.0));
    expect(k(e, WayClass.wanderweg, 1000, 100, 0) / t(e, WayClass.wanderweg, 1000, 100, 0), closeTo(2.0, 1e-9));
  });

  test('Profile: Vorgaben und Lesen aus der Einstellung', () {
    expect(RiderProfile.bio.budgetClimbM, 800);
    expect(RiderProfile.ebike.budgetClimbM, 1400);
    expect(RiderProfile.parse('ebike'), RiderProfile.ebike);
    expect(RiderProfile.parse('bio'), RiderProfile.bio);
    expect(RiderProfile.parse(null), RiderProfile.bio);
    expect(RiderProfile.parse('rakete'), RiderProfile.bio);
    expect(kBudgetHours, 3.0);
    expect(kBudgetHikingKm, 2.0);
  });
}
