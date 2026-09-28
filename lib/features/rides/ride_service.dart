import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ride_service_stub.dart' if (dart.library.io) 'ride_service_android.dart';

/// Der Foreground-Service der Fahrt (#28): hält den Prozess wach und
/// trägt das Isolate, in dem gemessen wird. Die Dauerbenachrichtigung IST
/// die Offenlegung gegenüber dem Nutzer — deshalb kein
/// `ACCESS_BACKGROUND_LOCATION`.
///
/// EIN Verbraucher, kein Koordinator: Anders als in PilzBuddy (Download
/// und Pilztour teilen sich dort einen Service) gibt es hier bisher nur
/// die Fahrt. Kommen Offline-Karten (Phase 3), wird daraus der
/// Koordinator aus PilzBuddy — zwei `stop()` auf einem Service sind die
/// Falle, die er dort löst.
abstract interface class RideService {
  /// Startet den Service mit dem Mess-Takt [every]; läuft er schon,
  /// werden nur die Texte erneuert.
  Future<void> start({required String title, required String text, required Duration every});

  Future<void> stop();
}

/// Legt den Port an, über den das Service-Isolate den Main-Isolate
/// erreicht. **Gehört in `main()`, vor `runApp`** — ohne ihn ist die
/// Rückrichtung stumm: `sendDataToMain` findet `null` und verwirft die
/// Meldung, ohne Fehler, ohne Spur (PilzBuddy #465, vier Wochen lang).
void initRideCommunication() => initRideCommunicationImpl();

/// Plattform-Implementierung: Foreground-Service auf Android, sonst
/// nichts. Tests überschreiben den Provider.
final rideServiceProvider = Provider<RideService>((ref) => createRideService());
