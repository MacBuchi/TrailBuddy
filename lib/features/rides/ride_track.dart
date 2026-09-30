// Die Fahrt (#28, Konzept 5.1): der aufgezeichnete Weg von Start bis
// Ziel — Haustür bis Haustür. Sie ist ein Bewegungsprofil und verlässt
// das Gerät nie (Konzept 10, Entscheidung 4); beigesteuert werden
// später nur Ausschnitte, die einen Trail belegen (Zerlege-Blatt, #29).
//
// Alles hier ist rein: Punkte rein, Zahlen raus. Kein Netz, keine
// Platte, keine Provider. Der Baustein ist die Pilztour aus PilzBuddy
// (#338/#342 dort), ohne die Leergang-Logik.
import '../trails/trail_geometry.dart' show haversineM;
import 'ride_confirm.dart' show ConfirmEvent;

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

/// Eine Marke während der Aufnahme (#105, Rework 5.2 und E12): „Trail
/// beginnt" oder „Trail endet", gesetzt per Knopf — wer auf dem Trail
/// steht, weiß genau, wo er anfängt. Die Marke trägt NUR die Zeit: Den
/// Ort sagt die Spur, und das Zerlege-Blatt nimmt den Punkt, der ihr
/// zeitlich am nächsten liegt. Ein eigener Fix beim Tippen wäre eine
/// zweite Messung derselben Stelle, die der Takt ohnehin macht.
enum RideMarkKind { start, end }

class RideMark {
  const RideMark({required this.kind, required this.at});

  final RideMarkKind kind;
  final DateTime at;

  /// Steht als eigene Zeile in der Fahrt-Datei, erkennbar am Schlüssel —
  /// `RidePoint.fromJson` ließe sie ohnehin liegen (keine Koordinate).
  static bool isMark(Map<String, dynamic> json) => json.containsKey('mark');

  Map<String, dynamic> toJson() => {'mark': kind.name, 'at': at.toUtc().toIso8601String()};

  static RideMark? fromJson(Map<String, dynamic> json) {
    final kind = switch (json['mark']) {
      'start' => RideMarkKind.start,
      'end' => RideMarkKind.end,
      _ => null,
    };
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (kind == null || at == null) return null;
    return RideMark(kind: kind, at: at.toUtc());
  }
}

/// Läuft gerade ein markierter Trail? Die letzte Marke ist ein Beginn.
/// Dieselbe Regel für den Knopf (was der nächste Tipp setzt, ob er einen
/// Rand trägt) und das Zerlege-Blatt (offene Marke bis zum Ende).
bool markedTrailOpen(List<RideMark> marks) =>
    marks.isNotEmpty && marks.last.kind == RideMarkKind.start;

/// Die laufende Fahrt: wann sie begann, was seither gemessen und was
/// markiert wurde.
typedef RecordedRide = ({DateTime startedAt, List<RidePoint> points, List<RideMark> marks});

/// Eine abgeschlossene Fahrt auf dem Gerät. [id] ist der Dateiname ohne
/// Endung, abgeleitet aus dem Start — eindeutig genug, zwei Fahrten
/// beginnen nie in derselben Sekunde.
class Ride {
  const Ride({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.points,
    this.events = const [],
    this.marks = const [],
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<RidePoint> points;

  /// Fragen und Antworten während der Fahrt (#116), in der Reihenfolge
  /// der Datei.
  final List<ConfirmEvent> events;

  /// Die Marken „Trail beginnt/endet" (#105), in der Reihenfolge der Datei.
  final List<RideMark> marks;

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
