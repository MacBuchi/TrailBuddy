import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../models/trail.dart';
import '../trails/trail_providers.dart';
import '../trails/trail_sheet.dart';
import '../update/update_banner.dart';
import 'map_providers.dart';

/// Die Karte: OSM-Raster, darüber die Trails des eigenen Netzes als
/// Linien. Eigene grün, nur von Buddys belegte blau, gesperrte oder
/// zerstörte in Warnfarbe — die Farbe sagt, was ICH damit zu tun habe,
/// nicht, wie gut der Trail ist.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _controller = MapController();
  final LayerHitNotifier<String> _hits = ValueNotifier(null);
  bool _fittedOnce = false;

  static const _dachCenter = LatLng(48.8, 10.5);

  @override
  void dispose() {
    _hits.dispose();
    _controller.dispose();
    super.dispose();
  }

  Color _colorOf(Trail t) {
    if (t.status.warns) return AppColors.warningAmber;
    return t.isOwn ? AppColors.trailGreen : AppColors.friendBlue;
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
              onTap: (_, _) {
                final hit = _hits.value;
                final id = hit?.hitValues.firstOrNull;
                if (id == null) return;
                final trail = ref.read(trailByIdProvider(id));
                if (trail != null) showTrailSheet(context, trail);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.mcbuchi.trailbuddy',
                tileProvider: ref.watch(mapTileProviderProvider),
              ),
              PolylineLayer<String>(
                hitNotifier: _hits,
                polylines: [
                  for (final t in trails)
                    Polyline<String>(
                      points: t.points,
                      color: _colorOf(t),
                      strokeWidth: 4,
                      hitValue: t.id,
                    ),
                ],
              ),
              const RichAttributionWidget(
                animationConfig: ScaleRAWA(),
                attributions: [
                  TextSourceAttribution('OpenStreetMap-Mitwirkende'),
                ],
              ),
            ],
          ),
          if (trailsAsync.isLoading && trails.isEmpty)
            const Center(child: CircularProgressIndicator()),
          if (trailsAsync.hasValue && trails.isEmpty)
            const _EmptyHint(),
          const UpdateBanner(),
        ],
      ),
    );
  }
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
