// „Meine Fahrten" (#28): was auf dem Gerät liegt — ansehen, auf der
// Karte zeigen, löschen. Die Liste ist das Gegenstück zur Zusage „die
// Fahrt bleibt auf dem Gerät": Was bleibt, muss man sehen und loswerden
// können.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/geo.dart';
import '../../core/gpx_share.dart';
import '../../core/router_branches.dart';
import '../../core/widgets/motion.dart';
import '../help/help_link.dart';
import '../trails/gpx_writer.dart';
import 'ride_export.dart';
import 'ride_providers.dart';
import 'ride_split_sheet.dart';
import 'ride_track.dart';

class RidesScreen extends ConsumerWidget {
  const RidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridesAsync = ref.watch(ridesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Fahrten')),
      body: ridesAsync.when(
        loading: () => const CenteredTrailLoader(),
        error: (e, _) => const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Die Fahrten ließen sich nicht lesen.'),
        ),
        data: (rides) {
          if (rides.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                Text(
                  'Noch keine Fahrt. Starte eine auf der Karte mit dem '
                  'Aufnahme-Knopf — sie bleibt auf deinem Gerät.',
                ),
                SizedBox(height: 8),
                HelpLinkButton(),
              ],
            );
          }
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Fahrten liegen nur auf diesem Gerät. Beigesteuert wird '
                  'nie eine ganze Fahrt, nur ein Stück, das einen Trail belegt '
                  '— „Zerlegen" zeigt, welche.',
                ),
              ),
              for (final r in rides) _RideTile(r),
            ],
          );
        },
      ),
    );
  }
}

class _RideTile extends ConsumerWidget {
  const _RideTile(this.ride);

  final Ride ride;

  static final _date = DateFormat('EEEE, d. MMMM yyyy, HH:mm', 'de');
  static final _day = DateFormat('d. MMMM yyyy', 'de');

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ride.planned ? 'Geplante Fahrt löschen?' : 'Fahrt löschen?'),
        content: Text(ride.planned
            ? 'Die geplante Runde wird vom Gerät gelöscht.'
            : 'Die Aufzeichnung wird vom Gerät gelöscht. '
                'Beigesteuerte Trails bleiben davon unberührt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(ridesProvider.notifier).delete(ride.id);
    if (ref.read(mapFocusRideProvider)?.id == ride.id) {
      ref.read(mapFocusRideProvider.notifier).state = null;
    }
  }

  /// Die ganze Fahrt als GPX, mit roher GPS-Höhe (#150) — die Sicherung
  /// aus Konzept 10.4, über das Teilen-Blatt des Systems.
  Future<void> _export(BuildContext context, WidgetRef ref) {
    final track = rideToGpx(ride);
    return shareGpx(context, ref,
        fileName: rideExportFileName(ride),
        xml: writeGpx(name: track.name, points: track.points));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eine geplante Fahrt (#158 Schritt 5) ist eine Linie, keine Messung:
    // ihr Name statt des Datums, „etwa" vor der Zeit, keine Schere — zerlegt
    // wird, was gefahren wurde, und das ist dann eine eigene Aufzeichnung.
    final planned = ride.planned;
    return ListTile(
      key: ValueKey('ride-${ride.id}'),
      leading: Icon(planned ? Icons.route_outlined : Icons.directions_bike),
      title: Text(planned ? (ride.name ?? 'Geplante Fahrt') : _date.format(ride.startedAt.toLocal())),
      subtitle: Text(planned
          ? 'Geplant am ${_day.format(ride.startedAt.toLocal())} · ${formatMeters(ride.lengthM)} · '
              'etwa ${rideDurationLabel(ride.duration)}'
          : '${formatMeters(ride.lengthM)} · '
              '${rideDurationLabel(ride.duration)} · ${ride.points.length} Punkte'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!planned)
          IconButton(
            key: ValueKey('ride-split-${ride.id}'),
            tooltip: 'Fahrt zerlegen',
            icon: const Icon(Icons.content_cut),
            onPressed: () {
              // Erst der Reiter, dann der Wunsch — wie „auf der Karte zeigen".
              StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
              ref.read(mapSplitRequestProvider.notifier).state = SplitRequest.fromRide(ride);
            },
          ),
        // Exportieren und Löschen in einem Menü (#150): Drei Symbole
        // nebeneinander ließen auf einem kleinen Telefon vom Datum
        // nichts mehr übrig.
        PopupMenuButton<String>(
          key: ValueKey('ride-menu-${ride.id}'),
          tooltip: 'Mehr',
          onSelected: (value) => switch (value) {
            'export' => _export(context, ref),
            _ => _delete(context, ref),
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              key: ValueKey('ride-export-${ride.id}'),
              value: 'export',
              child: const ListTile(
                  leading: Icon(Icons.share_outlined), title: Text('Als GPX exportieren')),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(planned ? 'Geplante Fahrt löschen' : 'Fahrt löschen')),
            ),
          ],
        ),
      ]),
      onTap: () {
        // Erst der Reiter, dann der Wunsch (PilzBuddy #345).
        StatefulNavigationShell.of(context).goBranch(kMapBranchIndex);
        ref.read(mapFocusRideProvider.notifier).state = ride;
      },
    );
  }
}
