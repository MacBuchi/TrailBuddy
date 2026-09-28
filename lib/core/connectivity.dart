import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Der Transportweg, wie `connectivity_plus` ihn meldet. In Tests
/// überschrieben — ohne Kanal gäbe es sonst keinen Strom.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
    (ref) => Connectivity().onConnectivityChanged);

/// Kein Empfang? Der eine Wechsel, an dem der Ausgangskorb (#30) hängt:
/// von „kein Netz" zurück auf irgendetwas. Bewusst NICHT am App-Resume —
/// wer aus dem Wald nach Hause kommt, ohne die App zu schließen, hat
/// kein Resume, aber sehr wohl einen Netzwechsel. Unbekannt gilt als
/// verbunden: ein Banner „offline" beim Aufbau, das gleich wieder
/// verschwindet, wäre schlimmer als eines einen Frame später.
final noConnectivityProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).valueOrNull;
  if (results == null) return false;
  return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
});
