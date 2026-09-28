import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

// Die eigene Position auf der Karte (PilzBuddy-Muster, gekürzt). Sie
// bleibt auf dem Gerät: Nichts hier schickt sie irgendwohin, und Trails
// entstehen weiter nur aus importierten Dateien (Phase 1).

/// Live-Position für den Punkt auf der Karte. Liefert null, wenn
/// Standortdienste aus sind oder die Berechtigung (noch) fehlt — es wird
/// hier bewusst NICHT gefragt: Ein Systemdialog beim ersten Start, bevor
/// jemand irgendetwas angetippt hat, wäre genau die Überrumpelung, die
/// Google Play „Prominent Disclosure" nennt. Gefragt wird nur über
/// [positionFixProvider], nach einem Tipp auf „Meine Position"; danach
/// wird dieser Provider invalidiert.
final positionStreamProvider = StreamProvider<Position?>((ref) async* {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      yield null;
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      yield null;
      return;
    }
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // erst ab 5 m Bewegung neu zeichnen
      ),
    );
  } catch (_) {
    yield null; // Die Position ist ein Zusatz, nie ein Fehlerfall.
  }
});

/// Ein EINZELNER Fix — und die einzige Stelle der App, die nach der
/// Standortberechtigung fragt. Als Provider, damit Widget-Tests ihn
/// ersetzen: Den Plattform-Kanal gibt es dort nicht.
typedef PositionFix = Future<Position?> Function();

final positionFixProvider = Provider<PositionFix>((ref) => _platformFix);

Future<Position?> _platformFix() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition();
  } catch (_) {
    return null;
  }
}
