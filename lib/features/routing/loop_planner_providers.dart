// Die Nähte zwischen Planer-Blatt und Karte (#158 Schritt 5). Das Blatt
// rechnet, die Karte zeichnet (`loopPreviewProvider`); der getippte
// Startpunkt ist ein kleiner Dialog mit der Karte: Das Blatt stellt die
// Bitte (`loopStartPickProvider`), schließt sich, die Karte nimmt den
// nächsten Tipp als Start (`loopStartProvider`) und öffnet das Blatt
// wieder — Muster der Zeichenfläche für Bereiche, nur ohne eigene
// Fläche: Ein Tipp ist eine Geste, die die Fassade schon hat.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_view/map_view.dart';

/// Die Vorschau der Runde — gezeichnet vom Blatt, gemalt vom
/// Karten-Screen über der Fahrt und unter dem Netz; ohne Blatt leer.
final loopPreviewProvider = StateProvider<List<MapViewPolyline>>((ref) => const []);

/// Die Karte wartet auf einen Tipp, der zum Start der Runde wird.
final loopStartPickProvider = StateProvider<bool>((ref) => false);

/// Der getippte Start (null: der eigene Standort).
final loopStartProvider = StateProvider<LatLng?>((ref) => null);

/// Ein Blatt bittet die Karte, diese Punkte einzupassen — in die Fläche
/// ÜBER dem Blatt (`mapPanelInsetProvider`). Die Karte nimmt den Wunsch und
/// setzt ihn auf null. Seit 0.74.0 statt „einpassen, sobald die Vorschau
/// zum ersten Mal Linien hat": Das Blatt weiß, wann es soweit ist — nach
/// dem Einklappen, sonst läge die Route wieder darunter.
final mapFitRequestProvider = StateProvider<List<LatLng>?>((ref) => null);

/// Der Planer wartet im Pool auf Tipps auf Trails (#178): Ein Tipp auf
/// einen Trail aus [selectable] wählt ihn an oder ab, statt sein Blatt zu
/// öffnen. Null, solange der Pool nicht offen ist.
class LoopMapPick {
  const LoopMapPick({required this.selectable, required this.toggle});

  final Set<String> selectable;
  final void Function(String trailId) toggle;
}

final loopMapPickProvider = StateProvider<LoopMapPick?>((ref) => null);
