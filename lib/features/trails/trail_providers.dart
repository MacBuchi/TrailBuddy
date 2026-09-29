import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../core/settings.dart';
import '../../data/outbox.dart';
import '../../data/outbox_runner.dart';
import '../../data/providers.dart';
import '../../data/trail_cache.dart';
import '../../data/trail_repository.dart';
import '../../models/trail.dart';
import 'elevation_backfill.dart';
import 'gpx.dart';
import 'outbox_providers.dart';
import 'trail_geometry.dart';
import 'trail_list.dart';

final trailRepositoryProvider = Provider<TrailRepository>(
    (ref) => SupabaseTrailRepository(ref.watch(supabaseClientProvider)));

/// Was aus einem Schreibvorgang geworden ist (#30).
enum WriteOutcome {
  /// Auf dem Server, Liste frisch.
  done,

  /// Auf dem Server, aber das Neuladen scheiterte — die Liste ist alt
  /// ([staleAfterWriteHint]).
  doneStale,

  /// Kein Netz: liegt im Ausgangskorb und geht, sobald wieder Verbindung
  /// besteht.
  queued,
}

/// Ergebnis von [TrailsNotifier.contribute]: die Trail-Kennung — bei
/// [queued] die des Auftrags, unter der der wartende Trail auf der Karte
/// steht.
typedef ContributeResult = ({String trailId, bool queued});

