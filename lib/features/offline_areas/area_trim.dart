// Kacheln aus gespeicherten Bereichen herausnehmen (seit 0.27.0; der
// Radierer der Werkzeugleiste auf hellen Kacheln, Betreiber, 2026-09-29).
// Ganz ohne Netz: Die App liest das eigene Archiv, schreibt es ohne die
// wegfallenden Kacheln neu (derselbe Schreiber wie beim Download) und
// liest es mit dem Leser beider Engines gegen. Ein Bereich, der dabei
// leer wird, verschwindet ganz.
//
// Gerechnet wird in den Kacheln der Formen ([kAreaShapeZoom]): Eine
// gröbere Kachel (Zoom 8…12) bleibt, solange noch eine ihrer Kinder im
// Bereich liegt — sonst fehlte beim Herauszoomen die Übersicht über den
// Rest.
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';

import '../map/poi.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'height_tiles.dart';
import 'pmtiles_writer.dart';

/// Was mit EINEM Bereich passiert.
class AreaTrim {
  const AreaTrim({
    required this.area,
    required this.shape,
    required this.keep,
    required this.freedTiles,
    required this.freedBytes,
    this.keepHeights = const [],
  });

  final StoredArea area;

  /// Die neue Form; null heißt: der Bereich wird ganz gelöscht.
  final TileSetShape? shape;

  /// Die Kacheln, die im Archiv bleiben (alle Zooms).
  final List<TileXYZ> keep;
  final int freedTiles;

  /// Frei werdende Bytes beider Archive (Karte und Höhen).
  final int freedBytes;

  /// Die Höhenkacheln, die im zweiten Archiv bleiben (leer: keine mehr,
  /// oder der Bereich hatte nie welche).
  final List<TileXYZ> keepHeights;
}

/// Der Plan des Entfernens über alle betroffenen Bereiche.
class TrimPlan {
  const TrimPlan(this.trims);

  final List<AreaTrim> trims;

  bool get isEmpty => trims.isEmpty;
  int get freedTiles => trims.fold(0, (s, t) => s + t.freedTiles);
  int get freedBytes => trims.fold(0, (s, t) => s + t.freedBytes);
}

class AreaTrimmer {
  AreaTrimmer(this.store);

  final AreaStore store;

  Future<PmTilesArchive> _open(StoredArea area) async {
    final path = await store.archivePath(area.id);
    if (path != null) return PmTilesArchive.from(path);
    final bytes = await store.readArchive(area.id);
    if (bytes == null) throw StateError('Archiv von ${area.name} fehlt');
    return PmTilesArchive.fromBytes(bytes);
  }

  /// Das Höhenarchiv, null wenn der Bereich keins trägt — ein Index, der
  /// Höhen nennt, deren Archiv fehlt, zählt wie keins (es ist nachladbar).
  Future<PmTilesArchive?> _openHeights(StoredArea area) async {
    if (!area.hasHeights) return null;
    final path = await store.heightsPath(area.id);
    if (path != null) return PmTilesArchive.from(path);
    final bytes = await store.readHeights(area.id);
    return bytes == null ? null : PmTilesArchive.fromBytes(bytes);
  }

  /// Was [removes] (Kacheln bei [kAreaShapeZoom]) mit den Bereichen
  /// macht. Gemessen, nicht geschätzt: Die frei werdenden Bytes kommen
  /// aus dem Verzeichnis des jeweiligen Archivs.
  Future<TrimPlan> plan(List<StoredArea> areas, Set<int> removes) async {
    final trims = <AreaTrim>[];
    if (removes.isEmpty) return const TrimPlan([]);
    for (final area in areas) {
      final keys = area.shape.keysAt(kAreaShapeZoom);
      if (!keys.any(removes.contains)) continue;
      final remaining = keys.difference(removes);
      final shape = remaining.isEmpty ? null : TileSetShape(zoom: kAreaShapeZoom, keys: remaining);
      final wanted = shape?.tiles(minZoom: area.minZoom, maxZoom: area.maxZoom).toSet() ?? const <TileXYZ>{};
      final archive = await _open(area);
      try {
        final keep = <TileXYZ>[];
        var freedTiles = 0, freedBytes = 0;
        for (final t in area.shape.tiles(minZoom: area.minZoom, maxZoom: area.maxZoom)) {
          final entry = await archive.lookup(tileIdOf(t));
          if (entry == null) continue; // lag nie im Archiv
          if (wanted.contains(t)) {
            keep.add(t);
          } else {
            freedTiles++;
            freedBytes += entry.length;
          }
        }
        // Die Höhen folgen den Kacheln der Form: eine Höhenkachel je
        // z13-Kachel, die bleibt.
        final keepHeights = <TileXYZ>[];
        var freedHeightBytes = 0;
        final hArchive = await _openHeights(area);
        if (hArchive != null) {
          try {
            final wantedH = shape?.tiles(minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom).toSet() ?? const {};
            for (final t in area.shape.tiles(minZoom: kHeightTileZoom, maxZoom: kHeightTileZoom)) {
              final entry = await hArchive.lookup(tileIdOf(t));
              if (entry == null) continue;
              if (wantedH.contains(t)) {
                keepHeights.add(t);
              } else {
                freedHeightBytes += entry.length;
              }
            }
          } finally {
            await hArchive.close();
          }
        }
        trims.add(AreaTrim(
          area: area,
          shape: keep.isEmpty ? null : shape,
          keep: keep,
          freedTiles: freedTiles,
          freedBytes: keep.isEmpty ? area.bytes + area.heightBytes : freedBytes + freedHeightBytes,
          keepHeights: keep.isEmpty ? const [] : keepHeights,
        ));
      } finally {
        await archive.close();
      }
    }
    return TrimPlan(trims);
  }

