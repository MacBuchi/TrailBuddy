// Wo die Fahrten liegen (#28): im App-Verzeichnis unter `rides/`, das
// in beiden Backup-Ausschlüssen steht — ein Bewegungsprofil hat in
// Googles Cloud nichts verloren.
//
// Die LAUFENDE Fahrt wird Zeile für Zeile angehängt (JSON Lines), nicht
// am Ende am Stück: Der Prozess-Kill ist auf Android der Normalfall
// (PilzBuddy #147), und drei Stunden Fahren dürfen nicht daran hängen.
// Ein Abbruch mitten im Schreiben kostet höchstens die letzte Zeile —
// und genau die wirft [readActive] weg. Beim Beenden wird die Datei nur
// UMBENANNT (`active.jsonl` → `<id>.jsonl`): Die Fahrt bleibt als Ganzes
// auf dem Gerät (Konzept 5.1), nichts wird ohne Nachfrage gelöscht.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import 'ride_confirm.dart';
import 'ride_track.dart';

abstract interface class RideStore {
  /// Beginnt eine Fahrt und verwirft, was als laufende vorher dalag.
  ///
  /// **Wirft**, wenn sich nichts anlegen lässt: Eine Fahrt zu starten,
  /// die gar nicht aufgezeichnet werden kann, wäre ein Versprechen, das
  /// erst zu Hause auffliegt.
  Future<void> begin({required String uid, required DateTime startedAt});

  /// Hängt einen Punkt an. **Wirft nie** — ein verlorener Fix ist ein
  /// verlorener Fix, kein Grund, die laufende Fahrt abzubrechen.
  Future<void> appendPoint(RidePoint point);

  /// Hängt eine Frage oder Antwort (#116) an die LAUFENDE Fahrt. Mit
  /// [rideStartedAt] nur, wenn es noch dieselbe Fahrt ist — eine Antwort
  /// auf eine Benachrichtigung kann eintreffen, wenn die Fahrt längst
  /// beendet und eine neue begonnen ist. Gibt zurück, ob geschrieben
  /// wurde. **Wirft nie.**
  Future<bool> appendConfirmEvent(ConfirmEvent event, {DateTime? rideStartedAt});

  /// Hängt eine Marke „Trail beginnt/endet" (#105) an die laufende Fahrt.
  /// Geschrieben aus dem Main-Isolate — getippt wird dort, und die Marke
  /// trägt nur die Zeit; der Service hängt daneben seine Punkte an (wie
  /// die Antworten aus #116). Gibt zurück, ob geschrieben wurde. **Wirft
  /// nie.**
  Future<bool> appendMark(RideMark mark);

  /// Die Fragen und Antworten der laufenden Fahrt. Wirft nie.
  Future<List<ConfirmEvent>> activeConfirmEvents({required String uid});

  /// Die Trails, zu denen während der Fahrt gefragt wird (#116). Die App
  /// schreibt, der Service liest. Wirft nie — ohne Datei wird nicht
  /// gefragt, gefahren wird trotzdem.
  Future<void> writeConfirmTargets({required String uid, required List<ConfirmTarget> targets});
  Future<List<ConfirmTarget>> readConfirmTargets({required String uid});

  /// Die laufende Fahrt, oder `null`. Wirft nie.
  Future<RecordedRide?> readActive({required String uid});

  /// Schließt die laufende Fahrt ab: Sie wird zu einer gespeicherten
  /// [Ride]. `null`, wenn keine läuft. Wirft nie.
  Future<Ride?> finish({required String uid, required DateTime endedAt});

  /// Verwirft die laufende Fahrt, ohne sie zu speichern.
  Future<void> discardActive();

  /// Alle gespeicherten Fahrten dieses Kontos, neueste zuerst. Wirft nie.
  Future<List<Ride>> list({required String uid});

  Future<void> delete(String id);
}

