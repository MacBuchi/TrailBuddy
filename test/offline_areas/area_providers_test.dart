// Die Bereiche in der App: wann sie die Karte sind (kein Empfang oder
// kein Manifest — dieselbe Regel wie die Übersicht, in beiden Engines),
// und wie mehrere Bereiche zu EINER Kachelquelle der flutter_map-Engine
// werden.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/features/map/online_map.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_providers.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/pmtiles_writer.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

const _manifest = MapManifest(file: 'dach-20260928.pmtiles', maxZoom: 13, bytes: 1, sourceBuild: '20260928');

Uint8List _archive(AreaBounds b, String tag) => writePmTiles(
      tiles: [
        for (final t in tilesCovering(b, maxZoom: 9))
          TileToWrite(t.z, t.x, t.y, Uint8List.fromList(utf8.encode('$tag ${t.z}/${t.x}/${t.y}'))),
      ],
      tileCompression: Compression.none,
      bounds: TileBounds(west: b.west, south: b.south, east: b.east, north: b.north),
    );

StoredArea _area(String id, AreaBounds b) => StoredArea(
      id: id,
      name: id,
      bounds: b,
      minZoom: 8,
      maxZoom: 9,
      build: '20260928',
      tiles: 1,
      bytes: 1,
      savedAt: DateTime.utc(2026, 9, 28),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer make({required bool noConnectivity, MapManifest? manifest = _manifest, AreaStore? store}) {
    final c = ProviderContainer(overrides: [
      noConnectivityProvider.overrideWithValue(noConnectivity),
      mapManifestLoaderProvider.overrideWithValue(() async => manifest),
      areaStoreProvider.overrideWithValue(store ?? MemoryAreaStore()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('die Bereiche sind die Karte ohne Empfang oder ohne Manifest', () async {
    final offline = make(noConnectivity: true);
    expect(offline.read(areasActiveProvider), isTrue);

    final online = make(noConnectivity: false);
    await online.read(mapManifestProvider.future);
    expect(online.read(areasActiveProvider), isFalse);

    final hostGone = make(noConnectivity: false, manifest: null);
    await hostGone.read(mapManifestProvider.future);
    expect(hostGone.read(areasActiveProvider), isTrue);
  });

  test('zwei Bereiche werden EINE Kachelquelle: der erste, der die Kachel hat, liefert', () async {
    const west = AreaBounds(south: 47.9, west: 11.0, north: 48.0, east: 11.2);
    const east = AreaBounds(south: 47.9, west: 12.0, north: 48.0, east: 12.2);
    final store = MemoryAreaStore();
    await store.putArchive('w', _archive(west, 'west'));
    await store.putArchive('e', _archive(east, 'east'));
    await store.saveIndex([_area('w', west), _area('e', east)]);

    final c = make(noConnectivity: true, store: store);
    // Der Stil kommt aus dem Asset — das der Test-Runner nicht liefert;
    // die Kachelquelle selbst braucht ihn nicht.
    final opened = [
      for (final a in await store.list())
        (area: a, provider: (await c.read(areaArchiveOpenerProvider)(store, a))!),
    ];
    final multi = MultiAreaTileProvider(opened);
    expect(multi.minimumZoom, kAreaMinZoom);
    expect(multi.maximumZoom, 9);

    final inWest = tileAt(47.95, 11.1, 9);
    final inEast = tileAt(47.95, 12.1, 9);
    expect(utf8.decode(await multi.provide(TileIdentity(9, inWest.x, inWest.y))), startsWith('west'));
    expect(utf8.decode(await multi.provide(TileIdentity(9, inEast.x, inEast.y))), startsWith('east'));
    final nowhere = tileAt(50, 8, 9);
    await expectLater(multi.provide(TileIdentity(9, nowhere.x, nowhere.y)), throwsA(isA<ProviderException>()));
    await expectLater(multi.provide(TileIdentity(12, 0, 0)), throwsA(isA<ProviderException>()),
        reason: 'über dem Zoom der Bereiche');
    await multi.close();
  });

  test('ohne Bereiche keine Schicht; ein Bereich ohne Archiv fällt still weg', () async {
    final c = make(noConnectivity: true);
    expect(await c.read(areaMapStyleProvider.future), isNull);

    final store = MemoryAreaStore();
    await store.saveIndex([_area('ghost', const AreaBounds(south: 47, west: 11, north: 48, east: 12))]);
    final c2 = make(noConnectivity: true, store: store);
    expect(await c2.read(areaMapStyleProvider.future), isNull);
    // Der Öffner wurde gefragt und hatte nichts.
    expect(await c2.read(areaArchiveOpenerProvider)(store, (await store.list()).single), isNull);
  });
}
