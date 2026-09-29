// Glättung der Trail-Linien für die ANZEIGE (Betreiber, 2026-09-29:
// „smoother darstellen"). Die gespeicherte Linie ist vereinfacht
// (Douglas-Peucker, `simplify`) und damit eckig — auf der Karte sah jede
// Kurve wie ein Knick aus. Chaikin schneidet die Ecken ab, bleibt dabei
// innerhalb der Hülle der Punkte und hält Anfang und Ende fest.
//
// NUR für das Bild: Abgleich, Länge, Höhen, Deckung und Zerlegung
// rechnen weiter mit den Originalpunkten. Die Trefferprüfung nimmt die
// geglättete Linie — getippt wird auf das, was man sieht.
import 'package:latlong2/latlong.dart';

/// Drei Durchgänge: Bei zwei sah eine enge Kehre noch eckig aus (im
/// Bild nachgesehen, 2026-09-29), ab vier ändert sich nichts Sichtbares
/// mehr. Die Abweichung bleibt unter einem Viertel des Abschnitts an der
/// Ecke. Jeder Durchgang verdoppelt die Punkte — gerechnet wird einmal je
/// Trail (`_smoothCache` im Karten-Screen).
const kLineSmoothingPasses = 3;

List<LatLng> chaikinSmooth(List<LatLng> points, {int passes = kLineSmoothingPasses}) {
  var pts = points;
  for (var n = 0; n < passes && pts.length >= 3; n++) {
    final out = <LatLng>[pts.first];
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      LatLng at(double t) => LatLng(a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t);
      // Am ersten und letzten Abschnitt bleibt das Ende stehen.
      if (i > 0) out.add(at(0.25));
      if (i < pts.length - 2) out.add(at(0.75));
    }
    out.add(pts.last);
    pts = out;
  }
  return pts;
}
