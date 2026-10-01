// Ein Trail als GPX (#150, Konzept 13: die Brücke zu anderen Apps ist
// die Datei). Pur: Trail rein, Spur raus.
//
// Exportiert wird die ANGEZEIGTE Linie in Trail-Richtung — die beste
// Aufzeichnung (`Trail.best`) samt IHREN Höhen (`best.ele`, nicht
// `Trail.elevation`: das kann eine andere Aufzeichnung sein, deren Höhen
// an diese Punkte nicht passen). Punkte und Höhen drehen sich gemeinsam,
// wenn die beste Aufzeichnung gegen die Richtung lief.
//
// Hinein geht der Name und der EIGENE Link (`myDetails.link`, nie der
// eines Buddys); nicht hinein gehen Buddy-Namen, Hinweise, Meldungen
// und Zeiten — die Datei ist eine Linie, kein Auszug aus dem Netz.
import '../../models/trail.dart';
import 'gpx.dart';

GpxTrack trailToGpx(Trail trail) {
  final best = trail.best;
  final points = best.reversed ? best.points.reversed.toList() : best.points;
  final ele = best.ele == null ? null : (best.reversed ? best.ele!.reversed.toList() : best.ele!);
  return GpxTrack(
    name: trail.hasName ? trail.displayName : 'Trail',
    points: [
      for (var i = 0; i < points.length; i++)
        TrackPoint(points[i].latitude, points[i].longitude, ele: ele?[i]),
    ],
    link: trail.myDetails?.link,
  );
}
