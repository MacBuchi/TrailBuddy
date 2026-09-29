// Der Style-Provider ist die I/O-Schicht über dem puren Composer: Welche
// Quellen er wann zusammensetzt, ist die Regel „Online-Karte vom Host,
// sobald das Manifest da ist; die Übersicht darunter ohne Empfang oder
// ohne Manifest; die gespeicherten Bereiche immer zuoberst (#82)" —
// dieselbe wie in der flutter_map-Engine.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_style_provider.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/area_store_io.dart';
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
    AreaStore? areaStore,
  }) {
    final io = _FakeIo();
    final container = ProviderContainer(overrides: [
      maplibreStyleIoProvider.overrideWithValue(io),
      areaStoreProvider.overrideWithValue(areaStore ?? MemoryAreaStore()),
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
      areaStoreProvider.overrideWithValue(MemoryAreaStore()),
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

  group('gespeicherte Bereiche (Konzept-Schritt 3)', () {
    Future<FileAreaStore> storeWithArea() async {
      final dir = await Directory.systemTemp.createTemp('areas');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileAreaStore(baseDir: dir);
      await store.putArchive('a1', Uint8List.fromList([1, 2, 3]));
      await store.saveIndex([
        StoredArea(
          id: 'a1',
          name: 'Isartrails',
          bounds: const AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7),
          minZoom: 8,
          maxZoom: 13,
          build: '20260928',
          tiles: 42,
          bytes: 3,
          savedAt: DateTime.utc(2026, 9, 28),
        ),
      ]);
      return store;
    }

    test('ohne Empfang liegen sie als file://-Quellen über der Übersicht', () async {
      final (c, _) = make(noConnectivity: true, areaStore: await storeWithArea());
      final style = await styleOf(c);
      expect(sourceIds(style), ['overview', 'area-a1']);
      final area = (style['sources'] as Map)['area-a1'] as Map;
      expect(area['url'], allOf(startsWith('pmtiles://file://'), endsWith('/a1.pmtiles')));
      expect(area['minzoom'], 8);
      expect(area['maxzoom'], 13);
      // Und die Ebenen des Basis-Styles gibt es für die Quelle noch einmal.
      expect((style['layers'] as List).any((l) => (l as Map)['id'] == 'area-a1/earth'), isTrue);
    });

    test('mit Empfang liegen sie ÜBER der Online-Karte (#82)', () async {
      // Bis 0.36.x nur ['online']: Bei schwachem Empfang meldet das
      // Telefon ein Netz, die Online-Kacheln kommen nie — und die
      // gespeicherten wurden gar nicht gefragt.
      final (c, _) = make(noConnectivity: false, areaStore: await storeWithArea());
      final style = await styleOf(c);
      expect(sourceIds(style), ['online', 'area-a1'], reason: 'Reihenfolge = Schichtung');
      final ids = (style['layers'] as List).map((l) => (l as Map)['id']).toList();
      expect(ids.indexOf('area-a1/earth'), greaterThan(ids.indexOf('online/earth')),
          reason: 'die deckende Fläche des Bereichs liegt über der Online-Karte');
    });

    test('ohne Manifest (Host weg): Übersicht, dann der Bereich', () async {
      final (c, _) = make(noConnectivity: false, manifest: null, areaStore: await storeWithArea());
      expect(sourceIds(await styleOf(c)), ['overview', 'area-a1']);
    });

    test('ohne Pfad (Browser) keine Quelle — der Canvas-Renderer liest die Bytes', () async {
      final store = MemoryAreaStore();
      await store.putArchive('a1', Uint8List.fromList([1, 2, 3]));
      final (c, _) = make(noConnectivity: true, areaStore: store);
      expect(sourceIds(await styleOf(c)), ['overview']);
    });
  });
}
