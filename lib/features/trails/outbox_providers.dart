// Der Ausgangskorb in der App (#30): die wartenden Aufträge als Zustand,
// und wie sie auf Karte und Liste aussehen — als Trails, die sich von
// übertragenen nur durch `pending` unterscheiden.
//
// **Warum sie sichtbar sind:** Ohne das steuert man dieselbe Datei
// zweimal bei, weil man nicht sieht, dass sie schon erfasst ist. Genau
// der Fehler, den der Korb verhindern soll.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/outbox.dart';
import '../../data/providers.dart';
import '../../models/trail.dart';
import 'trail_geometry.dart';

/// Datei auf Android, im Browser bewusst KEIN Korb (#30): Dort wirft
/// `append`, und der Netzfehler erscheint wie bisher. IndexedDB wie in
/// PilzBuddy (#386) ist ein eigener Schritt.
final outboxProvider =
    Provider<Outbox>((ref) => kIsWeb ? const NoOutbox() : FileOutbox());

/// Die Aufträge im Korb — gelesen beim Start, geändert nur über diesen
/// Notifier, damit Anzeige und Datei nie auseinanderlaufen.
class OutboxJobsNotifier extends AsyncNotifier<List<OutboxJob>> {
  @override
  Future<List<OutboxJob>> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const [];
    return ref.read(outboxProvider).read(uid: uid);
  }

  /// Legt einen Auftrag ab. **Wirft**, wenn er nicht sicher liegt — der
  /// Aufrufer meldet dann den ursprünglichen Netzfehler.
  ///
  /// Ein zweiter Beitrag zum SELBEN Trail ersetzt den ersten: Der Nutzer
  /// hat seine Meinung geändert, nicht zwei Meinungen.
  Future<void> append(OutboxJob job) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) throw StateError('nicht angemeldet');
    final outbox = ref.read(outboxProvider);
    final current = await outbox.read(uid: uid);
    final trailId = job is DetailsJob ? job.details.trailId : null;
    final kept = [
      for (final j in current)
        if (!(trailId != null && j is DetailsJob && j.details.trailId == trailId)) j,
    ];
    final next = [...kept, job];
    if (next.length == current.length + 1) {
      await outbox.append(job, uid: uid);
    } else {
      await outbox.replaceAll(next, uid: uid);
    }
    state = AsyncData(next);
  }

  /// Nimmt einen Auftrag zurück — „doch nicht", oder einer, den der
  /// Server dauerhaft ablehnt.
  Future<void> discard(String id) => _rewrite((jobs) => [for (final j in jobs) if (j.id != id) j]);

  /// Ein abgelehnter Auftrag noch einmal, von vorn.
  Future<void> retry(String id) => _rewrite((jobs) => [
        for (final j in jobs) j.id == id ? j.copyWith(attempts: 0, clearFailure: true) : j,
      ]);

  Future<void> _rewrite(List<OutboxJob> Function(List<OutboxJob>) change) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final outbox = ref.read(outboxProvider);
    final next = change(await outbox.read(uid: uid));
    await outbox.replaceAll(next, uid: uid);
    state = AsyncData(next);
  }

  /// Nach einem Lauf der Wiedervorlage: was die Datei jetzt sagt.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final outboxJobsProvider =
    AsyncNotifierProvider<OutboxJobsNotifier, List<OutboxJob>>(OutboxJobsNotifier.new);

/// Wie viele Aufträge warten — die Zahl im Banner.
final pendingJobCountProvider =
    Provider<int>((ref) => ref.watch(outboxJobsProvider).valueOrNull?.length ?? 0);

/// Aufträge, die der Server dauerhaft abgelehnt hat: Sie brauchen eine
/// Entscheidung von Hand und verschwinden nicht von allein.
final failedJobCountProvider = Provider<int>((ref) =>
    ref.watch(outboxJobsProvider).valueOrNull?.where((j) => j.failure != null).length ?? 0);

/// Die Trails des Servers plus die, die noch im Korb liegen (Konzept
/// 4.7: „steht als eigener Trail auf der Karte, bis er hochgeht").
///
/// Ein wartender Beitrag ([DetailsJob]) überlagert die eigene Zeile des
/// Trails: Man sieht, was man eingetragen hat, mit dem Vermerk, dass es
/// noch nicht übertragen ist. Rein und ohne Riverpod, damit die Zuordnung
/// ohne Backend prüfbar ist.
List<Trail> withPendingJobs(List<Trail> server, List<OutboxJob> jobs, {required String myId}) {
  if (jobs.isEmpty) return server;
  final detailsByTrail = <String, DetailsJob>{
    for (final j in jobs)
      if (j is DetailsJob) j.details.trailId: j,
  };
  final result = <Trail>[
    for (final t in server)
      detailsByTrail.containsKey(t.id)
          ? Trail(
              id: t.id,
              recordings: t.recordings,
              details: [
                for (final d in t.details)
                  if (d.userId != myId) d,
                detailsByTrail[t.id]!.details,
              ],
              myId: myId,
              notes: t.notes,
              pendingDetails: true,
            )
          : t,
  ];
  for (final j in jobs) {
    if (j is! ContributeJob) continue;
    final points = <LatLng>[
      for (var i = 0; i + 1 < j.coords.length; i += 2) LatLng(j.coords[i + 1], j.coords[i]),
    ];
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += haversineM(points[i - 1].latitude, points[i - 1].longitude,
          points[i].latitude, points[i].longitude);
    }
    result.add(Trail(
      id: j.id,
      recordings: [
        TrailRecording(
          id: 'pending-${j.id}',
          trailId: j.id,
          userId: myId,
          source: j.source,
          recordedAt: j.recordedAt?.toLocal(),
          reversed: false,
          quality: 0,
          createdAt: j.createdAt.toLocal(),
          points: points,
          lengthM: length,
          ele: j.eles,
        ),
      ],
      details: [
        TrailDetails(
            trailId: j.id,
            userId: myId,
            name: (j.name ?? '').trim().isEmpty ? null : clampTrailName(j.name!)),
      ],
      myId: myId,
      pending: true,
      pendingFailure: j.failure,
    ));
  }
  return result..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
}
