// Der Zwischenspeicher des eigenen Netzes (#32, Konzept 4.7) — damit die
// Karte ohne Empfang etwas zeigt, auch wenn die App dort NEU startet.
// PilzBuddys `spot_cache.dart` ist die Vorlage.
//
// **Warum es ihn braucht.** `trailsProvider` holt alles aus Supabase. Ein
// fehlgeschlagener Refresh ist harmlos (Riverpod behält den Vorwert),
// aber beim Kaltstart ohne Empfang gibt es keinen Vorwert — und die Karte
// stand kommentarlos leer. Genau im Wald.
//
// **Eine Kopie, kein Original.** Deshalb wirft hier nichts: Eine
// fehlende Kopie darf einen erfolgreichen Abruf nie kaputtmachen. Und
// **nur `looksOffline` liest die Kopie** (PilzBuddy #80): Ein
// Serverfehler muss sichtbar bleiben, sonst zeigte die App bei kaputtem
// Deployment wochenlang einen alten Stand als aktuellen.
//
// **Abgelegt wird die Zeilenform** — dieselbe, die auch vom Netz kommt,
// gelesen von denselben `fromJson`. Die Encoder hier sind die zweite
// Hälfte dazu; `test/trails/trail_cache_test.dart` prüft den Rundlauf
// Feld für Feld, damit die beiden Abbildungen nicht auseinanderlaufen.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';
import '../models/trail.dart';

/// Was das Netz auf einen Schlag liefert: die vier Tabellen des Netzes
/// (die Meldungen seit Patch 013).
typedef TrailSnapshot = ({
  List<TrailRecording> recordings,
  List<TrailDetails> details,
  List<TrailNote> notes,
  List<TrailReport> reports,
});

/// Ein Abruf mit Herkunft: `cachedAt == null` heißt frisch aus dem Netz.
typedef TrailSnapshotResult = ({TrailSnapshot snapshot, DateTime? cachedAt});

abstract interface class TrailCache {
  Future<({TrailSnapshot snapshot, DateTime savedAt})?> read({required String uid});
  Future<void> write({required String uid, required TrailSnapshot snapshot, required DateTime savedAt});
  Future<void> clear();
}

Map<String, dynamic> recordingToRow(TrailRecording r) => {
      'id': r.id,
      'trail_id': r.trailId,
      'user_id': r.userId,
      'source': r.source.name,
      'recorded_at': r.recordedAt?.toUtc().toIso8601String(),
      'reversed': r.reversed,
      'quality': r.quality,
      'created_at': r.createdAt.toUtc().toIso8601String(),
      'geojson': {
        'type': 'LineString',
        'coordinates': [for (final p in r.points) [p.longitude, p.latitude]],
      },
      'length_m': r.lengthM,
      'ele': r.ele,
    };

Map<String, dynamic> detailsToRow(TrailDetails d) => {
      ...d.toRow(),
      'updated_at': d.updatedAt?.toUtc().toIso8601String(),
      'contributor': d.username == null ? null : {'username': d.username},
    };

Map<String, dynamic> noteToRow(TrailNote n) => {
      'id': n.id,
      'trail_id': n.trailId,
      'user_id': n.userId,
      'body': n.body,
      'created_at': n.createdAt.toUtc().toIso8601String(),
      'author': n.username == null ? null : {'username': n.username},
    };

/// EIN JSON-Text mit dem Konto, dem er gehört.
String encodeTrailCache({required String uid, required TrailSnapshot snapshot, required DateTime savedAt}) =>
    jsonEncode({
      'uid': uid,
      'saved_at': savedAt.toUtc().toIso8601String(),
      'recordings': [for (final r in snapshot.recordings) recordingToRow(r)],
      'details': [for (final d in snapshot.details) detailsToRow(d)],
      'notes': [for (final n in snapshot.notes) noteToRow(n)],
      'reports': [for (final r in snapshot.reports) r.toRow()],
    });

