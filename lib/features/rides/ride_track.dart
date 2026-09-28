// Die Fahrt (#28, Konzept 5.1): der aufgezeichnete Weg von Start bis
// Ziel — Haustür bis Haustür. Sie ist ein Bewegungsprofil und verlässt
// das Gerät nie (Konzept 10, Entscheidung 4); beigesteuert werden
// später nur Ausschnitte, die einen Trail belegen (Zerlege-Blatt, #29).
//
// Alles hier ist rein: Punkte rein, Zahlen raus. Kein Netz, keine
// Platte, keine Provider. Der Baustein ist die Pilztour aus PilzBuddy
// (#338/#342 dort), ohne die Leergang-Logik.
import '../trails/trail_geometry.dart' show haversineM;

/// Ein gemessener Punkt der Fahrt.
class RidePoint {
  const RidePoint({
    required this.lat,
    required this.lng,
    required this.at,
    required this.accuracyM,
    this.altM,
  });

  final double lat;
  final double lng;
  final DateTime at;

  /// Der Streuradius, den das Gerät zu diesem Fix meldet. Mitgeführt,
  /// weil das Zerlege-Blatt (#29) unscharfe Stücke anders behandeln
  /// soll als scharfe — ein 15-m-Korridor gegen einen ±40-m-Fix ist
  /// Rauschen im Gewand einer Messung.
  final double accuracyM;

  /// Die Höhe, die das GPS meldet — ROH mitgeschrieben, nirgends
  /// angezeigt. GPS-Höhen rauschen um Dutzende Meter; ob sie als
  /// Höhenquelle taugen, wird gemessen, bevor eine Zahl daraus wird
  /// (#28: „file elevations stay the source until measured"). Ohne die
  /// Rohdaten gäbe es nichts zu messen.
  final double? altM;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'at': at.toUtc().toIso8601String(),
        'acc': accuracyM,
        if (altM != null) 'alt': altM,
      };

  static RidePoint? fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (lat == null || lng == null || at == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return RidePoint(
      lat: lat,
      lng: lng,
      at: at.toUtc(),
      // Fehlende Genauigkeit heißt „unbrauchbar", nicht „perfekt".
      accuracyM: (json['acc'] as num?)?.toDouble() ?? double.infinity,
      altM: (json['alt'] as num?)?.toDouble(),
    );
  }
}

/// Die laufende Fahrt: wann sie begann und was seither gemessen wurde.
typedef RecordedRide = ({DateTime startedAt, List<RidePoint> points});

/// Eine abgeschlossene Fahrt auf dem Gerät. [id] ist der Dateiname ohne
/// Endung, abgeleitet aus dem Start — eindeutig genug, zwei Fahrten
/// beginnen nie in derselben Sekunde.
class Ride {
  const Ride({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.points,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<RidePoint> points;

  Duration get duration => endedAt.difference(startedAt);
  double get lengthM => rideLengthM(points);
}

/// Die Länge einer Spur in Metern — Punkt zu Punkt, dieselbe Formel wie
/// bei den Trails.
double rideLengthM(List<RidePoint> points) {
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += haversineM(points[i - 1].lat, points[i - 1].lng, points[i].lat,
        points[i].lng);
  }
  return sum;
}

/// Wie viele Punkte die Karte höchstens zeichnet.
///
/// Eine Dreistundenfahrt im 5-Sekunden-Takt sind über 2 000 Punkte. Die
/// Grenze greift nur in die ANZEIGE ein: Gespeichert und später zerlegt
/// wird mit allen Punkten.
const kRideTrackMaxDots = 500;

/// Jeder n-te Punkt, damit höchstens [max] übrig bleiben — und der
/// LETZTE ist immer dabei: Er ist die Stelle, an der man gerade steht;
/// fiele er weg, hinkte die Spur sichtbar hinterher.
List<RidePoint> thinnedRide(List<RidePoint> points, {int max = kRideTrackMaxDots}) {
  if (points.length <= max) return points;
  final step = (points.length / max).ceil();
  final kept = <RidePoint>[
    for (var i = 0; i < points.length; i += step) points[i],
  ];
  if (kept.last != points.last) kept.add(points.last);
  return kept;
}

/// „1 h 12 min" bzw. „12 min".
String rideDurationLabel(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  return '$hours h $minutes min';
}
