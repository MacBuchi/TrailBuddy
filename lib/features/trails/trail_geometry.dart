import 'dart:math' as math;

import 'gpx.dart';

/// Erdradius für Haversine, in Metern.
const double kEarthRadiusM = 6371000.0;

/// Ab hier ist eine Datei eine FAHRT, kein Trail (Konzept 5.2, gemessen
/// in docs/trail-abgleich-messung.md: alpine Trails sind 3 bis 8 km lang,
/// Fahrten beginnen im Bestand bei 8 km).
const double kTrailMaxLengthM = 8000;

/// Kürzer ist eine Zufahrt oder ein Fragment (Konzept 4.2).
const double kTrailMinLengthM = 150;

/// Schneller fährt kein Fahrrad im Median: eine gezeichnete Route mit
/// erfundenen Zeiten. Dieselbe Grenze wie in tool/trail_match.py.
const double kPlannedSpeedKmh = 60;

/// Was aus einer Spur wird, wenn sie als Datei hereinkommt.
enum TrackKind {
  /// Kurz und überwiegend bergab: direkt ein Trail-Kandidat.
  trail,

  /// Alles andere: eine Fahrt, die zerlegt werden muss (Phase 2) —
  /// in Phase 1 kann sie als Ganzes NICHT beigesteuert werden.
  ride,

  /// Unter der Mindestlänge: kein Trail.
  fragment,
}

/// Quelle einer Aufzeichnung, wie sie die Datenbank kennt.
enum RecordingSource { app, import, planned }

double haversineM(double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dp = p2 - p1;
  final dl = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * kEarthRadiusM * math.asin(math.sqrt(a));
}

double trackLengthM(List<TrackPoint> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length; i++) {
    sum += haversineM(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
  }
  return sum;
}

/// (Anstieg, Abstieg) in Metern — nur wenn JEDER Punkt eine Höhe trägt,
/// sonst null. Eine halbe Höhenreihe ergäbe eine erfundene Zahl.
({double gain, double loss})? elevationGainLoss(List<TrackPoint> pts) {
  if (pts.isEmpty || pts.any((p) => p.ele == null)) return null;
  var gain = 0.0;
  var loss = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final d = pts[i].ele! - pts[i - 1].ele!;
    if (d > 0) {
      gain += d;
    } else {
      loss -= d;
    }
  }
  return (gain: gain, loss: loss);
}

/// Ohne verwertbare Zeiten oder mit Fahrradfremden Geschwindigkeiten:
/// eine gezeichnete Route, keine Fahrt (Entscheidung 2 im Konzept).
bool looksPlanned(List<TrackPoint> pts) {
  final stamps = pts.map((p) => p.time).whereType<DateTime>().toSet();
  if (stamps.length < 2) return true;
  final speeds = <double>[];
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1].time;
    final b = pts[i].time;
    if (a == null || b == null) continue;
    final dt = b.difference(a).inMilliseconds / 1000;
    if (dt <= 0) continue;
    final d = haversineM(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
    speeds.add(d / dt * 3.6);
  }
  if (speeds.isEmpty) return true;
  speeds.sort();
  return speeds[speeds.length ~/ 2] > kPlannedSpeedKmh;
}

RecordingSource sourceOf(List<TrackPoint> pts) =>
    looksPlanned(pts) ? RecordingSource.planned : RecordingSource.import;

/// Die Importregel aus Konzept 5.2: kurz und überwiegend bergab ⇒ Trail.
/// Ohne Höhen entscheidet die Länge allein — lieber ein Trail zu viel im
/// Kandidatenblatt als eine Fahrt, die niemand zerlegen kann.
TrackKind classifyTrack(List<TrackPoint> pts) {
  final length = trackLengthM(pts);
  if (length < kTrailMinLengthM) return TrackKind.fragment;
  if (length >= kTrailMaxLengthM) return TrackKind.ride;
  final el = elevationGainLoss(pts);
  if (el == null) return TrackKind.trail;
  return el.loss > 2 * el.gain ? TrackKind.trail : TrackKind.ride;
}

/// Douglas-Peucker in Metern — damit ein 6 894-Punkte-Track nicht als
/// 14 000 Zahlen an die RPC geht. 3 m Toleranz liegt unter jedem
/// GPS-Rauschen und weit unter dem 15-m-Korridor des Abgleichs.
List<TrackPoint> simplify(List<TrackPoint> pts, {double toleranceM = 3}) {
  if (pts.length <= 2) return List.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  final lat0 = pts.first.lat * math.pi / 180;
  final kx = kEarthRadiusM * math.cos(lat0) * math.pi / 180;
  const ky = kEarthRadiusM * math.pi / 180;
  double x(TrackPoint p) => p.lon * kx;
  double y(TrackPoint p) => p.lat * ky;
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    if (b - a < 2) continue;
    final ax = x(pts[a]), ay = y(pts[a]), bx = x(pts[b]), by = y(pts[b]);
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    var worst = -1.0;
    var worstI = -1;
    for (var i = a + 1; i < b; i++) {
      final px = x(pts[i]), py = y(pts[i]);
      double d;
      if (l2 == 0) {
        d = math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
      } else {
        final t = (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
        final cx = ax + t * dx, cy = ay + t * dy;
        d = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      }
      if (d > worst) {
        worst = d;
        worstI = i;
      }
    }
    if (worst > toleranceM) {
      keep[worstI] = true;
      stack.add((a, worstI));
      stack.add((worstI, b));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}

/// Flache Koordinatenliste [lon, lat, lon, lat, …] für die RPC.
List<double> flatCoords(List<TrackPoint> pts) =>
    [for (final p in pts) ...[p.lon, p.lat]];
