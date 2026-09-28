// Der Style-Provider ist die I/O-Schicht über dem puren Composer: Welche
// Quellen er wann zusammensetzt, ist die Regel „Online-Karte vom Host,
// sobald das Manifest da ist; die Übersicht darunter ohne Empfang oder
// ohne Manifest" — dieselbe wie in der flutter_map-Engine.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_style_provider.dart';
import 'package:trailbuddy/features/map/online_map.dart';
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

const _manifest = MapManifest(
  file: 'dach-20260928.pmtiles',
  maxZoom: 13,
  bytes: 2900000000,
  sourceBuild: '20260928',
);

void main() {
  (ProviderContainer, _FakeIo) make({
    required bool noConnectivity,
    MapManifest? manifest = _manifest,
    bool officialOn = false,
    FakeOfficialTrailsSource? official,
  }) {
    final io = _FakeIo();
    final container = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(io),
      noConnectivityProvider.overrideWithValue(noConnectivity),
      mapManifestLoaderProvider.overrideWithValue(() async => manifest),
      settingsProvider.overrideWithValue(FakeSettings(officialTrailsEnabled: officialOn)),
      officialTrailsSourceProvider.overrideWithValue(official ?? FakeOfficialTrailsSource()),
      officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
    ]);
    addTearDown(container.dispose);
    return (container, io);
  }

  Future<Map<String, dynamic>> styleOf(ProviderContainer c) async =>
      jsonDecode((await c.read(maplibreStyleProvider.future))!) as Map<String, dynamic>;

  List<String> sourceIds(Map<String, dynamic> style) =>
      (style['sources'] as Map<String, dynamic>).keys.toList();

  test('online mit Manifest: nur die Online-Karte, kein Archiv-Header gelesen', () async {
    final (container, io) = make(noConnectivity: false);
    final style = await styleOf(container);
    expect(sourceIds(style), ['online']);
    final online = (style['sources'] as Map)['online'] as Map;
    expect(online['url'], 'pmtiles://https://tiles.mcbuchi.de/trailbuddy/dach-20260928.pmtiles');
    expect(online['maxzoom'], 13, reason: 'aus dem Manifest, nicht aus einer Range-Anfrage');
    expect(io.readHeaders, isEmpty);
    expect(style['glyphs'], 'file:///fake/map_glyphs/{fontstack}/{range}.pbf');
  });

  test('ohne Empfang: die Übersicht allein — das Manifest wird gar nicht erst geholt', () async {
    var asked = 0;
    final io = _FakeIo();
    final container = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(io),
      noConnectivityProvider.overrideWithValue(true),
      mapManifestLoaderProvider.overrideWithValue(() async {
        asked++;
        return _manifest;
      }),
      settingsProvider.overrideWithValue(FakeSettings()),
      officialTrailsSourceProvider.overrideWithValue(FakeOfficialTrailsSource()),
      officialTrailsCacheProvider.overrideWithValue(MemoryOfficialTrailsCache()),
    ]);
    addTearDown(container.dispose);
    final style = await styleOf(container);
    expect(sourceIds(style), ['overview']);
    expect(asked, 0, reason: 'ein Funkloch ist kein Grund für einen Fehlversuch');
    expect(io.readHeaders, ['/fake/offline_maps/overview_dach.pmtiles']);
    final ids = (style['layers'] as List).map((l) => (l as Map)['id']).toList();
    expect(ids, ['hintergrund', 'overview/earth']);
  });

  test('online ohne Manifest (Host weg): die Übersicht ist die Karte', () async {
    final (container, _) = make(noConnectivity: false, manifest: null);
    expect(sourceIds(await styleOf(container)), ['overview']);
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
    final (container, _) = make(noConnectivity: false, officialOn: true, official: source);
    var style = await styleOf(container);
    expect(((style['sources'] as Map)['online'] as Map)['attribution'],
        '© OpenStreetMap contributors · Protomaps');

    await container
        .read(officialTrailsControllerProvider.notifier)
        .ensure((s: 47.9, w: 8.9, n: 48.1, e: 9.1));
    style = await styleOf(container);
    expect(((style['sources'] as Map)['online'] as Map)['attribution'],
        '© OpenStreetMap contributors · Protomaps · Land Testland (CC0 1.0)');
  });
}
