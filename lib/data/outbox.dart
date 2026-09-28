// Der Ausgangskorb (#30, Konzept 4.7 und 8): Aufträge, die ohne Empfang
// entstanden sind, warten hier auf die nächste Verbindung. Baustein aus
// PilzBuddy (#267 dort), auf zwei Aufträge zugeschnitten.
//
// **Warum es ihn braucht.** Beisteuern ging bis 0.13.0 direkt an die RPC
// und scheiterte im Funkloch mit „Keine Verbindung" — die Aufzeichnung
// war weg, wenn niemand sie zu Hause noch einmal wählte. Genau falsch
// herum: Der Trail ist der Ort ohne Netz.
//
// **Der Korb trägt das Original, keine Kopie.** Deshalb WIRFT
// [Outbox.append], wenn der Auftrag nicht sicher liegt — der Aufrufer
// meldet dann den ursprünglichen Netzfehler. Still „gespeichert" zu
// melden wäre die schlimmste Variante.
//
// **Nur `looksOffline` führt hierher.** Ein Serverfehler muss sichtbar
// scheitern, sonst sammelte der Korb still Aufträge, die nie durchgehen,
// und ein kaputtes Deployment bliebe unbemerkt.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../features/trails/trail_geometry.dart' show RecordingSource;
import '../models/trail.dart';

/// Ein Auftrag im Korb. Genau ZWEI Arten — die Schreibwege, die draußen
/// vorkommen: eine Aufzeichnung beisteuern und den eigenen Beitrag
/// speichern. Höhen nachtragen, Hinweise, Löschen scheitern weiter
/// sichtbar: Schreibtischarbeit im WLAN.
sealed class OutboxJob {
  const OutboxJob({
    required this.id,
    required this.createdAt,
    this.attempts = 0,
    this.failure,
  });

  /// Bei einer Aufzeichnung zugleich ihre `client_id` — die Kennung, mit
  /// der der Server einen zweiten Versuch als denselben erkennt.
  final String id;
  final DateTime createdAt;

  /// Wie oft die Wiedervorlage es schon versucht hat.
  final int attempts;

  /// Gesetzt heißt: endgültig abgelehnt, wird nicht mehr versucht. Der
  /// Text ist für den Nutzer, nicht fürs Log.
  final String? failure;

  Map<String, dynamic> toJson();

  OutboxJob copyWith({int? attempts, String? failure, bool clearFailure = false});

  static OutboxJob? tryParse(Map<String, dynamic> json) {
    try {
      final id = json['id'] as String?;
      final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
      if (id == null || createdAt == null) return null;
      final attempts = json['attempts'] as int? ?? 0;
      final failure = json['failure'] as String?;
      switch (json['kind']) {
        case 'contribute':
          final coords = [for (final c in json['coords'] as List) (c as num).toDouble()];
          final rawEles = json['eles'] as List?;
          final eles = rawEles == null
              ? null
              : [for (final e in rawEles) (e as num).toDouble()];
          if (coords.length < 4 || coords.length.isOdd) return null;
          if (eles != null && eles.length * 2 != coords.length) return null;
          return ContributeJob(
            id: id,
            createdAt: createdAt,
            coords: coords,
            eles: eles,
            source: RecordingSource.values
                .firstWhere((s) => s.name == json['source'], orElse: () => RecordingSource.import),
            recordedAt: DateTime.tryParse(json['recorded_at'] as String? ?? '')?.toUtc(),
            name: json['name'] as String?,
            grade: json['grade'] as int?,
            attempts: attempts,
            failure: failure,
          );
        case 'details':
          return DetailsJob(
            id: id,
            createdAt: createdAt,
            details: TrailDetails.fromJson(json['details'] as Map<String, dynamic>),
            note: json['note'] as String?,
            attempts: attempts,
            failure: failure,
          );
        default:
          return null; // Ein Auftragstyp, den dieser Stand nicht kennt.
      }
    } catch (_) {
      return null;
    }
  }
}

/// Eine Aufzeichnung beisteuern — die Linie so, wie sie an die RPC ging
/// (vereinfacht, flach), mit dem Namen aus der Datei, der danach als
/// eigener Name übernommen wird.
class ContributeJob extends OutboxJob {
  const ContributeJob({
    required super.id,
    required super.createdAt,
    required this.coords,
    this.eles,
    required this.source,
    this.recordedAt,
    this.name,
    this.grade,
    super.attempts,
    super.failure,
  });

  /// `[lon, lat, lon, lat, …]`, wie `contribute_recording` es nimmt.
  final List<double> coords;
  final List<double>? eles;
  final RecordingSource source;
  final DateTime? recordedAt;
  final String? name;

