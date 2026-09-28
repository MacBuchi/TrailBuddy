// Ein Bereich entsteht (Konzept 3.2): erst der PLAN — welche Kacheln,
// und wie viele Bytes das im Archiv des Hosts sind (jede Kachel nennt
// ihre Länge im Verzeichnis, „12,4 MB" ist eine Messung, keine
// Schätzung) —, dann der DOWNLOAD über den `tiles()`-Strom des Pakets
// (nach Hilbert-Kurve geclustert zerfällt ein Rechteck in wenige
// zusammenhängende Byte-Bereiche), dazu die Orte-Dateien der berührten
// Rasterzellen, am Ende EIN Archiv über den Schreiber, zurückgelesen als
// Gegenprobe, dann der Index.
//
// Läuft im Main-Isolate; auf Android hält der KeepAlive-Koordinator den
// Prozess wach (Vordergrunddienst `dataSync`), im Browser der Tab. Wer
// abbricht, bekommt nichts Halbes: Geschrieben wird erst am Ende.
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';

import '../map/online_map.dart';
import '../map/poi.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'pmtiles_writer.dart';

/// Der Plan: was geholt würde, und wie viel das ist.
class AreaPlan {
  const AreaPlan({
    required this.shape,
    required this.bounds,
    required this.maxZoom,
    required this.tiles,
    required this.bytes,
  });

  /// Die Form, die geplant wurde — wird mit dem Bereich gemerkt, damit
  /// „Aktualisieren" dieselbe Form noch einmal holt.
  final AreaShape shape;

  /// Die Hülle der Form: der Rahmen im Archiv-Header.
  final AreaBounds bounds;
  final int maxZoom;

  /// Die Kacheln, die das Archiv des Hosts wirklich hat (Kacheln ohne
  /// Eintrag — Meer außerhalb DACH — fehlen hier schon).
  final List<TileXYZ> tiles;

  /// Bytes im Archiv, Kachel für Kachel summiert.
  final int bytes;
}

/// Mehr Kacheln als [kAreaMaxTiles]: kleiner wählen oder zwei Bereiche.
class AreaTooLarge implements Exception {
  const AreaTooLarge(this.tiles);
  final int tiles;
  @override
  String toString() => 'Bereich zu groß: $tiles Kacheln';
}

/// Vom Nutzer abgebrochen — kein Fehler, nichts geschrieben.
class AreaCancelled implements Exception {
  const AreaCancelled();
}

/// Der Fortschritt: [done] von [total] in der Phase (Kacheln, dann Orte).
class AreaProgress {
  const AreaProgress({required this.phase, required this.done, required this.total});
  final AreaPhase phase;
  final int done;
  final int total;

  double get fraction => total == 0 ? 1 : done / total;
}

enum AreaPhase { tiles, pois, writing }

class AreaDownloader {
  AreaDownloader({
    required this.archive,
    required this.manifest,
    required this.store,
    required this.fetchPoiFile,
    this.poiManifest,
    this.chunkSize = 256,
    this.now,
  });

  /// Das Archiv des Hosts, über Range-Anfragen geöffnet.
  final PmTilesArchive archive;
  final MapManifest manifest;
  final AreaStore store;

  /// Holt eine Orte-Datei des Hosts (`pois-<build>/<name>`), null bei 404.
  final Future<String?> Function(String name) fetchPoiFile;

  /// Das Orte-Manifest — null heißt: keine Orte zum Bereich (noch kein
  /// Bau veröffentlicht).
  final PoiManifest? poiManifest;

  /// So viele Kachel-Ids je `tiles()`-Aufruf: Das Paket liest je
  /// Aufruf alle zusammenhängenden Bereiche PARALLEL — ein ganzer
  /// Bereich auf einmal wäre ein Sturm aus Range-Anfragen.
  final int chunkSize;

  final DateTime Function()? now;

  Future<AreaPlan> plan(AreaShape shape) async {
    final maxZoom = manifest.maxZoom;
    final count = shape.countTiles(maxZoom: maxZoom);
    if (count > kAreaMaxTiles) throw AreaTooLarge(count);
    final wanted = shape.tiles(maxZoom: maxZoom);
    final present = <TileXYZ>[];
    var bytes = 0;
    for (final t in wanted) {
      final entry = await archive.lookup(tileIdOf(t));
      if (entry == null) continue;
      present.add(t);
      bytes += entry.length;
    }
    return AreaPlan(shape: shape, bounds: shape.hull, maxZoom: maxZoom, tiles: present, bytes: bytes);
  }

