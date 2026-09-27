// Orte auf der Karte (#12): Arten erkennen, Overpass-Abfrage bauen und
// lesen, das Raster, und dass jede Zelle je Gruppe nur einmal gefragt wird.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/poi_source.dart';

import '../fakes/fake_pois.dart';
import '../fakes/fake_settings.dart';

void main() {
  group('Arten', () {
    test('Café, Quelle, Schlüssel', () {
      expect(PoiKind.of({'amenity': 'cafe'}), PoiKind.cafe);
      expect(PoiKind.of({'natural': 'spring'}), PoiKind.spring);
      expect(PoiKind.of({'amenity': 'bicycle_repair_station'}),
          PoiKind.repairStation);
      expect(PoiKind.of({'highway': 'track'}), isNull);
    });

    test('Ladesäule nur fürs Rad, Parkplatz nur öffentlich', () {
      expect(PoiKind.of({'amenity': 'charging_station'}), isNull);
      expect(PoiKind.of({'amenity': 'charging_station', 'bicycle': 'yes'}),
          PoiKind.eBikeCharging);
      expect(PoiKind.of({'amenity': 'parking'}), PoiKind.parking);
      expect(PoiKind.of({'amenity': 'parking', 'access': 'private'}), isNull);
    });
  });

  test('die Abfrage fragt nur die eingeschalteten Gruppen im Rahmen', () {
    final q = overpassQuery(
        (s: 47.5, w: 9.0, n: 47.6, e: 9.15), {PoiGroup.water});
    expect(q, contains('[bbox:47.50000,9.00000,47.60000,9.15000]'));
    expect(q, contains('nwr["amenity"="drinking_water"]'));
    expect(q, contains('nwr["natural"="spring"]'));
    expect(q, isNot(contains('cafe')));
    expect(q, endsWith('out center $kPoiMaxResults;'));
    expect(
        overpassQuery((s: 0, w: 0, n: 1, e: 1), {PoiGroup.other}),
        contains('nwr["amenity"="parking"]["access"!~"^(private|no)\$"]'));
  });

  test('die Antwort: Knoten, Flächen mit Mittelpunkt, Unbekanntes fällt weg',
      () {
    final pois = parseOverpass('''
      {"elements": [
        {"type": "node", "id": 1, "lat": 47.51, "lon": 9.01,
         "tags": {"natural": "spring", "name": "Kalte Quelle", "drinking_water": "no"}},
        {"type": "way", "id": 2, "center": {"lat": 47.52, "lon": 9.02},
         "tags": {"amenity": "biergarten", "opening_hours": "Mo-Su 11:00-22:00"}},
        {"type": "node", "id": 3, "lat": 47.53, "lon": 9.03},
        {"type": "node", "id": 4, "lat": 47.54, "lon": 9.04, "tags": {"amenity": "bench"}}
      ]}''');
    expect(pois.map((p) => p.id), ['node/1', 'way/2']);
    expect(pois[0].kind, PoiKind.spring);
    expect(pois[0].name, 'Kalte Quelle');
    expect(pois[0].drinkable, isFalse);
    expect(pois[1].position, const LatLng(47.52, 9.02));
    expect(pois[1].openingHours, 'Mo-Su 11:00-22:00');
    expect(pois[1].drinkable, isNull);
  });

  test('Raster: Zellen um einen Rahmen und der Rahmen um Zellen', () {
    final cells = poiCellsCovering(47.55, 9.05, 47.65, 9.2);
    expect(cells, ['475,60', '475,61', '476,60', '476,61']);
    final b = poiCellsBounds(cells);
    expect(b.s, closeTo(47.5, 1e-9));
    expect(b.n, closeTo(47.7, 1e-9));
    expect(b.w, closeTo(9.0, 1e-9));
    expect(b.e, closeTo(9.3, 1e-9));
    expect(poiCellOf(const LatLng(47.55, 9.05)), '475,60');
  });

  group('Nachladen', () {
    late FakePoiSource source;
    late ProviderContainer c;
    const spring = Poi(
        id: 'node/1', kind: PoiKind.spring, position: LatLng(47.55, 9.05));
    const cafe =
        Poi(id: 'node/2', kind: PoiKind.cafe, position: LatLng(47.56, 9.06));

    setUp(() {
      source = FakePoiSource([spring, cafe]);
      c = ProviderContainer(overrides: [
        settingsProvider.overrideWithValue(FakeSettings()),
        poiSourceProvider.overrideWithValue(source),
      ]);
      addTearDown(c.dispose);
    });

    test('jede Zelle je Gruppe genau einmal', () async {
      final ctl = c.read(poiControllerProvider.notifier);
      await ctl.ensure(['475,60'], {PoiGroup.water});
      await ctl.ensure(['475,60'], {PoiGroup.water});
      expect(source.calls, hasLength(1));
      expect(c.read(poiControllerProvider).inCells(['475,60'], {PoiGroup.water}),
          [spring]);

      // Eine neue Gruppe fragt nur sie nach.
      await ctl.ensure(['475,60'], {PoiGroup.water, PoiGroup.food});
      expect(source.calls, hasLength(2));
      expect(source.groupsAsked.last, {PoiGroup.food});
      expect(
          c.read(poiControllerProvider)
              .inCells(['475,60'], {PoiGroup.water, PoiGroup.food}),
          [spring, cafe]);
    });

    test('eine leere Zelle gilt als geladen', () async {
      final ctl = c.read(poiControllerProvider.notifier);
      await ctl.ensure(['0,0'], {PoiGroup.water});
      await ctl.ensure(['0,0'], {PoiGroup.water});
      expect(source.calls, hasLength(1));
    });

    test('nicht erreichbar: sagt es und fragt beim nächsten Mal wieder',
        () async {
      final ctl = c.read(poiControllerProvider.notifier);
      source.failWith = const PoiUnavailable(429);
      await ctl.ensure(['475,60'], {PoiGroup.water});
      expect(c.read(poiControllerProvider).unavailable, isTrue);
      await ctl.ensure(['475,60'], {PoiGroup.water});
      expect(source.calls, hasLength(2));
      expect(c.read(poiControllerProvider).unavailable, isFalse);
    });

    test('zu weit herausgezoomt: keine Abfrage', () async {
      final cells = poiCellsCovering(47, 8, 48, 10);
      expect(cells.length, greaterThan(kPoiMaxCells));
      await c.read(poiControllerProvider.notifier).ensure(cells, {PoiGroup.water});
      expect(source.calls, isEmpty);
    });

    test('Filter: Vorgabe Wasser, gemerkt, leer heißt alles aus', () {
      final settings = FakeSettings();
      final c2 = ProviderContainer(
          overrides: [settingsProvider.overrideWithValue(settings)]);
      addTearDown(c2.dispose);
      expect(c2.read(poiGroupsProvider), {PoiGroup.water});
      c2.read(poiGroupsProvider.notifier).toggle(PoiGroup.water);
      expect(c2.read(poiGroupsProvider), isEmpty);
      expect(settings.poiGroups, isEmpty);

      final c3 = ProviderContainer(overrides: [
        settingsProvider.overrideWithValue(FakeSettings(poiGroups: const []))
      ]);
      addTearDown(c3.dispose);
      expect(c3.read(poiGroupsProvider), isEmpty);
    });
  });
}