class FileRideStore implements RideStore {
  FileRideStore({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;

  /// Muss in `backup_rules.xml` UND `full_backup_content.xml` stehen.
  static const dirName = 'rides';
  static const _activeName = 'active.jsonl';
  static const _targetsName = 'confirm_targets.json';

  /// Schreibvorgänge in einer Kette: Der Takt hängt an, während das
  /// Beenden liest — ohne die Kette verlöre einer von beiden seinen
  /// Stand.
  Future<void> _lock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Directory> _dir() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _active() async => File('${(await _dir()).path}/$_activeName');

  static String _idFor(DateTime startedAt) => startedAt
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[-:]'), '')
      .replaceAll(RegExp(r'\.\d+'), '');

  @override
  Future<void> begin({required String uid, required DateTime startedAt}) =>
      _serialized(() async {
        final file = await _active();
        await file.writeAsString(
          '${jsonEncode({
                'uid': uid,
                'startedAt': startedAt.toUtc().toIso8601String(),
              })}\n',
          flush: true,
        );
      });

  @override
  Future<void> appendPoint(RidePoint point) => _serialized(() async {
        try {
          final file = await _active();
          await file.writeAsString('${jsonEncode(point.toJson())}\n',
              mode: FileMode.append, flush: true);
        } catch (e, stackTrace) {
          // Gemeldet, nicht geschluckt: Das ist echter Datenverlust —
          // aber einer, der die Fahrt weiterlaufen lässt.
          logError('Fahrt-Punkt anhängen', e, stackTrace);
        }
      });

  @override
  Future<bool> appendConfirmEvent(ConfirmEvent event, {DateTime? rideStartedAt}) =>
      _serialized(() async {
        try {
          final file = await _active();
          if (!await file.exists()) return false;
          if (rideStartedAt != null) {
            final head = await _head(file);
            if (head == null || !head.startedAt.isAtSameMomentAs(rideStartedAt)) return false;
          }
          await file.writeAsString('${jsonEncode(event.toJson())}\n',
              mode: FileMode.append, flush: true);
          return true;
        } catch (e, stackTrace) {
          logError('Fahrt: Frage oder Antwort anhängen', e, stackTrace);
          return false;
        }
      });

  @override
  Future<bool> appendMark(RideMark mark) => _serialized(() async {
        try {
          final file = await _active();
          if (!await file.exists()) return false;
          await file.writeAsString('${jsonEncode(mark.toJson())}\n',
              mode: FileMode.append, flush: true);
          return true;
        } catch (e, stackTrace) {
          logError('Fahrt: Marke anhängen', e, stackTrace);
          return false;
        }
      });

  @override
  Future<List<ConfirmEvent>> activeConfirmEvents({required String uid}) =>
      _serialized(() async => (await _parse(await _active(), uid: uid))?.events ?? const []);

  @override
  Future<void> writeConfirmTargets({required String uid, required List<ConfirmTarget> targets}) async {
    try {
      final file = File('${(await _dir()).path}/$_targetsName');
      final part = File('${file.path}.part');
      await part.writeAsString(encodeConfirmTargets(uid: uid, targets: targets), flush: true);
      // Umbenennen statt überschreiben: Der Service liest dieselbe Datei
      // aus einem anderen Isolate und soll nie eine halbe sehen.
      await part.rename(file.path);
    } catch (e, stackTrace) {
      logError('Fahrt: Trails zum Bestätigen ablegen', e, stackTrace);
    }
  }

  @override
  Future<List<ConfirmTarget>> readConfirmTargets({required String uid}) async {
    try {
      final file = File('${(await _dir()).path}/$_targetsName');
      if (!await file.exists()) return const [];
      return decodeConfirmTargets(await file.readAsString(), uid: uid);
    } catch (_) {
      // Unlesbar heißt „nichts zu fragen" — je Takt ein Bericht wäre Lärm.
      return const [];
    }
  }

  /// Wann die Ziel-Datei zuletzt geschrieben wurde; der Service liest sie
  /// nur neu, wenn sich das ändert.
  Future<DateTime?> confirmTargetsModified() async {
    try {
      final file = File('${(await _dir()).path}/$_targetsName');
      return await file.exists() ? await file.lastModified() : null;
    } catch (_) {
      return null;
    }
  }

  /// Nur die Kopfzeile der Fahrt: wem sie gehört und wann sie begann.
  Future<({String uid, DateTime startedAt})?> _head(File file) async {
    try {
      final first = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      final head = jsonDecode(first);
      if (head is! Map<String, dynamic>) return null;
      final uid = head['uid'];
      final startedAt = DateTime.tryParse(head['startedAt'] as String? ?? '');
      if (uid is! String || startedAt == null) return null;
      return (uid: uid, startedAt: startedAt.toUtc());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<RecordedRide?> readActive({required String uid}) =>
      _serialized(() async {
        final parsed = await _parse(await _active(), uid: uid);
        if (parsed == null) return null;
        return (startedAt: parsed.startedAt, points: parsed.points, marks: parsed.marks);
      });

  @override
  Future<Ride?> finish({required String uid, required DateTime endedAt}) =>
      _serialized(() async {
        try {
          final active = await _active();
          final parsed = await _parse(active, uid: uid);
          if (parsed == null) return null;
          final id = _idFor(parsed.startedAt);
          final target = File('${(await _dir()).path}/$id.jsonl');
          // Das Ende als eigene Zeile, damit die Datei ihre Dauer
          // selbst trägt — der letzte Punkt kann Minuten vor dem
          // Beenden liegen (Funkloch, Pause am Ende).
          await active.writeAsString(
              '${jsonEncode({'endedAt': endedAt.toUtc().toIso8601String()})}\n',
              mode: FileMode.append,
              flush: true);
          await active.rename(target.path);
          return Ride(
              id: id,
              startedAt: parsed.startedAt,
              endedAt: endedAt.toUtc(),
              points: parsed.points,
              events: parsed.events,
              marks: parsed.marks);
        } catch (e, stackTrace) {
          logError('Fahrt abschließen', e, stackTrace);
          return null;
        }
      });

  @override
  Future<void> discardActive() => _serialized(() async {
        try {
          final file = await _active();
          if (await file.exists()) await file.delete();
        } catch (e, stackTrace) {
          // Bleibt die Datei liegen, böte die App beim nächsten Start
          // eine Fahrt an, die längst verworfen ist — das gehört gemeldet.
          logError('Fahrt verwerfen', e, stackTrace);
        }
      });

  @override
  Future<List<Ride>> list({required String uid}) => _serialized(() async {
        try {
          final dir = await _dir();
          final rides = <Ride>[];
          await for (final entry in dir.list()) {
            if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
            final name = entry.uri.pathSegments.last;
            if (name == _activeName) continue;
            final parsed = await _parse(entry, uid: uid);
            if (parsed == null) continue;
            rides.add(Ride(
              id: name.substring(0, name.length - '.jsonl'.length),
              startedAt: parsed.startedAt,
              // Ohne Ende-Zeile (Absturz beim Umbenennen): der letzte
              // Punkt, sonst der Start.
              endedAt: parsed.endedAt ??
                  (parsed.points.isEmpty ? parsed.startedAt : parsed.points.last.at),
              points: parsed.points,
              events: parsed.events,
              marks: parsed.marks,
            ));
          }
          rides.sort((a, b) => b.startedAt.compareTo(a.startedAt));
          return rides;
        } catch (_) {
          // Unlesbar heißt „keine Fahrten". Kein `logError`: Das wäre
          // ein Bericht pro Öffnen der Liste.
          return const [];
        }
      });

  @override
  Future<void> delete(String id) => _serialized(() async {
        // Nur ein Dateiname, kein Pfad: Die Kennung kommt aus der
        // eigenen Liste, aber ein `../` darf hier trotzdem nichts.
        if (!RegExp(r'^[0-9TZ]+$').hasMatch(id)) return;
        try {
          final file = File('${(await _dir()).path}/$id.jsonl');
          if (await file.exists()) await file.delete();
        } catch (e, stackTrace) {
          logError('Fahrt löschen', e, stackTrace);
        }
      });

  /// Liest eine Fahrt-Datei: Kopfzeile, Punkte, optional die Ende-Zeile.
  /// `null` bei fremdem Konto oder unlesbarem Kopf; kaputte Punktzeilen
  /// fallen einzeln weg.
  Future<
          ({
            DateTime startedAt,
            DateTime? endedAt,
            List<RidePoint> points,
            List<ConfirmEvent> events,
            List<RideMark> marks,
          })?>
      _parse(File file, {required String uid}) async {
    try {
      if (!await file.exists()) return null;
      final lines = const LineSplitter()
          .convert(await file.readAsString())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) return null;
      final head = jsonDecode(lines.first);
      if (head is! Map<String, dynamic>) return null;
      // Fremdes Konto: Die Fahrt eines anderen Nutzers gehört nicht in
      // eine fremde Sitzung — dieselbe Regel wie beim Ausgangskorb.
      if (head['uid'] != uid) return null;
      final startedAt = DateTime.tryParse(head['startedAt'] as String? ?? '');
      if (startedAt == null) return null;
      final points = <RidePoint>[];
      final events = <ConfirmEvent>[];
      final marks = <RideMark>[];
      DateTime? endedAt;
      for (final line in lines.skip(1)) {
        // Eine abgeschnittene LETZTE Zeile ist der Normalfall nach einem
        // Prozess-Kill, kein Fehler.
        try {
          final json = jsonDecode(line);
          if (json is! Map<String, dynamic>) continue;
          if (json.containsKey('endedAt')) {
            endedAt = DateTime.tryParse(json['endedAt'] as String? ?? '')?.toUtc();
            continue;
          }
          if (RideMark.isMark(json)) {
            final mark = RideMark.fromJson(json);
            if (mark != null) marks.add(mark);
            continue;
          }
          if (ConfirmEvent.isEvent(json)) {
            final event = ConfirmEvent.fromJson(json);
            if (event != null) events.add(event);
            continue;
          }
          final point = RidePoint.fromJson(json);
          if (point != null) points.add(point);
        } catch (_) {
          continue;
        }
      }
      return (
        startedAt: startedAt.toUtc(),
        endedAt: endedAt,
        points: points,
        events: events,
        marks: marks,
      );
    } catch (_) {
      return null;
    }
  }
}
