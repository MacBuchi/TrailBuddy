// Die Ablage gespeicherter Bereiche: Dateien (Android), IndexedDB
// (Browser, hier die Speicher-Fassung derselben Implementierung) und der
// Test-Speicher verhalten sich gleich — Index, Archiv, Orte-Dateien,
// Löschen räumt alles ab.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:trailbuddy/features/offline_areas/area_plan.dart';
import 'package:trailbuddy/features/offline_areas/area_store.dart';
import 'package:trailbuddy/features/offline_areas/area_store_idb.dart';
import 'package:trailbuddy/features/offline_areas/area_store_io.dart';

StoredArea _area(String id, {List<String> poiFiles = const []}) => StoredArea(
      id: id,
      name: 'Bereich $id',
      bounds: const AreaBounds(south: 47.9, west: 11.6, north: 47.95, east: 11.7),
      minZoom: 8,
      maxZoom: 13,
      build: '20260928',
      tiles: 42,
      bytes: 1234567,
      savedAt: DateTime.utc(2026, 9, 28, 18),
      poiFiles: poiFiles,
    );

void main() {
  test('StoredArea überlebt JSON Feld für Feld', () {
    final a = _area('a1', poiFiles: const ['479_77.water.json']);
    final back = StoredArea.fromJson(a.toJson());
    expect(back.id, 'a1');
    expect(back.name, a.name);
    expect(back.bounds.north, a.bounds.north);
    expect(back.maxZoom, 13);
    expect(back.build, '20260928');
    expect(back.tiles, 42);
    expect(back.bytes, 1234567);
    expect(back.savedAt, a.savedAt);
    expect(back.poiFiles, ['479_77.water.json']);
    expect(back.poiBuild, isNull);
  });

  Future<void> exercise(AreaStore store, {required bool hasPath}) async {
    expect(await store.list(), isEmpty);
    final bytes = Uint8List.fromList(List.generate(300, (i) => i % 251));
    await store.putArchive('a1', bytes);
    await store.putPoiFile('a1', '479_77.water.json', '{"pois":[]}');
    await store.saveIndex([_area('a1', poiFiles: const ['479_77.water.json'])]);
    expect((await store.list()).single.id, 'a1');
    expect(await store.readArchive('a1'), bytes);
    expect((await store.archivePath('a1')) != null, hasPath);
    expect(await store.readPoiFile('479_77.water.json'), '{"pois":[]}');
    expect(await store.readPoiFile('0_0.food.json'), isNull);
    // Ein zweiter Bereich, dann der erste weg: Archiv, Orte, Eintrag.
    await store.putArchive('a2', bytes);
    await store.saveIndex([_area('a1', poiFiles: const ['479_77.water.json']), _area('a2')]);
    await store.delete('a1');
    expect((await store.list()).map((a) => a.id), ['a2']);
    expect(await store.readArchive('a1'), isNull);
    expect(await store.archivePath('a1'), isNull);
    expect(await store.readPoiFile('479_77.water.json'), isNull);
    expect(await store.readArchive('a2'), isNotNull);
  }

  test('Dateien auf dem Telefon', () async {
    final dir = await Directory.systemTemp.createTemp('areas');
    addTearDown(() => dir.delete(recursive: true));
    await exercise(FileAreaStore(baseDir: dir), hasPath: true);
    expect(await File('${dir.path}/a2.pmtiles').exists(), isTrue);
    expect(await File('${dir.path}/a2.pmtiles.part').exists(), isFalse);
    // Ein kaputter Index heißt keine Bereiche, kein Absturz.
    await File('${dir.path}/areas.json').writeAsString('{');
    expect(await FileAreaStore(baseDir: dir).list(), isEmpty);
  });

  test('IndexedDB im Browser (dieselbe Implementierung im Speicher)', () async {
    await exercise(IdbAreaStore(newIdbFactoryMemory()), hasPath: false);
  });

  test('der Test-Speicher', () async {
    await exercise(MemoryAreaStore(), hasPath: false);
  });
}
