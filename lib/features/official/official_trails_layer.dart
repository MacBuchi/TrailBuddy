import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/geo.dart';
import '../trails/trail_sheet.dart' show formatElevation;
import 'official_trails.dart';
import 'official_trails_source.dart';

/// Die offiziellen Trails als gestrichelte Linien — eine Ebene INNERHALB
/// von `FlutterMap`, damit sie die Kamera kennt. Ab [kOfficialMinZoom]
/// lädt sie, was der Ausschnitt braucht, kurz verzögert wie die Orte.
/// Sie liegt über den Orten und unter den Trails des Netzes.
class OfficialTrailsLayer extends ConsumerStatefulWidget {
  const OfficialTrailsLayer({super.key, required this.hits});

  /// Wird von der Karte gelesen: Ein Tipp, der keinen Trail des Netzes
  /// trifft, öffnet den offiziellen darunter.
  final LayerHitNotifier<OfficialTrail> hits;

  @override
  ConsumerState<OfficialTrailsLayer> createState() => _OfficialTrailsLayerState();
}

class _OfficialTrailsLayerState extends ConsumerState<OfficialTrailsLayer> {
  Timer? _debounce;
  String? _requested;

  static const _delay = Duration(milliseconds: 500);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final enabled = ref.watch(officialTrailsEnabledProvider);
    final state = ref.watch(officialTrailsControllerProvider);
    if (!enabled || camera.zoom < kOfficialMinZoom) {
      _debounce?.cancel();
      _requested = null;
      return const SizedBox.shrink();
    }
    final b = camera.visibleBounds;
    final view = (s: b.south, w: b.west, n: b.north, e: b.east);
    // Nur fragen, wenn der Ausschnitt eine noch fehlende Region berührt
    // (oder der Index fehlt) — sonst wäre jedes Verschieben ein Aufruf.
    final index = state.index;
    final missing = index == null ||
        index.regions.any((r) =>
            !state.byRegion.containsKey(r.id) && r.touches(view.s, view.w, view.n, view.e));
    // Je Ausschnitt EIN Versuch: Ohne Netz änderte sonst jede Antwort den
    // Zustand, der Neuaufbau fragte wieder — alle halbe Sekunde.
    final key = '${view.s},${view.w},${view.n},${view.e}';
    if (missing && key != _requested) {
      _requested = key;
      _debounce?.cancel();
      _debounce = Timer(_delay, () {
        if (mounted) ref.read(officialTrailsControllerProvider.notifier).ensure(view);
      });
    }
    return PolylineLayer<OfficialTrail>(
      hitNotifier: widget.hits,
      polylines: [
        for (final t in state.trails)
          for (final s in t.sections)
            Polyline<OfficialTrail>(
              points: s.points,
              color: s.closed ? Colors.grey.shade600 : AppColors.officialViolet,
              strokeWidth: s.variant ? 2.5 : 3.5,
              pattern: StrokePattern.dashed(segments: const [10, 6]),
              hitValue: t,
            ),
      ],
    );
  }
}

/// Die Aussage über den Status — immer mit der Quelle, denn sie kommt von
/// dort und nicht von einem Buddy.
String officialStatusLine(OfficialStatus status, String by) => switch (status) {
      OfficialStatus.open => 'Freigegeben laut $by.',
      OfficialStatus.partlyClosed =>
        'Teilweise gesperrt laut $by — die gesperrten Teile sind grau.',
      OfficialStatus.closed => 'Gesperrt laut $by.',
    };

/// Das Blatt eines offiziellen Trails: was die Quelle sagt, und von wem.
/// Keine Beiträge, keine Hinweise, kein Status eines Buddys — dafür gibt
/// es die Trails des Netzes (Konzept offizielle Trails 5.3).
Future<void> showOfficialTrailSheet(BuildContext context, OfficialTrail trail) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _OfficialTrailSheet(trail),
    );

class _OfficialTrailSheet extends ConsumerWidget {
  const _OfficialTrailSheet(this.trail);

  final OfficialTrail trail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(officialTrailsControllerProvider).sourceOf(trail);
    final by = source?.attribution ?? 'Quelle';
    final text = Theme.of(context).textTheme;
    final facts = [
      if (trail.lengthM != null) formatMeters(trail.lengthM!),
      if (trail.downM != null && trail.upM != null)
        formatElevation((gain: trail.upM!, loss: trail.downM!)),
    ];
    final url = source?.url;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trail.name, style: text.titleLarge),
              const SizedBox(height: 4),
              Text('Offizieller Singletrail', style: text.bodyMedium),
              if (facts.isNotEmpty) Text(facts.join(' · '), style: text.bodyMedium),
              if (trail.difficulty != null)
                Text('Schwierigkeit laut Quelle: ${trail.difficulty}',
                    style: text.bodyMedium),
              const SizedBox(height: 8),
              Row(children: [
                Icon(
                  trail.status == OfficialStatus.open
                      ? Icons.verified_outlined
                      : Icons.block,
                  size: 18,
                  color: trail.status == OfficialStatus.open
                      ? AppColors.officialViolet
                      : Colors.grey.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(officialStatusLine(trail.status, by),
                        style: text.bodyMedium)),
              ]),
              if (trail.description != null) ...[
                const SizedBox(height: 8),
                Text(trail.description!, style: text.bodyMedium),
              ],
              const SizedBox(height: 12),
              // Konzept 6.3: Die Ebene sagt nur etwas über ihre eigenen
              // Linien, nie über die übrigen Trails.
              Text(
                'Ausgewiesen laut Quelle. Über andere Trails sagt diese '
                'Ebene nichts.',
                style: text.bodySmall,
              ),
              if (source != null)
                Text(
                  'Quelle: ${source.name} · ${source.license}'
                  '${trail.updated == null ? '' : ' · Stand ${formatIsoDateDe(trail.updated!)}'}',
                  style: text.bodySmall,
                ),
              if (url != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Bei der Quelle ansehen'),
                    onPressed: () => launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