/// Alle Trails meines Netzes — eigene Belege plus die meiner Buddys, so
/// wie die RLS sie liefert, dazu die Aufträge aus dem Ausgangskorb
/// (#30) als wartende Trails. Zwei Abfragen, gruppiert im Client.
class TrailsNotifier extends AsyncNotifier<List<Trail>>
    with ReadAfterWrite<List<Trail>> {
  /// Der letzte erfolgreiche Stand vom Server — die Grundlage, auf die
  /// der Korb gelegt wird, ohne dafür neu zu laden.
  List<Trail> _server = const [];

  @override
  Future<List<Trail>> build() async {
    final myId = ref.watch(currentUserIdProvider);
    if (myId == null) return const [];
    // Ändert sich der Korb, wird NICHT neu vom Server geladen — ein
    // Auftrag entsteht ja gerade, weil es kein Netz gibt. Der Korb wird
    // auf den letzten bekannten Stand gelegt.
    ref.listen(outboxJobsProvider, (_, next) {
      final jobs = next.valueOrNull;
      if (jobs != null) _applyPending(jobs, myId);
    });
    final repo = ref.watch(trailRepositoryProvider);
    // Netz zuerst, ohne Empfang die Kopie vom letzten Mal (#32) — ein
    // Serverfehler bleibt sichtbar, `fetchWithCache` liest die Kopie nur
    // bei `looksOffline`.
    final result = await fetchWithCache(
      fetch: () async {
        final results = await Future.wait(
            [repo.fetchRecordings(), repo.fetchDetails(), repo.fetchNotes()]);
        return (
          recordings: results[0] as List<TrailRecording>,
          details: results[1] as List<TrailDetails>,
          notes: results[2] as List<TrailNote>,
        );
      },
      cache: ref.read(trailCacheProvider),
      uid: myId,
      now: DateTime.now(),
    );
    ref.read(trailsCachedAtProvider.notifier).set(result.cachedAt);
    _server = buildTrails(
      recordings: result.snapshot.recordings,
      details: result.snapshot.details,
      notes: result.snapshot.notes,
      myId: myId,
    );
    final cached = ref.read(outboxJobsProvider).valueOrNull;
    final List<OutboxJob> jobs = cached ?? await ref.read(outboxJobsProvider.future);
    return withPendingJobs(_server, jobs, myId: myId);
  }

  void _applyPending(List<OutboxJob> jobs, String myId) {
    // Ohne je einen Server-Stand und ohne Aufträge gibt es nichts zu
    // zeigen — der Fehlerzustand bleibt dann stehen.
    if (!state.hasValue && jobs.isEmpty) return;
    state = AsyncData(withPendingJobs(_server, jobs, myId: myId));
  }

  /// Steuert eine Spur bei: vereinfacht (mit Höhe, siehe [simplify]),
  /// schickt Linie und Höhen an die RPC und legt den eigenen Beitrag mit
  /// dem Namen aus der Datei an. Ohne Netz wandert der Auftrag in den
  /// Ausgangskorb (#30) und der Trail steht sofort als wartender auf der
  /// Karte. Wirft, wenn das SCHREIBEN aus einem anderen Grund scheitert;
  /// ein gescheitertes Neuladen meldet der Rückgabewert von
  /// [reloadAfterWrite] beim Aufrufer.
  ///
  /// [source] steht fest, wenn die Spur aus der eigenen Aufzeichnung
  /// kommt (`app`, Zerlege-Blatt #29); sonst entscheidet die Datei
  /// ([sourceOf]). [grade] geht mit dem Namen in den eigenen Beitrag.
  Future<ContributeResult> contribute(GpxTrack track,
      {String? clientId, RecordingSource? source, int? grade}) async {
    final repo = ref.read(trailRepositoryProvider);
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) throw const NotSignedInException();
    final pts = simplify(track.points);
    source ??= sourceOf(track.points);
    final recordedAt =
        source == RecordingSource.planned ? null : track.points.first.time;
    // Der Auftrag entsteht VOR dem Sendeversuch, mit seiner Kennung: So
    // trägt schon der erste Versuch die `client_id`, und ein Abriss nach
    // dem Insert legt beim Nachholen keine zweite Aufzeichnung an.
    final job = ContributeJob(
      id: clientId ?? newClientId(),
      createdAt: DateTime.now().toUtc(),
      coords: flatCoords(pts),
      eles: trackElevations(pts),
      source: source,
      recordedAt: recordedAt,
      name: track.name,
      grade: grade,
    );
    try {
      final trailId = await repo.contribute(
        coords: job.coords,
        eles: job.eles,
        source: job.source,
        recordedAt: job.recordedAt,
        clientId: job.id,
      );
      await adoptDetails(trailId, track.name, grade: grade);
      return (trailId: trailId, queued: false);
    } catch (error, stackTrace) {
      await _queueIfOffline(error, stackTrace, job);
      return (trailId: job.id, queued: true);
    }
  }

  /// Nur `looksOffline` führt in den Korb; alles andere wirft weiter,
  /// samt dem Fall, dass der Korb selbst nicht schreiben kann.
  Future<void> _queueIfOffline(Object error, StackTrace stackTrace, OutboxJob job) async {
    if (!looksOffline(error)) Error.throwWithStackTrace(error, stackTrace);
    try {
      await ref.read(outboxJobsProvider.notifier).append(job);
    } catch (_) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Arbeitet den Ausgangskorb ab und lädt danach neu. Angestoßen beim
  /// Start, bei der Rückkehr der Verbindung und auf Tippen im Banner;
  /// Doppelläufe hält der Runner auseinander.
  Future<OutboxRunResult> sendOutbox() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return (sent: 0, remaining: 0, failed: 0);
    // Den Korb ABWARTEN, nicht den Zähler lesen: Beim Kartenstart ist er
    // noch nicht geladen, und ein Zähler von 0 hieße dann „nichts zu tun".
    final jobs = await ref.read(outboxJobsProvider.future);
    if (jobs.isEmpty) return (sent: 0, remaining: 0, failed: 0);
    final result = await ref.read(outboxRunnerProvider).run(uid: uid);
    await ref.read(outboxJobsProvider.notifier).refresh();
    if (result.sent > 0) await reloadAfterWrite('Trails nach dem Ausgangskorb laden');
    return result;
  }

  /// Übernimmt den Namen aus der Datei als eigenen Namen des Trails —
  /// gekürzt auf [kTrailNameMaxLength]. Ein vorhandener eigener Name
  /// bleibt: Der Import überschreibt nicht, was jemand bewusst eingetragen
  /// hat. Kein Neuladen hier (der Import lädt einmal am Ende). Gibt
  /// zurück, ob geschrieben wurde.
  Future<bool> adoptName(String trailId, String fileName) => adoptDetails(trailId, fileName);

  /// Wie [adoptName], dazu der S-Grad aus dem Zerlege-Blatt (#29): Der
  /// wird immer gesetzt — wer ihn gewählt hat, hat ihn gerade gefahren.
  /// EIN Schreibvorgang für beides.
  Future<bool> adoptDetails(String trailId, String fileName, {int? grade}) async {
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) throw const NotSignedInException();
    final name = clampTrailName(fileName);
    final existing = state.valueOrNull
        ?.where((t) => t.id == trailId)
        .firstOrNull
        ?.myDetails;
    final keepName = existing != null && (existing.name ?? '').trim().isNotEmpty;
    final writesName = name.isNotEmpty && !keepName;
    if (!writesName && grade == null) return false;
    var details = existing ?? TrailDetails(trailId: trailId, userId: myId);
    if (writesName) details = details.copyWith(name: name);
    if (grade != null) details = details.copyWith(grade: grade);
    await ref.read(trailRepositoryProvider).saveDetails(details);
    return true;
  }

  /// Speichert den eigenen Beitrag; ein [note] (etwa zum geänderten
  /// Status) geht als Hinweis mit — ein Neuladen für beides. Ohne Netz
  /// wartet beides zusammen im Ausgangskorb (#30).
  Future<WriteOutcome> saveDetails(TrailDetails details, {String? note}) async {
    final repo = ref.read(trailRepositoryProvider);
    final text = note?.trim() ?? '';
    try {
      await repo.saveDetails(details);
      if (text.isNotEmpty) {
        await repo.addNote(trailId: details.trailId, body: text);
      }
    } catch (error, stackTrace) {
      await _queueIfOffline(
          error,
          stackTrace,
          DetailsJob(
              id: newClientId(),
              createdAt: DateTime.now().toUtc(),
              details: details,
              note: text.isEmpty ? null : text));
      return WriteOutcome.queued;
    }
    return await reloadAfterWrite('Trail-Beitrag speichern')
        ? WriteOutcome.done
        : WriteOutcome.doneStale;
  }

  Future<bool> addNote(String trailId, String body) async {
    await ref
        .read(trailRepositoryProvider)
        .addNote(trailId: trailId, body: body.trim());
    return reloadAfterWrite('Hinweis speichern');
  }

  Future<bool> deleteNote(String id) async {
    await ref.read(trailRepositoryProvider).deleteNote(id);
    return reloadAfterWrite('Hinweis löschen');
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

/// Die Kopie des Netzes (#32): Datei auf Android, im Browser bewusst
/// keine (IndexedDB wie PilzBuddy #385 ist ein eigener Schritt).
final trailCacheProvider =
    Provider<TrailCache>((ref) => kIsWeb ? const NoTrailCache() : FileTrailCache());

/// Wann der angezeigte Stand geholt wurde — `null`, solange er frisch aus
/// dem Netz kommt. Karte und Liste sagen es, sonst hielte man einen alten
/// Stand für den aktuellen.
class TrailsCachedAtNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? at) => state = at;
}