  /// Führt [plan] aus: je Bereich neu schreiben oder löschen, dann EIN
  /// neuer Index.
  Future<void> apply(TrimPlan plan) async {
    if (plan.isEmpty) return;
    final updated = <String, StoredArea?>{};
    for (final trim in plan.trims) {
      final area = trim.area;
      final shape = trim.shape;
      if (shape == null) {
        await store.delete(area.id);
        updated[area.id] = null;
        continue;
      }
      final archive = await _open(area);
      final Uint8List bytes;
      try {
        final ids = {for (final t in trim.keep) tileIdOf(t): t};
        final kept = <TileToWrite>[];
        final sorted = ids.keys.toList()..sort();
        for (var start = 0; start < sorted.length; start += 256) {
          final chunk = sorted.sublist(start, start + 256 > sorted.length ? sorted.length : start + 256);
          await for (final tile in archive.tiles(chunk)) {
            final t = ids[tile.id]!;
            kept.add(TileToWrite(t.z, t.x, t.y, Uint8List.fromList(tile.compressedBytes())));
          }
        }
        final hull = shape.hull;
        bytes = writePmTiles(
          tiles: kept,
          tileCompression: archive.header.tileCompression,
          bounds: TileBounds(west: hull.west, south: hull.south, east: hull.east, north: hull.north),
          metadata: {
            'name': area.name,
            'source_build': area.build,
            'attribution': '© OpenStreetMap contributors · Protomaps (ODbL)',
          },
        );
        if (kept.length != trim.keep.length) {
          throw StateError('${area.name}: ${kept.length} statt ${trim.keep.length} Kacheln gelesen');
        }
      } finally {
        await archive.close();
      }
      // Gegenlesen, bevor das alte Archiv ersetzt wird.
      final check = await PmTilesArchive.fromBytes(bytes);
      try {
        if (check.header.numberOfAddressedTiles != trim.keep.length) {
          throw StateError('${area.name}: neues Archiv zählt falsch');
        }
      } finally {
        await check.close();
      }
      await store.putArchive(area.id, bytes);
      final heightBytes = await _rewriteHeights(area, trim);
      // Orte-Dateien nur noch für Zellen, die der Bereich noch berührt.
      final cells = shape.poiCells().toSet();
      final wantedPoi = {
        for (final c in cells)
          for (final g in PoiGroup.values) poiCellFileName(c, g),
      };
      updated[area.id] = StoredArea(
        id: area.id,
        name: area.name,
        bounds: shape.hull,
        shape: shape,
        minZoom: area.minZoom,
        maxZoom: area.maxZoom,
        build: area.build,
        tiles: trim.keep.length,
        bytes: bytes.length,
        savedAt: area.savedAt,
        poiFiles: [for (final f in area.poiFiles) if (wantedPoi.contains(f)) f],
        poiBuild: area.poiBuild,
        heightTiles: trim.keepHeights.length,
        heightBytes: heightBytes,
        heightsBuild: trim.keepHeights.isEmpty ? null : area.heightsBuild,
      );
    }
    final next = <StoredArea>[
      for (final a in await store.list())
        if (!updated.containsKey(a.id)) a else if (updated[a.id] != null) updated[a.id]!,
    ];
    await store.saveIndex(next);
  }

  /// Schreibt das Höhenarchiv ohne die wegfallenden Kacheln neu (oder
  /// nimmt es weg, wenn keine bleibt); liefert seine neue Größe.
  Future<int> _rewriteHeights(StoredArea area, AreaTrim trim) async {
    final hArchive = await _openHeights(area);
    if (hArchive == null) return 0;
    if (trim.keepHeights.isEmpty) {
      await hArchive.close();
      await store.deleteHeights(area.id);
      return 0;
    }
    final Uint8List bytes;
    try {
      final ids = {for (final t in trim.keepHeights) tileIdOf(t): t};
      final kept = <TileToWrite>[];
      final sorted = ids.keys.toList()..sort();
      for (var start = 0; start < sorted.length; start += 256) {
        final chunk = sorted.sublist(start, start + 256 > sorted.length ? sorted.length : start + 256);
        await for (final tile in hArchive.tiles(chunk)) {
          final t = ids[tile.id]!;
          kept.add(TileToWrite(t.z, t.x, t.y, Uint8List.fromList(tile.compressedBytes())));
        }
      }
      final hull = trim.shape!.hull;
      bytes = writePmTiles(
        tiles: kept,
        tileCompression: hArchive.header.tileCompression,
        bounds: TileBounds(west: hull.west, south: hull.south, east: hull.east, north: hull.north),
        metadata: heightsMetadata(area.name, area.heightsBuild),
      );
      if (kept.length != trim.keepHeights.length) {
        throw StateError('${area.name}: ${kept.length} statt ${trim.keepHeights.length} Höhenkacheln gelesen');
      }
    } finally {
      await hArchive.close();
    }
    final check = await PmTilesArchive.fromBytes(bytes);
    try {
      if (check.header.numberOfAddressedTiles != trim.keepHeights.length) {
        throw StateError('${area.name}: neues Höhenarchiv zählt falsch');
      }
    } finally {
      await check.close();
    }
    await store.putHeights(area.id, bytes);
    return bytes.length;
  }
}
