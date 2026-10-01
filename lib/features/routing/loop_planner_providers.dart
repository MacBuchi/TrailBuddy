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