final trailsCachedAtProvider =
    NotifierProvider<TrailsCachedAtNotifier, DateTime?>(TrailsCachedAtNotifier.new);

/// Die Wiedervorlage (#30). Den Namen übernimmt sie über den Notifier,
/// der den Bestand kennt und keinen bewusst eingetragenen überschreibt.
final outboxRunnerProvider = Provider<OutboxRunner>((ref) => OutboxRunner(
      repository: ref.watch(trailRepositoryProvider),
      outbox: ref.watch(outboxProvider),
      adoptDetails: (trailId, name, grade) =>
          ref.read(trailsProvider.notifier).adoptDetails(trailId, name, grade: grade),
    ));

final trailByIdProvider = Provider.family<Trail?, String>((ref, id) =>
    ref.watch(trailsProvider).valueOrNull?.where((t) => t.id == id).firstOrNull);

/// Die Hinweise, die auf DIESEM Gerät schon im Trail-Blatt zu sehen
/// waren (#7): Sie heben den Trail in Karte und Liste nicht mehr hervor.
/// Gerätelokal wie der Orte-Filter — gelesen ist eine Frage des Geräts,
/// nicht des Kontos, und der Server erfährt nicht, wer was gelesen hat.
class SeenNotesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {...?ref.read(settingsProvider).seenNoteIds};

  /// Merkt [ids] als gesehen. Gespeichert wird nur, was es noch gibt
  /// ([known]: alle geladenen Hinweise) — so wächst die Liste nicht mit
  /// jedem gelöschten Hinweis weiter.
  void markSeen(Iterable<String> ids, {required Set<String> known}) {
    final next = {...state, ...ids}.where(known.contains).toSet();
    if (next.length == state.length && next.containsAll(state)) return;
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setSeenNoteIds(next.toList())
        .catchError((Object e, StackTrace s) => logError('Gelesene Hinweise merken', e, s)));
  }
}

final seenNotesProvider =
    NotifierProvider<SeenNotesNotifier, Set<String>>(SeenNotesNotifier.new);

/// Wunsch der Liste an die Karte: diesen Trail zeigen (Muster PilzBuddy
/// #345, erst Reiter wechseln, dann Wunsch stellen).
/// Sortierung der Liste (#66) — nur für die Liste, für die Sitzung.
final trailSortProvider = StateProvider<TrailSort>((ref) => TrailSort.recent);

/// Der Trail-Filter (#66) — für Liste UND Karte (seit 0.33.0), für die
/// Sitzung: Wer die App neu öffnet, sieht wieder alles.
final trailListFilterProvider = StateProvider<TrailListFilter>((ref) => const TrailListFilter());

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
