// Fehlende Wege- und Höhenkacheln vom eigenen Kartenhost (#187, seit
// 0.78.0). Die Planung rechnet über die Kacheln der gespeicherten
// Bereiche; mit Empfang kommen die fehlenden aus DEMSELBEN Archiv, aus
// dem die Bereiche geschnitten sind (`dach-<build>.pmtiles`, Ebene
// `roads`) und aus dem Höhenarchiv (`heights-<build>.pmtiles`), per
// Range-Anfrage wie beim Speichern eines Bereichs. Kein neues Netzziel:
// Die Online-Karte holt dieselben Kacheln.
//
// Drei Regeln:
// - **Die letzte Quelle**: Gefragt wird nur nach Kacheln, die kein Bereich
//   hat, höchstens [kOnlineFillMaxTiles] je Planung (der Lader zählt).
//   Höhen nur für genau diese Kacheln — ein Bereich ohne Höhen (vor
//   0.69.0) bekommt hier keine nachgereicht, das macht „Aktualisieren".
// - **Nur für die Sitzung**: Die Kacheln liegen im Speicher
//   ([OnlineTileCache], höchstens [kOnlineCacheTiles] je Sorte), damit ein
//   zweiter Plan dieselbe Gegend nicht noch einmal holt. Behalten ist
//   #155 („Gesehenes bleibt liegen").
// - **Ein Netzfehler beendet das Nachladen**, er kippt die Planung nicht:
//   Was bis dahin da ist, reicht für einen Plan, und das Blatt sagt, über
//   wie viele Kacheln. Jeder Schritt hat eine Frist ([kOnlineFillTimeout]) —
//   „ein Balken, über den nichts kommt" ist im Wald der Normalfall.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' show ProviderException, TileIdentity;

import '../../core/errors.dart';
import '../map/online_map.dart';
import '../map/pmtiles_tile_provider.dart';
import '../offline_areas/area_plan.dart';
import '../offline_areas/area_providers.dart' show areaSourceOpenerProvider;
import '../offline_areas/height_tiles.dart';

/// Höchstens so lange wartet ein Schritt des Nachladens (Manifest, Archiv
/// öffnen, eine Kachel). Danach gilt das Netz als weg.
const kOnlineFillTimeout = Duration(seconds: 10);

/// So viele Kacheln je Sorte hält der Sitzungsspeicher, die ältesten
/// fallen zuerst. Eine Wegekachel bei z13 hat meist einige zehn KB.
const kOnlineCacheTiles = 300;

/// Die nachgeladenen Kacheln dieser Sitzung — im Speicher, nie auf der
/// Platte. Auch „der Host hat sie nicht" wird gemerkt (null).
class OnlineTileCache {
  // Dart-Maps behalten die Einfügereihenfolge: Der erste Schlüssel ist
  // der älteste.
  final _roads = <int, Uint8List?>{};
  final _heights = <int, HeightTile?>{};

  static int _key(int x, int y) => (x << kHeightTileZoom) | y;

  bool hasRoads(TileXYZ t) => _roads.containsKey(_key(t.x, t.y));
  Uint8List? roads(TileXYZ t) => _roads[_key(t.x, t.y)];
  void putRoads(TileXYZ t, Uint8List? bytes) => _put(_roads, _key(t.x, t.y), bytes);

  bool hasHeights(int x, int y) => _heights.containsKey(_key(x, y));
  HeightTile? heights(int x, int y) => _heights[_key(x, y)];
  void putHeights(int x, int y, HeightTile? tile) => _put(_heights, _key(x, y), tile);

  int get length => _roads.length + _heights.length;

  static void _put<V>(Map<int, V> map, int key, V value) {
    map.remove(key);
    map[key] = value;
    while (map.length > kOnlineCacheTiles) {
      map.remove(map.keys.first);
    }
  }
}

final onlineTileCacheProvider = Provider<OnlineTileCache>((ref) => OnlineTileCache());

/// Eine Planung lang: öffnet die Archive des Hosts erst, wenn eine Kachel
/// fehlt, und schließt sie danach ([close]).
class OnlineFill {
  OnlineFill({
    required this.openRoads,
    required this.openHeights,
    required this.cache,
    this.timeout = kOnlineFillTimeout,
  });

  /// Öffnet das Kartenarchiv des Hosts; null ohne Manifest.
  final Future<PmTilesVectorTileProvider?> Function() openRoads;

