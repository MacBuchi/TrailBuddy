// „Meine Fahrten" (#28): was auf dem Gerät liegt — ansehen, auf der
// Karte zeigen, löschen. Die Liste ist das Gegenstück zur Zusage „die
// Fahrt bleibt auf dem Gerät": Was bleibt, muss man sehen und loswerden
// können.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/geo.dart';
import '../../core/router_branches.dart';
import '../../core/widgets/motion.dart';
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
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Noch keine Fahrt. Starte eine auf der Karte mit dem '
                'Aufnahme-Knopf — sie bleibt auf deinem Gerät.',
              ),
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

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fahrt löschen?'),
        content: const Text('Die Aufzeichnung wird vom Gerät gelöscht. '
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: ValueKey('ride-${ride.id}'),
      leading: const Icon(Icons.directions_bike),
      title: Text(_date.format(ride.startedAt.toLocal())),
      subtitle: Text('${formatMeters(ride.lengthM)} · '
          '${rideDurationLabel(ride.duration)} · ${ride.points.length} Punkte'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
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
        IconButton(
          tooltip: 'Fahrt löschen',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _delete(context, ref),
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