/// Liest [text] zurück — `null`, wenn nichts Brauchbares darin steht oder
/// der Inhalt einem anderen Konto gehört. Die Trails eines anderen
/// Nutzers dürfen nie in einer fremden Sitzung auftauchen.
({TrailSnapshot snapshot, DateTime savedAt})? decodeTrailCache(String text, {required String uid}) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return null;
    if (json['uid'] != uid) return null;
    final savedAt = DateTime.tryParse(json['saved_at'] as String? ?? '');
    if (savedAt == null) return null;
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    return (
      snapshot: (
        recordings: [for (final r in rows('recordings')) TrailRecording.fromJson(r)],
        details: [for (final d in rows('details')) TrailDetails.fromJson(d)],
        notes: [for (final n in rows('notes')) TrailNote.fromJson(n)],
        // Fehlt bei einer Kopie von vor 0.49.0: dann eben keine Meldungen.
        reports: [for (final r in rows('reports')) ?TrailReport.fromJson(r)],
      ),
      savedAt: savedAt.toLocal(),
    );
  } catch (_) {
    return null;
  }
}

/// Die Datei im App-Verzeichnis (Android). `trail_cache/` steht in beiden
/// Backup-Ausschlüssen: Googles Cloud ist in der Datenschutzerklärung
/// kein Empfänger.
class FileTrailCache implements TrailCache {
  FileTrailCache({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;

  static const dirName = 'trail_cache';

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/network.json');
  }

  /// `.part` + `rename`: Ein Abbruch mitten im Schreiben darf keine halbe
  /// Datei hinterlassen — das wäre genau der Zustand, den die Kopie
  /// beseitigen soll.
  @override
  Future<void> write({required String uid, required TrailSnapshot snapshot, required DateTime savedAt}) async {
    try {
      final file = await _file();
      final temp = File('${file.path}.part');
      await temp.writeAsString(encodeTrailCache(uid: uid, snapshot: snapshot, savedAt: savedAt), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // Volle Platte, fehlende Rechte: Dann gibt es eben keine Kopie. Der
      // Abruf war erfolgreich und darf daran nicht scheitern.
    }
  }

  @override
  Future<({TrailSnapshot snapshot, DateTime savedAt})?> read({required String uid}) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return decodeTrailCache(await file.readAsString(), uid: uid);
    } catch (_) {
      // Unlesbar heißt „keine Kopie". Kein `logError`: ein Bericht je Start.
      return null;
    }
  }

  /// Beim Abmelden: Das Netz des abgemeldeten Kontos hat auf dem Gerät
  /// nichts mehr verloren — es ist eine Kopie, es geht nichts verloren.
  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ein Löschfehler darf das Abmelden nicht aufhalten.
    }
  }
}

/// Kein Ort zum Ablegen: der Web-Zweig, bewusst (#32; IndexedDB wie in
/// PilzBuddy #385 ist ein eigener Schritt) — und der Fall in Tests, die
/// keine Kopie wollen.
class NoTrailCache implements TrailCache {
  const NoTrailCache();

  @override
  Future<({TrailSnapshot snapshot, DateTime savedAt})?> read({required String uid}) async => null;

  @override
  Future<void> write({required String uid, required TrailSnapshot snapshot, required DateTime savedAt}) async {}

  @override
  Future<void> clear() async {}
}

/// Netz zuerst, Kopie als Rückfalllinie — und zwar NUR bei fehlendem
/// Empfang. Als freie Funktion, damit die Regel ohne Supabase prüfbar
/// ist: [fetch] ist im Test eine Funktion, die wirft.
Future<TrailSnapshotResult> fetchWithCache({
  required Future<TrailSnapshot> Function() fetch,
  required TrailCache cache,
  required String uid,
  required DateTime now,
}) async {
  final TrailSnapshot snapshot;
  try {
    snapshot = await fetch();
  } catch (error) {
    // Ein Serverfehler bleibt sichtbar; ein 504 zählt wie kein Netz.
    if (!looksOffline(error)) rethrow;
    final cached = await cache.read(uid: uid);
    if (cached == null) rethrow;
    return (snapshot: cached.snapshot, cachedAt: cached.savedAt);
  }
  await cache.write(uid: uid, snapshot: snapshot, savedAt: now);
  return (snapshot: snapshot, cachedAt: null);
}