  /// Öffnet das Höhenarchiv des Hosts; null ohne Manifest oder Bau.
  final Future<PmTilesArchive?> Function() openHeights;
  final OnlineTileCache cache;
  final Duration timeout;

  Future<PmTilesVectorTileProvider?>? _roads;
  Future<PmTilesArchive?>? _heights;
  bool _heightsFailed = false;

  /// Die Kacheln, die diese Planung vom Host hat — nur für sie fragt
  /// [heights] das Höhenarchiv.
  final _fetched = <int>{};

  /// Wie viele Höhenkacheln über das Netz kamen (nicht aus dem Speicher).
  int heightRequests = 0;

  /// Die Wegekachel [t] — aus dem Speicher oder vom Host. Null: Der Host
  /// hat sie nicht. Wirft bei Netzfehler oder Frist; der Lader hört dann
  /// auf zu fragen.
  Future<Uint8List?> fetch(TileXYZ t) async {
    if (cache.hasRoads(t)) {
      final cached = cache.roads(t);
      if (cached != null) _fetched.add(OnlineTileCache._key(t.x, t.y));
      return cached;
    }
    final archive = await (_roads ??= openRoads().timeout(timeout));
    if (archive == null) throw StateError('Kein Kartenhost');
    Uint8List? bytes;
    try {
      bytes = await archive.provide(TileIdentity(t.z, t.x, t.y)).timeout(timeout);
    } on ProviderException catch (e) {
      // 404: außerhalb des Archivs (Meer, Ausland). Alles andere ist kein
      // „hat er nicht", sondern ein Fehler.
      if (e.statusCode != 404) rethrow;
      bytes = null;
    }
    cache.putRoads(t, bytes);
    if (bytes != null) _fetched.add(OnlineTileCache._key(t.x, t.y));
    return bytes;
  }

  /// Höhen für die nachgeladenen Kacheln — die letzte Quelle des Lesers.
  HeightTileSource get heights => _OnlineHeightSource(this);

  Future<HeightTile?> _heightTile(int x, int y) async {
    if (!_fetched.contains(OnlineTileCache._key(x, y))) return null;
    if (cache.hasHeights(x, y)) return cache.heights(x, y);
    if (_heightsFailed) return null;
    try {
      final archive = await (_heights ??= openHeights().timeout(timeout));
      if (archive == null) {
        _heightsFailed = true;
        return null;
      }
      final id = ZXY(kHeightTileZoom, x, y).toTileId();
      HeightTile? tile;
      heightRequests++;
      if (await archive.lookup(id).timeout(timeout) != null) {
        try {
          tile = HeightTile.decode((await archive.tile(id).timeout(timeout)).bytes());
        } on FormatException {
          tile = null;
        }
      }
      cache.putHeights(x, y, tile);
      return tile;
    } catch (e, s) {
      // Ohne Höhen rechnet die Suche flach und sagt es — kein Grund, den
      // Plan zu kippen. Gemeldet nur, was nicht nach Funkloch aussieht.
      if (!looksOffline(e)) logError('Höhen online nachladen', e, s);
      _heightsFailed = true;
      return null;
    }
  }

  Future<void> close() async {
    try {
      await (await _roads)?.close();
    } catch (_) {
      // Nie geöffnet oder schon weg — nichts zu schließen.
    }
    try {
      await (await _heights)?.close();
    } catch (_) {
      // Dasselbe für das Höhenarchiv.
    }
  }
}

class _OnlineHeightSource implements HeightTileSource {
  _OnlineHeightSource(this._fill);
  final OnlineFill _fill;

  @override
  Future<HeightTile?> tile(int x, int y) => _fill._heightTile(x, y);

  // Geschlossen wird über [OnlineFill.close], einmal für beide Archive.
  @override
  Future<void> close() async {}
}

/// Baut das Nachladen für eine Planung aus den Manifesten des Hosts —
/// die Naht, die Tests ersetzen.
final onlineFillFactoryProvider = Provider<OnlineFill Function()>((ref) => () => OnlineFill(
      openRoads: () async {
        final manifest = await ref.read(mapManifestProvider.future);
        if (manifest == null) return null;
        return ref.read(onlineArchiveOpenerProvider)(manifest.archiveUri);
      },
      openHeights: () async {
        final manifest = await ref.read(heightsManifestProvider.future);
        if (manifest == null) return null;
        return ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
      },
      cache: ref.read(onlineTileCacheProvider),
    ));
