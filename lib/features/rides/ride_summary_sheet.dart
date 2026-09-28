// Das Abschluss-Blatt der Fahrt (#28): was aufgezeichnet wurde, und ob
// es bleibt. Gespeichert IST die Fahrt schon, wenn das Blatt aufgeht —
// „Verwerfen" löscht, „Behalten" tut nichts. Wer das Blatt wegwischt,
// behält.
//
// Was aus der Fahrt WIRD — welche Trails wieder gefahren, wo ein neuer
// Kandidat liegt — kommt mit dem Zerlege-Blatt (#29). Bis dahin sagt das
// Blatt das, statt so zu tun, als sei die Fahrt schon ein Beitrag.
import 'package:flutter/material.dart';

import '../../core/geo.dart';
import 'ride_track.dart';

/// Zeigt das Blatt; `true` heißt „verwerfen".
Future<bool> showRideSummarySheet(BuildContext context, Ride ride) async {
  final discard = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => _RideSummarySheet(ride),
  );
  return discard ?? false;
}

class _RideSummarySheet extends StatelessWidget {
  const _RideSummarySheet(this.ride);

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fahrt beendet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${formatMeters(ride.lengthM)} · ${rideDurationLabel(ride.duration)} · '
              '${ride.points.length} Punkte',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Die Fahrt liegt auf deinem Gerät unter „Meine Fahrten" im Profil '
              'und verlässt es nicht. Welche Trails du wieder gefahren bist und '
              'wo ein neuer liegt, zeigt bald das Zerlege-Blatt — bis dahin '
              'bleibt sie, wie sie ist.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Verwerfen'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Behalten'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