  /// Holt und speichert den Bereich; wirft [AreaCancelled], sobald
  /// [isCancelled] wahr sagt (geprüft zwischen den Blöcken).
  Future<StoredArea> download(
    AreaPlan plan, {
    required String name,
    String? id,
    void Function(AreaProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void check() {
      if (isCancelled?.call() ?? false) throw const AreaCancelled();
    }

    final byId = {for (final t in plan.tiles) tileIdOf(t): t};
    final ids = byId.keys.toList()..sort();
    final fetched = <TileToWrite>[];
    onProgress?.call(AreaProgress(phase: AreaPhase.tiles, done: 0, total: ids.length));
    for (var start = 0; start < ids.length; start += chunkSize) {
      check();
      final chunk = ids.sublist(start, start + chunkSize > ids.length ? ids.length : start + chunkSize);
      await for (final tile in archive.tiles(chunk)) {
        final t = byId[tile.id]!;
        // Die BYTES des Hosts, unverändert (mit dessen Kompression) — der
        // Schreiber trägt dieselbe Kompression in den Header.
        fetched.add(TileToWrite(t.z, t.x, t.y, Uint8List.fromList(tile.compressedBytes())));
      }
      onProgress?.call(AreaProgress(phase: AreaPhase.tiles, done: fetched.length, total: ids.length));
    }

    // Die Orte der berührten Zellen, alle Gruppen — was das Manifest
    // nennt. Alle Gruppen, damit der Filter offline umschaltbar bleibt;
    // die Dateien sind klein. Die Zellen kommen aus der FORM, nicht aus
    // der Hülle: Entlang der Trails sind das die Zellen der Kacheln, nicht
    // alles dazwischen.
    final poiFiles = <String, String>{};
    final pm = poiManifest;
    if (pm != null) {
      final wanted = [
        for (final cell in plan.shape.poiCells())
          for (final g in PoiGroup.values)
            if (pm.has(cell, g)) poiCellFileName(cell, g),
      ];
      onProgress?.call(AreaProgress(phase: AreaPhase.pois, done: 0, total: wanted.length));
      for (final fileName in wanted) {
        check();
        final text = await fetchPoiFile(fileName);
        if (text != null) poiFiles[fileName] = text;
        onProgress?.call(AreaProgress(phase: AreaPhase.pois, done: poiFiles.length, total: wanted.length));
      }
    }

    check();
    onProgress?.call(const AreaProgress(phase: AreaPhase.writing, done: 0, total: 1));
    final areaId = id ?? _newId();
    final bytes = writePmTiles(
      tiles: fetched,
      tileCompression: archive.header.tileCompression,
      bounds: TileBounds(
          west: plan.bounds.west, south: plan.bounds.south, east: plan.bounds.east, north: plan.bounds.north),
      metadata: {
        'name': name,
        'source_build': manifest.sourceBuild,
        'attribution': '© OpenStreetMap contributors · Protomaps (ODbL)',
      },
    );
    await store.putArchive(areaId, bytes);
    await _verify(areaId, fetched);
    for (final e in poiFiles.entries) {
      await store.putPoiFile(areaId, e.key, e.value);
    }

    final area = StoredArea(
      id: areaId,
      name: name,
      shape: plan.shape,
      bounds: plan.bounds,
      minZoom: kAreaMinZoom,
      maxZoom: plan.maxZoom,
      build: manifest.sourceBuild,
      tiles: fetched.length,
      bytes: bytes.length,
      savedAt: (now ?? DateTime.now)().toUtc(),
      poiFiles: poiFiles.keys.toList()..sort(),
      poiBuild: poiFiles.isEmpty ? null : pm?.build,
    );
    final others = [for (final a in await store.list()) if (a.id != areaId) a];
    await store.saveIndex([...others, area]);
    return area;
  }

  /// Die Gegenprobe: Das gespeicherte Archiv öffnet sich mit dem Leser,
  /// den beide Engines benutzen, zählt alle Kacheln und liefert eine
  /// Stichprobe Byte für Byte. Ein Archiv, das hier scheitert, wird nie
  /// in den Index eingetragen.
  Future<void> _verify(String areaId, List<TileToWrite> fetched) async {
    final path = await store.archivePath(areaId);
    final PmTilesArchive stored;
    if (path != null) {
      stored = await PmTilesArchive.from(path);
    } else {
      final bytes = await store.readArchive(areaId);
      if (bytes == null) throw StateError('Archiv nach dem Schreiben nicht lesbar');
      stored = await PmTilesArchive.fromBytes(bytes);
    }
    try {
      if (stored.header.numberOfAddressedTiles != fetched.length) {
        throw StateError('Archiv zählt ${stored.header.numberOfAddressedTiles} statt ${fetched.length} Kacheln');
      }
      for (final probe in [fetched.first, fetched[fetched.length ~/ 2], fetched.last]) {
        final tile = await stored.tile(ZXY(probe.z, probe.x, probe.y).toTileId());
        final got = tile.compressedBytes();
        if (got.length != probe.bytes.length) {
          throw StateError('Kachel ${probe.z}/${probe.x}/${probe.y} kommt anders zurück');
        }
        for (var i = 0; i < got.length; i++) {
          if (got[i] != probe.bytes[i]) {
            throw StateError('Kachel ${probe.z}/${probe.x}/${probe.y} kommt anders zurück');
          }
        }
      }
    } finally {
      await stored.close();
    }
  }

  String _newId() {
    final at = (now ?? DateTime.now)().toUtc();
    return 'area-${at.millisecondsSinceEpoch.toRadixString(36)}';
  }
}
