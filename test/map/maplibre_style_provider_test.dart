// Der Style-Provider ist die I/O-Schicht über dem puren Composer: Welche
// Quellen er wann zusammensetzt, ist die Regel „Übersicht NUR ohne
// Empfang" — dieselbe wie in der flutter_map-Engine.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_style_provider.dart';
import 'package:trailbuddy/features/official/official_trails_source.dart';

import '../fakes/fake_official_trails.dart';
import '../fakes/fake_settings.dart';

/// I/O-Fake: liefert feste Pfade und Header-Zoombereiche, merkt sich, für
/// welche Dateien der Header gelesen wurde.
class _FakeIo extends MapLibreStyleIo {
  final readHeaders = <String>[];
  bool failOverview = false;

  @override
  Future<String> loadBaseStyle() async => jsonEncode({
        'version': 8,
        'sources': {},
        'layers': [
          {'id': 'earth', 'type': 'fill', 'source': 'protomaps', 'source-layer': 'earth'},
        ],
      });

  @override
  Future<String> materializeOverview() async {
    if (failOverview) throw StateError('Asset kaputt');
    return '/fake/offline_maps/overview_dach.pmtiles';
  }

  @override
  Future<String> materializeGlyphs() async => 'file:///fake/map_glyphs/{fontstack}/{range}.pbf';

  @override
  Future<({int min, int max})> readZoomRange(String path) async {
    readHeaders.add(path);
    return (min: 0, max: 7);
  }
}

void main() {
  (ProviderContainer, _FakeIo) make({required bool noConnectivity, bool officialOn = false}) {
    final io = _FakeIo();
    final container = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(io),
      noConnectivityProvider.overrideWithValue(noConnectivity),
      settingsProvider.overrideWithValue(FakeSettings(officialTrailsEnabled: officialOn)),
      officialTrailsSourceProvider.overrideWithValue(FakeOfficialTrailsSource()),
      officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
    ]);
    addTearDown(container.dispose);
    return (container, io);
  }

  Future<Map<String, dynamic>> styleOf(ProviderContainer c) async =>
      jsonDecode((await c.read(maplibreStyleProvider.future))!) as Map<String, dynamic>;

  test('online: nur das OSM-Raster, keine Übersicht, kein Archiv-Header gelesen', () async {
    final (container, io) = make(noConnectivity: false);
    final style = await styleOf(container);
    expect((style['sources'] as Map).keys, ['osm']);
    expect(io.readHeaders, isEmpty);
    expect(style['glyphs'], 'file:///fake/map_glyphs/{fontstack}/{range}.pbf');
  });

  test('ohne Empfang: die Übersicht UNTER dem Raster, Zoombereich aus dem Header', () async {
    final (container, io) = make(noConnectivity: true);
    final style = await styleOf(container);
    final sources = style['sources'] as Map<String, dynamic>;
    expect(sources.keys, ['overview', 'osm'], reason: 'Reihenfolge = Schichtung');
    expect((sources['overview'] as Map)['maxzoom'], 7);
    expect(io.readHeaders, ['/fake/offline_maps/overview_dach.pmtiles']);
    final ids = (style['layers'] as List).map((l) => (l as Map)['id']).toList();
    expect(ids, ['hintergrund', 'overview/earth', 'osm']);
  });

  test('I/O-Fehler ⇒ null statt Wurf (die Engine fällt auf flutter_map zurück)', () async {
    final (container, io) = make(noConnectivity: true);
    io.failOverview = true;
    expect(await container.read(maplibreStyleProvider.future), isNull);
  });

  test('die Quellen der offiziellen Trails stehen im Style, sobald eine Region geladen ist',
      () async {
    final source = FakeOfficialTrailsSource({
      'index.json': fakeIndex(),
      'testland.geojson': fakeRegion(),
    });
    final container = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(_FakeIo()),
      noConnectivityProvider.overrideWithValue(false),
      settingsProvider.overrideWithValue(FakeSettings(officialTrailsEnabled: true)),
      officialTrailsSourceProvider.overrideWithValue(source),
      officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
    ]);
    addTearDown(container.dispose);
    var style = await styleOf(container);
    expect(((style['sources'] as Map)['osm'] as Map)['attribution'], '© OpenStreetMap contributors');

    await container
        .read(officialTrailsControllerProvider.notifier)
        .ensure((s: 47.9, w: 8.9, n: 48.1, e: 9.1));
    style = await styleOf(container);
    expect(((style['sources'] as Map)['osm'] as Map)['attribution'],
        '© OpenStreetMap contributors · Land Testland (CC0 1.0)');
  });
}
