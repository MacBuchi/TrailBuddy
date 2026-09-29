// Die gespeicherten Bereiche in der App (Konzept 3.2): die Liste, der
// laufende Download (mit Fortschritt, Abbruch und dem Vordergrunddienst
// über den KeepAlive-Koordinator), und die geöffneten Archive für die
// Karte — für flutter_map als Kachelquellen, für MapLibre als Pfade.
//
// Wann die Bereiche die Karte SIND: sobald kein Empfang besteht oder es
// kein Manifest gibt — dieselbe Regel wie für die Übersicht, in beiden
// Engines. Bewusst nicht „erst lokal, dann Netz" (Konzept 3.2, dort so
// gedacht): MapLibre hat keinen Kachel-Lieferanten, in den sich ein
// lokaler Vorrang hängen ließe — zwei Quellen mit demselben Inhalt
// zeichneten doppelt. Beide Engines eine Regel ist mehr wert als ein
// Vorrang in nur einer (Entscheidung, Konzept Abschnitt 7).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../keep_alive/keep_alive.dart';
import '../map/base_map_providers.dart';
import '../map/online_map.dart';
import '../map/pmtiles_tile_provider.dart';
import '../map/poi.dart';
import '../map/poi_source.dart';
import 'area_downloader.dart';
import 'area_plan.dart';
import 'area_store.dart';
import 'area_trim.dart';

/// Die Liste aus dem Index, in Speicherreihenfolge.
class StoredAreasNotifier extends AsyncNotifier<List<StoredArea>> {
  @override
  Future<List<StoredArea>> build() => ref.watch(areaStoreProvider).list();

  Future<void> refresh() async => state = AsyncData(await ref.read(areaStoreProvider).list());

  Future<void> delete(String id) async {
    await ref.read(areaStoreProvider).delete(id);
    await refresh();
  }

  /// Was das Entfernen von [removes] (Kacheln bei Zoom 13) aus den
  /// gespeicherten Bereichen macht — lokal gemessen, ohne Netz.
  Future<TrimPlan> planTrim(Set<int> removes) async =>
      AreaTrimmer(ref.read(areaStoreProvider)).plan(await future, removes);

  Future<void> applyTrim(TrimPlan plan) async {
    await AreaTrimmer(ref.read(areaStoreProvider)).apply(plan);
    await refresh();
  }
}

final storedAreasProvider =
    AsyncNotifierProvider<StoredAreasNotifier, List<StoredArea>>(StoredAreasNotifier.new);

/// Öffnet das Archiv des Hosts für den Download — die Naht für Tests.
final areaSourceOpenerProvider =
    Provider<Future<PmTilesArchive> Function(Uri)>((ref) => PmTilesArchive.fromUri);

/// Das Orte-Manifest für den Download — null, wenn keins da ist (dann
/// kommt der Bereich ohne Orte). Die Naht für Tests.
final areaPoiManifestLoaderProvider = Provider<Future<PoiManifest?> Function()>((ref) => () async {
      try {
        return await fetchPoiManifest(http.Client());
      } catch (_) {
        return null;
      }
    });

/// Holt eine Orte-Datei des Hosts für einen Bereich.
final areaPoiFileLoaderProvider =
    Provider<Future<String?> Function(PoiManifest manifest, String name)>(
        (ref) => (manifest, name) => fetchPoiFileFromHost(http.Client(), manifest, name));

enum AreaDownloadPhase { idle, planning, running, done, failed }

/// Der Zustand des einen laufenden Downloads (es gibt höchstens einen).
@immutable
class AreaDownloadState {
  const AreaDownloadState({
    this.phase = AreaDownloadPhase.idle,
    this.name,
    this.plan,
    this.progress,
    this.result,
    this.error,
  });

  final AreaDownloadPhase phase;
  final String? name;
  final AreaPlan? plan;
  final AreaProgress? progress;
  final StoredArea? result;
  final String? error;

  bool get busy => phase == AreaDownloadPhase.planning || phase == AreaDownloadPhase.running;
}

class AreaDownloadNotifier extends Notifier<AreaDownloadState> {
  static const _keepAliveKey = 'area';
  bool _cancelled = false;

  @override
  AreaDownloadState build() => const AreaDownloadState();

