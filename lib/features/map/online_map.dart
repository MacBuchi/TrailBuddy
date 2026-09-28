import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileProviders;

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import 'base_map_providers.dart';
import 'map_providers.dart';
import 'pmtiles_tile_provider.dart';

/// Das Manifest des Kartenhosts (`dach.json`, geschrieben von
/// `map-data.yml`): welche Datei gerade gilt und bis zu welchem Zoom sie
/// reicht.
class MapManifest {
  const MapManifest({
    required this.file,
    required this.maxZoom,
    required this.bytes,
    required this.sourceBuild,
  });

  final String file;
  final int maxZoom;
  final int bytes;

  /// Das Datum des Protomaps-Baus (`JJJJMMTT`) — der Kartenstand.
  final String sourceBuild;

  Uri get archiveUri => Uri.parse('$kMapTilesBase/$file');

  /// Liest das Manifest; wirft bei allem, was nicht passt. Der Dateiname
  /// wird geprüft, weil er zu einem Pfad wird.
  factory MapManifest.fromJson(Map<String, dynamic> j) {
    final file = j['file'] as String;
    if (!RegExp(r'^dach-\d{8}\.pmtiles$').hasMatch(file)) {
      throw FormatException('Unerwarteter Archivname: $file');
    }
    return MapManifest(
      file: file,
      maxZoom: j['maxzoom'] as int,
      bytes: j['bytes'] as int,
      sourceBuild: j['source_build'] as String,
    );
  }
}

/// Holt das Manifest vom Host — die Naht, die Tests ersetzen (kein Netz).
Future<MapManifest?> fetchMapManifest() async {
  final response = await http.get(Uri.parse(kMapManifestUrl));
  if (response.statusCode != 200) {
    throw http.ClientException('Manifest: HTTP ${response.statusCode}');
  }
  return MapManifest.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
}

final mapManifestLoaderProvider =
    Provider<Future<MapManifest?> Function()>((ref) => fetchMapManifest);

/// Das Manifest — oder null: kein Empfang (dann wird gar nicht erst
/// gefragt), Host nicht erreichbar, Datei kaputt. Null heißt für beide
/// Engines: die mitgelieferte Übersicht ist die Karte.
///
/// Hängt am `noConnectivityProvider`, damit die Rückkehr des Netzes einen
/// neuen Versuch auslöst. Ein Fehler wird nur gemeldet, wenn er nicht
/// nach Funkloch aussieht — sonst füllte jeder Wald den Wochendigest.
final mapManifestProvider = FutureProvider<MapManifest?>((ref) async {
  if (ref.watch(noConnectivityProvider)) return null;
  try {
    return await ref.watch(mapManifestLoaderProvider)();
  } catch (e, s) {
    if (!looksOffline(e)) logError('Karten-Manifest laden', e, s);
    return null;
  }
});

/// Öffnet das Online-Archiv über Range-Anfragen — die Naht für Tests.
final onlineArchiveOpenerProvider =
    Provider<Future<PmTilesVectorTileProvider> Function(Uri)>(
        (ref) => PmTilesVectorTileProvider.openUri);

/// Die Online-Vektorkarte für die flutter_map-Engine: Archiv vom Host
/// plus das Thema OHNE `background`-Ebene, damit die Übersicht darunter
/// durchscheint, wo eine Kachel (noch) fehlt. Null, solange es kein
/// Manifest gibt oder das Archiv nicht aufgeht — dann bleibt die
/// Übersicht die Karte, ohne Fehlermeldung.
final onlineMapStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  final manifest = await ref.watch(mapManifestProvider.future);
  if (manifest == null) return null;
  try {
    final archive = await ref.watch(onlineArchiveOpenerProvider)(manifest.archiveUri);
    ref.onDispose(archive.close);
    final theme = await ref.watch(baseThemeWithoutBackgroundProvider.future);
    return BaseMapStyle(theme: theme, tileProviders: TileProviders({'protomaps': archive}));
  } catch (e, s) {
    if (!looksOffline(e)) logError('Online-Karte öffnen', e, s);
    return null;
  }
});