  /// Der S-Grad aus dem Zerlege-Blatt (#29), der mit dem Namen in den
  /// eigenen Beitrag geht — null, wenn keiner gewählt war.
  final int? grade;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'contribute',
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'failure': failure,
        'coords': coords,
        'eles': eles,
        'source': source.name,
        'recorded_at': recordedAt?.toUtc().toIso8601String(),
        'name': name,
        'grade': grade,
      };

  @override
  ContributeJob copyWith({int? attempts, String? failure, bool clearFailure = false}) =>
      ContributeJob(
        id: id,
        createdAt: createdAt,
        coords: coords,
        eles: eles,
        source: source,
        recordedAt: recordedAt,
        name: name,
        grade: grade,
        attempts: attempts ?? this.attempts,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Den eigenen Beitrag zu einem Trail speichern, der auf dem Server
/// schon existiert — samt Hinweis zum geänderten Status, wenn einer
/// mitgegeben wurde (beides gehört zusammen).
class DetailsJob extends OutboxJob {
  const DetailsJob({
    required super.id,
    required super.createdAt,
    required this.details,
    this.note,
    super.attempts,
    super.failure,
  });

  final TrailDetails details;
  final String? note;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'details',
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'failure': failure,
        'details': details.toRow(),
        'note': note,
      };

  @override
  DetailsJob copyWith({int? attempts, String? failure, bool clearFailure = false}) =>
      DetailsJob(
        id: id,
        createdAt: createdAt,
        details: details,
        note: note,
        attempts: attempts ?? this.attempts,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// Die Ablage-Form: EIN JSON-Text mit dem Konto, dem er gehört.
String encodeOutbox(List<OutboxJob> jobs, {required String uid}) => jsonEncode({
      'uid': uid,
      'jobs': [for (final job in jobs) job.toJson()],
    });

/// Liest [text] zurück — oder `const []`, wenn nichts Brauchbares darin
/// steht oder der Inhalt einem anderen Konto gehört. Wirft nie; ein
/// einzelner unlesbarer Auftrag fällt weg, der Rest bleibt.
List<OutboxJob> decodeOutbox(String text, {required String uid}) {
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return const [];
    // Fremdes Konto: Die Aufträge eines anderen Nutzers dürfen nie in
    // einer fremden Sitzung hochgehen — sie trügen dessen Linien in mein
    // Konto.
    if (json['uid'] != uid) return const [];
    final jobs = <OutboxJob>[];
    for (final raw in json['jobs'] as List<dynamic>? ?? const []) {
      final job = OutboxJob.tryParse(raw as Map<String, dynamic>);
      if (job != null) jobs.add(job);
    }
    return jobs;
  } catch (_) {
    return const [];
  }
}

/// Der Korb wirft beim Lesen nie, beim **Schreiben** aber sehr wohl.
abstract interface class Outbox {
  Future<List<OutboxJob>> read({required String uid});

  /// Hängt einen Auftrag an. Wirft, wenn er nicht sicher liegt.
  Future<void> append(OutboxJob job, {required String uid});

  /// Schreibt den ganzen Korb neu — der Weg der Wiedervorlage: „erledigt"
  /// und „Zähler hochgesetzt" werden GEMEINSAM gültig.
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid});
}

/// Der Korb als Datei im App-Verzeichnis (Android). `outbox/` steht in
/// beiden Backup-Ausschlüssen: Hier liegen Linien, BEVOR sie irgendwo
/// anders liegen.
class FileOutbox implements Outbox {
  FileOutbox({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;

  static const dirName = 'outbox';

  /// Lese-Ändern-Schreiben ist hier die Regel: Die Wiedervorlage arbeitet
  /// den Korb ab, während der Import einen weiteren Auftrag ablegt.
  Future<void> _lock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/jobs.json');
  }

  @override
  Future<List<OutboxJob>> read({required String uid}) =>
      _serialized(() => _readUnlocked(uid: uid));

  Future<List<OutboxJob>> _readUnlocked({required String uid}) async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      return decodeOutbox(await file.readAsString(), uid: uid);
    } catch (_) {
      // Unlesbar heißt „kein Korb". Kein `logError`: ein Bericht je Start.
      return const [];
    }
  }

  @override
  Future<void> append(OutboxJob job, {required String uid}) => _serialized(() async {
        final jobs = await _readUnlocked(uid: uid);
        await _writeUnlocked([...jobs, job], uid: uid);
      });

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) =>
      _serialized(() => _writeUnlocked(jobs, uid: uid));

  /// `.part` + `rename`: Ein Abbruch mitten im Schreiben darf keine halbe
  /// Datei hinterlassen. Anders als bei einer Kopie wird hier NICHTS
  /// geschluckt.
  Future<void> _writeUnlocked(List<OutboxJob> jobs, {required String uid}) async {
    final file = await _file();
    final temp = File('${file.path}.part');
    await temp.writeAsString(encodeOutbox(jobs, uid: uid), flush: true);
    await temp.rename(file.path);
  }
}

/// Kein Ort zum Ablegen, also kein Korb: [append] wirft, und der Aufrufer
/// meldet den ursprünglichen Netzfehler — wie vor diesem Feature. Das ist
/// der Web-Zweig, bewusst (#30: „explicitly no outbox on web for now";
/// PilzBuddy hat dort IndexedDB, #386).
class NoOutbox implements Outbox {
  const NoOutbox();

  @override
  Future<List<OutboxJob>> read({required String uid}) async => const [];

  @override
  Future<void> append(OutboxJob job, {required String uid}) async =>
      throw const OutboxUnavailable();

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) async {}
}

class OutboxUnavailable implements Exception {
  const OutboxUnavailable();

  @override
  String toString() => 'Auf dieser Plattform gibt es keinen Ausgangskorb';
}