  /// Der Plan für [shape]: wirft [AreaTooLarge], liefert Kacheln, Bytes
  /// und — seit 0.27.0 — die Orte samt Anzahl (der Dialog vor dem
  /// Speichern nennt sie; der Download holt sie dann nicht noch einmal).
  /// Braucht das Manifest — ohne Empfang gibt es keinen Plan.
  Future<AreaPlan> plan(AreaShape shape) async {
    final manifest = await ref.read(mapManifestProvider.future);
    if (manifest == null) throw StateError('Kein Kartenhost erreichbar');
    state = const AreaDownloadState(phase: AreaDownloadPhase.planning);
    final archive = await ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
    try {
      final poiManifest = await ref.read(areaPoiManifestLoaderProvider)();
      final fetchPoi = ref.read(areaPoiFileLoaderProvider);
      final downloader = AreaDownloader(
          archive: archive,
          manifest: manifest,
          store: ref.read(areaStoreProvider),
          poiManifest: poiManifest,
          fetchPoiFile: (fileName) =>
              poiManifest == null ? Future.value(null) : fetchPoi(poiManifest, fileName));
      final plan = await downloader.plan(shape, withPois: true);
      state = AreaDownloadState(phase: AreaDownloadPhase.idle, plan: plan);
      return plan;
    } catch (e) {
      state = const AreaDownloadState();
      rethrow;
    } finally {
      await archive.close();
    }
  }

  /// Holt und speichert. Läuft im Main-Isolate; der Koordinator hält
  /// den Prozess auf Android wach. Ein Fehler landet im Zustand (die
  /// Oberfläche zeigt ihn), nie beim Aufrufer.
  Future<StoredArea?> start(AreaPlan plan, {required String name, String? id}) async {
    if (state.busy) return null;
    _cancelled = false;
    final manifest = await ref.read(mapManifestProvider.future);
    if (manifest == null) {
      state = AreaDownloadState(phase: AreaDownloadPhase.failed, error: 'Kein Kartenhost erreichbar', plan: plan);
      return null;
    }
    state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name, plan: plan);
    final coordinator = ref.read(keepAliveCoordinatorProvider);
    await coordinator.start(_keepAliveKey, '$name — 0 %', title: 'Bereich wird gespeichert');
    PmTilesArchive? archive;
    try {
      archive = await ref.read(areaSourceOpenerProvider)(manifest.archiveUri);
      final poiManifest = await ref.read(areaPoiManifestLoaderProvider)();
      final fetchPoi = ref.read(areaPoiFileLoaderProvider);
      final downloader = AreaDownloader(
        archive: archive,
        manifest: manifest,
        store: ref.read(areaStoreProvider),
        poiManifest: poiManifest,
        fetchPoiFile: (fileName) => poiManifest == null ? Future.value(null) : fetchPoi(poiManifest, fileName),
      );
      final area = await downloader.download(
        plan,
        name: name,
        id: id,
        isCancelled: () => _cancelled,
        onProgress: (p) {
          state = AreaDownloadState(phase: AreaDownloadPhase.running, name: name, plan: plan, progress: p);
          final percent = (p.fraction * 100).round();
          final text = switch (p.phase) {
            AreaPhase.tiles => '$name — $percent %',
            AreaPhase.pois => '$name — Orte',
            AreaPhase.writing => '$name — wird geschrieben',
          };
          unawaited(coordinator.update(_keepAliveKey, text));
        },
      );
      await ref.read(storedAreasProvider.notifier).refresh();
      state = AreaDownloadState(phase: AreaDownloadPhase.done, name: name, plan: plan, result: area);
      return area;
    } on AreaCancelled {
      state = const AreaDownloadState();
      return null;
    } catch (e, s) {
      if (!looksOffline(e)) logError('Bereich speichern', e, s);
      state = AreaDownloadState(
          phase: AreaDownloadPhase.failed,
          name: name,
          plan: plan,
          error: looksOffline(e)
              ? 'Die Verbindung ist abgerissen. Nichts gespeichert — noch einmal versuchen, sobald Empfang da ist.'
              : 'Der Bereich ließ sich nicht speichern.');
      return null;
    } finally {
      await archive?.close();
      await coordinator.stop(_keepAliveKey);
    }
  }

  void cancel() => _cancelled = true;

  void reset() {
    if (!state.busy) state = const AreaDownloadState();
  }
}

final areaDownloadProvider =
    NotifierProvider<AreaDownloadNotifier, AreaDownloadState>(AreaDownloadNotifier.new);

