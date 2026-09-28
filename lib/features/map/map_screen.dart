import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../models/trail.dart';
import '../feedback/feedback_dialog.dart';
import '../official/official_trails.dart';
import '../official/official_trails_layer.dart';
import '../official/official_trails_source.dart';
import '../trails/trail_providers.dart';
import '../trails/trail_sheet.dart';
import '../update/update_banner.dart';
import 'map_providers.dart';
import 'poi_layer.dart';
import 'position_provider.dart';
import 'poi_source.dart';

/// Die Karte: OSM-Raster, darüber die Trails des eigenen Netzes als
/// Linien. Eigene grün, nur von Buddys belegte blau, gesperrte oder
/// zerstörte in Warnfarbe — die Farbe sagt, was ICH damit zu tun habe,
/// nicht, wie gut der Trail ist. Ein gelber Rand heißt: Ein Buddy hat
/// in den letzten Tagen einen Hinweis dazu geschrieben (#7). Darunter, auf Wunsch, Orte aus
/// OpenStreetMap als Stecknadeln (#12) — unter den Trails, damit ein
/// Tipp auf eine Linie nie an einer Nadel hängen bleibt. Dazwischen,
/// gestrichelt, die offiziellen Trails (#13): eine eigene Ebene aus
/// Behördendaten, die nichts mit dem Netz zu tun hat.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _controller = MapController();
  final LayerHitNotifier<String> _hits = ValueNotifier(null);
  final LayerHitNotifier<OfficialTrail> _officialHits = ValueNotifier(null);
  bool _fittedOnce = false;

  static const _dachCenter = LatLng(48.8, 10.5);

  @override
  void dispose() {
    _hits.dispose();
    _officialHits.dispose();
    _controller.dispose();
    super.dispose();
  }

  Color _colorOf(Trail t) {
    if (t.status.warns) return AppColors.warningAmber;
    return t.isOwn ? AppColors.trailGreen : AppColors.friendBlue;
  }

  /// „Meine Position": die einzige Stelle, die nach der Berechtigung
  /// fragt (`positionFixProvider`). Danach läuft der Punkt mit.
  Future<void> _locateMe() async {
    final messenger = ScaffoldMessenger.of(context);
    final fix = await ref.read(positionFixProvider)();
    if (!mounted) return;
    if (fix == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Position nicht verfügbar — Standort ist aus '
              'oder für TrailBuddy nicht erlaubt.')));
      return;
    }
    _fittedOnce = true;
    final zoom = _controller.camera.zoom;
    _controller.move(LatLng(fix.latitude, fix.longitude), zoom < 14 ? 15 : zoom);
    ref.invalidate(positionStreamProvider);
  }

  void _fitTo(List<Trail> trails) {
    final pts = [for (final t in trails) ...t.points];
    if (pts.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(pts);
    _controller.fitCamera(CameraFit.bounds(
        bounds: bounds, padding: const EdgeInsets.all(40), maxZoom: 15));
  }

  @override
  Widget build(BuildContext context) {
    final trailsAsync = ref.watch(trailsProvider);
    final trails = trailsAsync.valueOrNull ?? const <Trail>[];
    final seenNotes = ref.watch(seenNotesProvider);
    final poiUnavailable = ref.watch(poiGroupsProvider).isNotEmpty &&
        ref.watch(poiControllerProvider.select((s) => s.unavailable));
    final officialOn = ref.watch(officialTrailsEnabledProvider);
    final position = ref.watch(positionStreamProvider).valueOrNull;
    final official = ref.watch(officialTrailsControllerProvider);

    // Einmal auf das Netz zoomen, sobald es da ist; danach nie wieder
    // von selbst — wer die Karte verschoben hat, will nicht zurückgeholt
    // werden.
    ref.listen(trailsProvider, (_, next) {
      final list = next.valueOrNull;
      if (!_fittedOnce && list != null && list.isNotEmpty) {
        _fittedOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitTo(list);
        });
      }
    });
    ref.listen(mapFocusTrailProvider, (_, id) {
      if (id == null) return;
      final t = ref.read(trailByIdProvider(id));
      if (t != null) {
        _fittedOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitTo([t]);
        });
      }
      ref.read(mapFocusTrailProvider.notifier).state = null;
    });

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _dachCenter,
              initialZoom: 6,
              // Norden bleibt oben: Eine gedrehte Karte passiert beim
              // Zoomen mit zwei Fingern aus Versehen, und zurückdrehen
              // kann man sie ohne Kompass nicht.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (_, _) {
                // Die Trails des Netzes liegen oben und gewinnen.
                final id = _hits.value?.hitValues.firstOrNull;
                final trail = id == null ? null : ref.read(trailByIdProvider(id));
                if (trail != null) {
                  showTrailSheet(context, trail);
                  return;
                }
                final off = _officialHits.value?.hitValues.firstOrNull;
                if (off != null) showOfficialTrailSheet(context, off);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.mcbuchi.trailbuddy',
                tileProvider: ref.watch(mapTileProviderProvider),
              ),
              const PoiLayer(),
              OfficialTrailsLayer(hits: _officialHits),
              PolylineLayer<String>(
                hitNotifier: _hits,
                polylines: [
                  for (final t in trails)
                    Polyline<String>(
                      points: t.points,
                      color: _colorOf(t),
                      strokeWidth: 4,
                      // Neuer Hinweis eines Buddys (#7): ein gelber
                      // Leuchtrand, die Linie behält ihre Farbe.
                      borderStrokeWidth:
                          t.hasFreshNote(seen: seenNotes) ? 4 : 0,
                      borderColor: AppColors.noteYellow,
                      hitValue: t.id,
                    ),
                ],
              ),
              if (position != null) ..._positionLayers(position),
              RichAttributionWidget(
                animationConfig: const ScaleRAWA(),
                attributions: [
                  const TextSourceAttribution('OpenStreetMap-Mitwirkende'),
                  // Die Quellen der offiziellen Trails, solange die Ebene
                  // an ist und eine ihrer Regionen geladen.
                  if (officialOn)
                    for (final src in official.loadedSources)
                      TextSourceAttribution(
                        '${src.attribution} (${src.license})',
                        prependCopyright: false,
                      ),
                ],
              ),
            ],
          ),
          if (trailsAsync.isLoading && trails.isEmpty)
            const Center(child: CircularProgressIndicator()),
          if (trailsAsync.hasValue && trails.isEmpty)
            const _EmptyHint(),
          const UpdateBanner(),
          // Die Glühbirne (PilzBuddy-Muster): melden kann man immer, also
          // steht sie immer da — klein, unten links, wo weder die
          // Attribution (rechts) noch die Banner (oben) liegen. Der
          // Orte-Filter steht aus demselben Grund darüber.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (officialOn && official.unavailable)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Text('Offizielle Trails gerade nicht erreichbar'),
                        ),
                      ),
                    if (poiUnavailable)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Text('Orte gerade nicht erreichbar'),
                        ),
                      ),
                    FloatingActionButton.small(
                      heroTag: 'locate',
                      tooltip: 'Meine Position',
                      onPressed: _locateMe,
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'poi-filter',
                      tooltip: 'Ebenen und Orte',
                      onPressed: () => showPoiFilterSheet(context),
                      child: const Icon(Icons.layers_outlined),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'feedback',
                      tooltip: 'Idee oder Fehler melden',
                      onPressed: () => showFeedbackFlow(context, ref),
                      child: const Icon(Icons.lightbulb_outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Der Punkt der eigenen Position über allem, darunter ihr
/// Genauigkeitskreis. Beides fängt keine Tipps ab — ein Tipp auf einen
/// Trail unter dem Punkt soll den Trail treffen.
List<Widget> _positionLayers(Position p) {
  final at = LatLng(p.latitude, p.longitude);
  return [
    if (p.accuracy > 0)
      IgnorePointer(
        child: CircleLayer(circles: [
          CircleMarker(
            point: at,
            radius: p.accuracy,
            useRadiusInMeter: true,
            color: AppColors.positionDot.withValues(alpha: 0.12),
            borderColor: AppColors.positionDot.withValues(alpha: 0.35),
            borderStrokeWidth: 1,
          ),
        ]),
      ),
    IgnorePointer(
      child: MarkerLayer(markers: [
        Marker(
          key: const ValueKey('my-position'),
          point: at,
          width: 22,
          height: 22,
          child: const _PositionDot(),
        ),
      ]),
    ),
  ];
}

class _PositionDot extends StatelessWidget {
  const _PositionDot();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Deine Position',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.positionDot,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
          ),
        ),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Noch keine Trails. Importiere deine GPX-Dateien im Profil '
                'oder verbinde dich mit Buddys — du siehst, was sie gefahren sind.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      );
}
