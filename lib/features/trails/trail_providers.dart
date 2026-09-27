import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../data/providers.dart';
import '../../data/trail_repository.dart';
import '../../models/trail.dart';
import 'elevation_backfill.dart';
import 'gpx.dart';
import 'trail_geometry.dart';

final trailRepositoryProvider = Provider<TrailRepository>(
    (ref) => SupabaseTrailRepository(ref.watch(supabaseClientProvider)));

/// Alle Trails meines Netzes — eigene Belege plus die meiner Buddys, so
/// wie die RLS sie liefert. Zwei Abfragen, gruppiert im Client.
class TrailsNotifier extends AsyncNotifier<List<Trail>>
    with ReadAfterWrite<List<Trail>> {
  @override
  Future<List<Trail>> build() async {
    final myId = ref.watch(currentUserIdProvider);
    if (myId == null) return const [];
    final repo = ref.watch(trailRepositoryProvider);
    final results = await Future.wait([repo.fetchRecordings(), repo.fetchDetails()]);
    return buildTrails(
      recordings: results[0] as List<TrailRecording>,
      details: results[1] as List<TrailDetails>,
      myId: myId,
    );
  }

  /// Steuert eine Spur bei: vereinfacht (mit Höhe, siehe [simplify]),
  /// schickt Linie und Höhen an die RPC und legt
  /// den eigenen Beitrag mit dem Namen aus der Datei an. Gibt die
  /// Trail-Kennung zurück. Wirft, wenn das SCHREIBEN scheitert; ein
  /// gescheitertes Neuladen meldet der Rückgabewert von [reloadAfterWrite]
  /// beim Aufrufer.
  Future<String> contribute(GpxTrack track, {String? clientId}) async {
    final repo = ref.read(trailRepositoryProvider);
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) throw const NotSignedInException();
    final pts = simplify(track.points);
    final source = sourceOf(track.points);
    final recordedAt =
        source == RecordingSource.planned ? null : track.points.first.time;
    final trailId = await repo.contribute(
      coords: flatCoords(pts),
      eles: trackElevations(pts),
      source: source,
      recordedAt: recordedAt,
      clientId: clientId ?? newClientId(),
    );
    final name = track.name.trim();
    if (name.isNotEmpty) {
      final existing = state.valueOrNull
          ?.where((t) => t.id == trailId)
          .firstOrNull
          ?.myDetails;
      // Ein vorhandener eigener Name bleibt — der Import überschreibt
      // nicht, was jemand bewusst eingetragen hat.
      if (existing == null || (existing.name ?? '').trim().isEmpty) {
        await repo.saveDetails(
            (existing ?? TrailDetails(trailId: trailId, userId: myId))
                .copyWith(name: name));
      }
    }
    return trailId;
  }

  Future<bool> saveDetails(TrailDetails details) async {
    await ref.read(trailRepositoryProvider).saveDetails(details);
    return reloadAfterWrite('Trail-Beitrag speichern');
  }

  /// Höhen einer eigenen Aufzeichnung nachtragen (#16). Kein Neuladen
  /// hier: Der Import lädt einmal am Ende, nicht nach jeder Datei.
  Future<bool> attachElevation(ExistingRecording existing) {
    final eles = existing.eles;
    if (eles == null) throw StateError('Datei ohne vollständige Höhen');
    return ref.read(trailRepositoryProvider).attachElevation(
          recordingId: existing.recording.id,
          coords: flatCoords(existing.points),
          eles: eles,
        );
  }
}

final trailsProvider =
    AsyncNotifierProvider<TrailsNotifier, List<Trail>>(TrailsNotifier.new);

final trailByIdProvider = Provider.family<Trail?, String>((ref, id) =>
    ref.watch(trailsProvider).valueOrNull?.where((t) => t.id == id).firstOrNull);

/// Wunsch der Liste an die Karte: diesen Trail zeigen (Muster PilzBuddy
/// #345, erst Reiter wechseln, dann Wunsch stellen).
final mapFocusTrailProvider = StateProvider<String?>((ref) => null);

/// UUID v4 aus `Random.secure()` — die Kennung des Auftrags, damit ein
/// Wiederholversuch nach abgerissener Antwort keinen zweiten Beleg anlegt
/// (Idempotenz in `contribute_recording`, PilzBuddy Patch 016).
String newClientId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final h = List.generate(16, hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
