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
  Future<RecordedRide?> readActive({required String uid}) =>
      _serialized(() async {
        final parsed = await _parse(await _active(), uid: uid);
        if (parsed == null) return null;
        return (startedAt: parsed.startedAt, points: parsed.points);
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
              points: parsed.points);
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
  Future<({DateTime startedAt, DateTime? endedAt, List<RidePoint> points})?>
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
          final point = RidePoint.fromJson(json);
          if (point != null) points.add(point);
        } catch (_) {
          continue;
        }
      }
      return (startedAt: startedAt.toUtc(), endedAt: endedAt, points: points);
    } catch (_) {
      return null;
    }
  }
}
