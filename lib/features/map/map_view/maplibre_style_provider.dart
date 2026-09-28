// Die I/O-Schicht über dem puren Style-Composer: materialisiert Glyphs und
// Übersichtskarte aus den Assets, liest den Zoombereich aus dem
// Archiv-Header und setzt daraus das Style-Dokument der MapLibre-Engine
// zusammen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pmtiles/pmtiles.dart';

import '../../../core/app_colors.dart';
import '../../../core/connectivity.dart';
import '../../../core/errors.dart';
import '../../official/official_trails_source.dart';
import '../base_map_providers.dart';
import '../map_providers.dart';
import 'map_style_composer.dart';

/// Die fünf Unicode-Bereiche, die für deutsche Kartenbeschriftung reichen.
const _glyphRanges = ['0-255', '256-511', '512-767', '7680-7935', '8192-8447'];
const _fontStacks = ['noto-sans-regular', 'noto-sans-medium'];

/// Alle Plattenzugriffe des Style-Providers — als Klasse, damit Tests sie
/// durch eine Fake ersetzen können; echte Dateien und Platform-Channels
/// gibt es im Widget-Test nicht.
class MapLibreStyleIo {
  /// Der erzeugte Protomaps-Basis-Style (dasselbe Asset wie beim
  /// Canvas-Renderer — eine Quelle der Wahrheit für beide Engines).
  Future<String> loadBaseStyle() => rootBundle.loadString(kMapStyleAsset);

  /// Kopiert ein Asset ins App-Verzeichnis, wenn es dort fehlt oder eine
  /// andere Größe hat — MapLibre kann keine `asset://`-URLs lesen (kein
  /// Byte-Range auf Assets), es braucht echte Dateien.
  Future<File> _materialize(String assetPath, File target) async {
    final data = await rootBundle.load(assetPath);
    if (!await target.exists() || await target.length() != data.lengthInBytes) {
      await target.create(recursive: true);
      await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return target;
  }

  /// Materialisiert die DACH-Übersicht und liefert ihren Pfad. Derselbe
  /// Zielpfad wie `openBundledOverview` beim Canvas-Renderer — beide
  /// Engines teilen sich die eine Datei auf Platte.
  Future<String> materializeOverview() async {
    final dir = await getApplicationSupportDirectory();
    final file = await _materialize(
        kOverviewAsset, File('${dir.path}/offline_maps/overview_dach.pmtiles'));
    return file.path;
  }

  /// Materialisiert die Glyph-PBFs und liefert die Glyphs-URL-Vorlage.
  Future<String> materializeGlyphs() async {
    final dir = await getApplicationSupportDirectory();
    for (final stack in _fontStacks) {
      for (final range in _glyphRanges) {
        await _materialize('assets/map_glyphs/$stack/$range.pbf',
            File('${dir.path}/map_glyphs/$stack/$range.pbf'));
      }
    }
    return 'file://${dir.path}/map_glyphs/{fontstack}/{range}.pbf';
  }

  /// Liest min/max Zoom aus dem PMTiles-ARCHIV-HEADER — nie aus den
  /// eingebetteten Metadaten (siehe MapStyleSource).
  Future<({int min, int max})> readZoomRange(String path) async {
    final archive = await PmTilesArchive.fromFile(File(path));
    try {
      return (min: archive.header.minZoom, max: archive.header.maxZoom);
    } finally {
      await archive.close();
    }
  }
}

final maplibreStyleIoProvider = Provider<MapLibreStyleIo>((ref) => MapLibreStyleIo());

/// CSS-Farbwert für den Style — aus derselben Konstante wie die
/// flutter_map-Engine, damit die Landflächen beider Engines gleich aussehen.
String cssColor(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Das Online-Raster — dieselbe Quelle wie der TileLayer der
/// flutter_map-Engine.
const _osmRaster = MapRasterSource(
  id: 'osm',
  urlTemplate: kOsmTileUrl,
  maxZoom: kOsmMaxZoom,
);

/// Das fertige Style-Dokument — oder null, wenn etwas fehlt: Dann fällt die
/// MapLibre-Engine auf flutter_map zurück (maplibre_map_view.dart).
///
/// Die Quellen-Wahl folgt EXAKT der flutter_map-Engine: das OSM-Raster
/// immer, die Übersicht NUR darunter, wenn kein Empfang besteht — dann
/// kommt keine Kachel, es gibt nichts, womit sie sich mischen könnte.
/// Ein Wechsel erzeugt einen neuen Style-String; die Engine spielt ihn per
/// `setStyle` ein.
final maplibreStyleProvider = FutureProvider<String?>((ref) async {
  final noConnectivity = ref.watch(noConnectivityProvider);
  final io = ref.watch(maplibreStyleIoProvider);
  // Die Quellenangabe der Behörden — nur solange die Ebene an ist und
  // eine ihrer Regionen geladen. `select` auf den Text: Der Controller
  // ändert sich bei jedem Nachladen, der Text selten.
  final officialCredits = ref.watch(officialTrailsEnabledProvider)
      ? ref.watch(officialTrailsControllerProvider.select((s) => [
            for (final src in s.loadedSources) '${src.attribution} (${src.license})',
          ].join('\u0000')))
      : '';
  try {
    final base = jsonDecode(await io.loadBaseStyle()) as Map<String, dynamic>;
    final glyphsUrl = await io.materializeGlyphs();

    final sources = <MapStyleSource>[];
    if (noConnectivity) {
      final overviewPath = await io.materializeOverview();
      final overviewZoom = await io.readZoomRange(overviewPath);
      sources.add(MapStyleSource(
        id: 'overview',
        filePath: overviewPath,
        minZoom: overviewZoom.min,
        maxZoom: overviewZoom.max,
      ));
    }

    return composeMapLibreStyle(
      baseStyle: base,
      glyphsUrl: glyphsUrl,
      backgroundColor: cssColor(AppColors.mapBackground.toARGB32()),
      sources: sources,
      rasterSources: const [_osmRaster],
      extraAttributions: officialCredits.isEmpty ? const [] : officialCredits.split('\u0000'),
    );
  } catch (e, stackTrace) {
    logError('MapLibre-Style bauen', e, stackTrace);
    return null;
  }
});
