// Die Fahrt im Isolate des Foreground-Service (#28; PilzBuddy #342).
//
// **Warum hier und nicht im Main-Isolate.** Wischt der Nutzer die App
// aus der Übersicht, stirbt der Flutter-Prozess samt allen Dart-Timern —
// der Service läuft sichtbar weiter, und aufgezeichnet würde trotzdem
// nichts. PilzBuddy hat genau das im Feld gesehen (2026-08-27).
// `flutter_foreground_task` startet für den Service ein EIGENES
// Flutter-Isolate, das das Wegwischen überlebt. Was hier steht, läuft
// dort — und nur dort.
//
// **Was in diesem Isolate NICHT gilt:** kein Riverpod, keine Widgets,
// kein `logError` mit Sink. Alles, was gebraucht wird, kommt über die
// Brücke (`FlutterForegroundTask.saveData`, also SharedPreferences —
// lesbar in beiden Isolaten) oder aus der Datei.
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'ride_store.dart';
import 'ride_track.dart';

/// Schlüssel der Brücke zwischen den Isolaten. Bewusst flache Werte:
/// `saveData` nimmt nur int, double, String und bool an.
const kRideDataDir = 'ride_dir';
const kRideDataUid = 'ride_uid';
const kRideDataActive = 'ride_active';

/// Ein gemessener Punkt als Zeichenkette an den Main-Isolate —
/// `sendDataToMain` trägt nur einfache Werte.
String encodeRideTick(RidePoint point) =>
    '${point.lat};${point.lng};${point.at.toUtc().toIso8601String()};'
    '${point.accuracyM};${point.altM ?? ''}';

RidePoint? decodeRideTick(Object? data) {
  if (data is! String) return null;
  final parts = data.split(';');
  if (parts.length != 5) return null;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  final at = DateTime.tryParse(parts[2]);
  final accuracy = double.tryParse(parts[3]);
  if (lat == null || lng == null || at == null || accuracy == null) return null;
  return RidePoint(
      lat: lat,
      lng: lng,
      at: at.toUtc(),
      accuracyM: accuracy,
      altM: double.tryParse(parts[4]));
}

/// Ein Takt der Aufzeichnung: messen, anhängen, melden.
///
/// Gibt zurück, was gemessen wurde — `null`, wenn keine Fahrt läuft oder
/// kein Fix zustande kam. **Wirft nie**: Eine Ausnahme in diesem Isolate
/// hat niemanden, der sie fängt, und beendete die Aufzeichnung für den
/// Rest der Fahrt.
Future<RidePoint?> recordRideTick({
  Future<Position?> Function()? fix,
  RideStore Function(String dir)? storeFor,
}) async {
  try {
    final active = await FlutterForegroundTask.getData<bool>(key: kRideDataActive);
    if (active != true) return null;
    final dir = await FlutterForegroundTask.getData<String>(key: kRideDataDir);
    if (dir == null) return null;

    final position = await (fix ?? _fix)();
    if (position == null) return null;
    final point = RidePoint(
      lat: position.latitude,
      lng: position.longitude,
      at: position.timestamp.toUtc(),
      accuracyM: position.accuracy,
      altM: position.altitude,
    );

    await (storeFor ?? _storeFor)(dir).appendPoint(point);
    // Damit die Karte mitläuft, solange jemand hinsieht. Ist die App weg,
    // geht das ins Leere — und genau dann trägt die Datei allein.
    FlutterForegroundTask.sendDataToMain(encodeRideTick(point));
    return point;
  } catch (_) {
    return null;
  }
}

RideStore _storeFor(String dir) => FileRideStore(baseDir: Directory(dir));

Future<Position?> _fix() async {
  try {
    // KEIN `timeLimit` (PilzBuddy-Lehre): Es machte aus jedem langsamen
    // Hintergrund-Fix stillschweigend gar keinen.
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );
  } catch (_) {
    // Kein Empfang zum Himmel: ein fehlender Fix ist kein Fehler,
    // sondern der Wald.
    return null;
  }
}

/// Der Task-Handler des Service: misst je Takt, solange die Brücke
/// „aktiv" sagt.
class RideTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Nicht abgewartet: `onRepeatEvent` ist synchron, der nächste Takt
    // kommt erst nach dem eingestellten Abstand.
    recordRideTick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