/// Gilt die Regel „die Bereiche sind die Karte"? Kein Empfang oder kein
/// Manifest — wie bei der Übersicht.
final areasActiveProvider = Provider<bool>((ref) {
  if (ref.watch(noConnectivityProvider)) return true;
  final manifest = ref.watch(mapManifestProvider);
  return manifest.hasValue && manifest.value == null;
});

/// Die Archive der Bereiche mit Pfad — für MapLibre (`file://`). Leer im
/// Browser (dort gibt es keine Pfade, und keine MapLibre-Engine).
final areaArchivePathsProvider = FutureProvider<List<({StoredArea area, String path})>>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  final store = ref.watch(areaStoreProvider);
  return [
    for (final area in areas)
      if (await store.archivePath(area.id) case final path?) (area: area, path: path),
  ];
});

/// Öffnet ein gespeichertes Archiv für die flutter_map-Engine — die
/// Naht für Tests.
final areaArchiveOpenerProvider =
    Provider<Future<PmTilesVectorTileProvider?> Function(AreaStore store, StoredArea area)>(
        (ref) => _openArea);

Future<PmTilesVectorTileProvider?> _openArea(AreaStore store, StoredArea area) async {
  final path = await store.archivePath(area.id);
  if (path != null) return PmTilesVectorTileProvider.open(path);
  final bytes = await store.readArchive(area.id);
  if (bytes == null) return null;
  return PmTilesVectorTileProvider.openBytes(bytes);
}

/// Mehrere Bereiche als EINE Kachelquelle: Die erste, die die Kachel
/// hat, liefert; keine ⇒ 404 wie bei einer Kachel außerhalb.
class MultiAreaTileProvider extends VectorTileProvider {
  MultiAreaTileProvider(this._areas);

  final List<({StoredArea area, PmTilesVectorTileProvider provider})> _areas;

  Future<void> close() async {
    for (final a in _areas) {
      await a.provider.close();
    }
  }

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    ProviderException? last;
    for (final a in _areas) {
      if (tile.z < a.area.minZoom || tile.z > a.area.maxZoom) continue;
      try {
        return await a.provider.provide(tile);
      } on ProviderException catch (e) {
        last = e;
      }
    }
    throw last ??
        ProviderException(
            message: 'Kachel ${tile.key()} in keinem Bereich', retryable: Retryable.none, statusCode: 404);
  }

  @override
  int get minimumZoom => kAreaMinZoom;

  @override
  int get maximumZoom {
    var max = kAreaMinZoom;
    for (final a in _areas) {
      if (a.area.maxZoom > max) max = a.area.maxZoom;
    }
    return max;
  }

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;
}

/// Die Bereiche als Kartenschicht der flutter_map-Engine — null, wenn
/// es keine gibt oder keines aufgeht. Thema OHNE `background`, damit die
/// Übersicht darunter durchscheint, wo kein Bereich liegt.
final areaMapStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  final areas = await ref.watch(storedAreasProvider.future);
  if (areas.isEmpty) return null;
  final store = ref.watch(areaStoreProvider);
  final open = ref.watch(areaArchiveOpenerProvider);
  final opened = <({StoredArea area, PmTilesVectorTileProvider provider})>[];
  for (final area in areas) {
    try {
      final provider = await open(store, area);
      if (provider != null) opened.add((area: area, provider: provider));
    } catch (e, s) {
      logError('Bereich öffnen', e, s);
    }
  }
  if (opened.isEmpty) return null;
  final multi = MultiAreaTileProvider(opened);
  ref.onDispose(multi.close);
  final theme = await ref.watch(baseThemeWithoutBackgroundProvider.future);
  return BaseMapStyle(theme: theme, tileProviders: TileProviders({'protomaps': multi}));
});

/// „Auf der Karte zeigen" aus der Liste: der Wunsch, den die Karte beim
/// nächsten Aufbau einpasst und dann zurücksetzt.
final mapFocusAreaProvider = StateProvider<StoredArea?>((ref) => null);

/// Solange die Werkzeugleiste „Ebenen" offen ist (seit 0.27.0; davor das
/// Blatt „Offline-Karten"): Die Karte dunkelt alles ab, was nicht
/// gespeichert ist, und der Entwurf liegt schraffiert darüber.
final offlineOverlayProvider = StateProvider<bool>((ref) => false);
