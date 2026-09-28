// Die Zerlegung einer Fahrt (#29, Konzept 5.1), pur: Punkte, das
// sichtbare Netz und die Wege rein — bekannte Trails, Kandidaten und
// der Rest raus. Kein Netz, keine Platte, keine Provider; das Blatt
// zeigt nur, was hier gerechnet wurde.
//
// Drei Regeln, jede mit ihrer Fehlerrichtung:
// - **Bekannt** ist ein Trail, den die Fahrt mit den Schwellen des
//   Abgleichs deckt (Korridor 15 m, Deckung ≥ 0,8, beidseitig, wie
//   `contribute_recording`). Das Stück der Fahrt darauf wird als
//   Aufzeichnung beigesteuert — „wieder gefahren". Was hier „bekannt"
//   heißt, verschmilzt der Server dann auch; sonst legte er still einen
//   Trail daneben an.
// - **Kandidat** ist ein Stück mit anhaltendem Gefälle, das zu mehr als
//   70 % abseits von Fahr- und Forststraßen liegt. Heuristik, kein
//   Urteil: Der Nutzer schneidet, benennt, verwirft. Ohne bekannte Wege
//   gibt es KEINE Kandidaten (Betreiber, 2026-09-28) — ein Gefälle
//   allein ist auch jede Forststraße bergab.
// - **Rest** (Anfahrt, Forstweg, Straße) wird nicht angeboten.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/line_geometry.dart';
import '../../models/trail.dart';
import '../trails/gpx.dart';
import '../trails/trail_geometry.dart';
import 'road_index.dart';

/// Ein Fix, der weiter streut als das, ist keine Messung im 15-m-Korridor
/// mehr — er fällt vor der Zerlegung weg (das Blatt sagt, wie viele).
const kSplitMaxAccuracyM = 30.0;

/// Ab diesem Anteil abseits der Straßen ist ein Gefälle-Stück ein
/// Kandidat (Konzept 5.1: „> 70 %").
const kSplitOffRoadShare = 0.7;

/// Weniger Abfahrt als das ist keine: 30 Höhenmeter sind die kürzeste
/// Abfahrt, die jemand als Trail anlegen würde — und GPS-Höhen rauschen
/// um 10 bis 20 m, ein kleineres Stück wäre Rauschen im Gewand eines
/// Kandidaten.
const kSplitMinLossM = 30.0;

/// Steigt die Höhe seit dem tiefsten Punkt einer Abfahrt um so viel, ist
/// die Abfahrt zu Ende. Größer als die Hysterese der Anzeige (3 m), weil
/// eine Gegensteigung von ein paar Metern auf einem Trail normal ist.
const kSplitRiseEndM = 15.0;

/// Über so viele Punkte wird die Höhe vor der Suche geglättet (Median).
/// Bei 5-s-Takt sind das ~30 s Fahrt — kurz genug für jede Kuppe, lang
/// genug gegen einen einzelnen Ausreißer des GPS.
const kSplitSmoothWindow = 7;

/// Heimzone (Konzept 5.1): Ein Kandidat, der so nah an Start oder Ziel
/// der Fahrt beginnt oder endet, bekommt einen Hinweis — keinen Riegel.
const kSplitHomeM = 300.0;

/// So viele Punkte darf die Fahrt neben dem Trail liegen, ohne dass das
/// Stück „bekannt" abreißt: GPS unter Bäumen springt für einen Moment
/// aus dem Korridor und kommt zurück.
const kSplitCorridorGap = 2;

/// Ein Stück der Fahrt: Punkt [start] bis [end], beide eingeschlossen,
/// als Indizes in [RideSplit.points].
sealed class RideSection {
  const RideSection({required this.start, required this.end, required this.lengthM});

  final int start;
  final int end;
  final double lengthM;

  int get pointCount => end - start + 1;
}

/// Ein Trail des Netzes, den die Fahrt gedeckt hat.
class KnownTrailSection extends RideSection {
  const KnownTrailSection({
    required this.trail,
    required super.start,
    required super.end,
    required super.lengthM,
  });

  final Trail trail;
}

/// Ein Vorschlag für einen neuen Trail.
class CandidateSection extends RideSection {
  const CandidateSection({
    required super.start,
    required super.end,
    required super.lengthM,
    required this.lossM,
    required this.offRoadShare,
    required this.nearStart,
    required this.nearEnd,
  });

  /// Höhenverlust über das Stück, aus den geglätteten Höhen.
  final double lossM;

  /// Anteil der Abtastpunkte weiter als 15 m von jeder Straße.
  final double offRoadShare;

  /// Beginnt oder endet nahe Start/Ziel der Fahrt (Heimzone).
  final bool nearStart;
  final bool nearEnd;

  bool get nearHome => nearStart || nearEnd;
}

/// Das Ergebnis, mit den Punkten, auf die sich die Indizes beziehen.
class RideSplit {
  const RideSplit({
    required this.points,
    required this.known,
    required this.candidates,
    required this.roads,
    required this.hasElevation,
    required this.droppedInaccurate,
    required this.totalM,
  });

  /// Die Punkte der Fahrt OHNE die unscharfen.
  final List<TrackPoint> points;
  final List<KnownTrailSection> known;
  final List<CandidateSection> candidates;
  final RoadCoverage roads;

  /// Gab es Höhen zum Rechnen? Ohne sie keine Kandidaten.
  final bool hasElevation;
  final int droppedInaccurate;
  final double totalM;

  /// Was weder bekannt noch Kandidat ist — Anfahrt, Forstweg, Straße.
  double get restM {
    var used = 0.0;
    for (final s in known) {
      used += s.lengthM;
    }
    for (final s in candidates) {
      used += s.lengthM;
    }
    return math.max(0, totalM - used);
  }

  List<TrackPoint> pointsOf(RideSection s) => points.sublist(s.start, s.end + 1);
}

/// Zerlegt [points] (mit optionaler Streuung je Punkt, [accuracyM])
/// gegen [trails] und [roads]. [roads] null heißt „Wege unbekannt":
/// keine Kandidaten.
RideSplit splitRide({
  required List<TrackPoint> points,
  List<double?>? accuracyM,
  required List<Trail> trails,
  required RoadLoadResult roads,
}) {
  // 1. Unscharfe Punkte raus.
  final kept = <TrackPoint>[];
  var dropped = 0;
  for (var i = 0; i < points.length; i++) {
    final acc = accuracyM == null || i >= accuracyM.length ? null : accuracyM[i];
    if (acc != null && acc > kSplitMaxAccuracyM) {
      dropped++;
      continue;
    }
    kept.add(points[i]);
  }
  final latLng = [for (final p in kept) LatLng(p.lat, p.lon)];
  final totalM = trackLengthM(kept);
  if (kept.length < 2) {
    return RideSplit(
      points: kept,
      known: const [],
      candidates: const [],
      roads: roads.coverage,
      hasElevation: false,
      droppedInaccurate: dropped,
      totalM: totalM,
    );
  }

  final proj = roads.index?.projection ?? FlatProjection.around(latLng);
  final xy = proj.line(latLng);
  final cum = _cumulative(xy);

  // 2. Bekannte Trails.
  final known = _knownSections(kept, latLng, xy, cum, trails, proj);

  // 3. Kandidaten in den freien Stücken.
  final ele = _elevations(kept);
  final candidates = <CandidateSection>[];
  final roadIndex = roads.index;
  if (ele != null && roadIndex != null) {
    final smooth = smoothElevation(ele, kSplitSmoothWindow);
    final onRoad = [for (final p in xy) roadIndex.nearRoad(p)];
    for (final (from, to) in _freeRanges(kept.length, known)) {
      for (final run in descentRuns(smooth, from: from, to: to)) {
        final c = _candidateFrom(run, xy, cum, smooth, onRoad);
        if (c != null) candidates.add(c);
      }
    }
  }
  return RideSplit(
    points: kept,
    known: known,
    candidates: candidates,
    roads: roads.coverage,
    hasElevation: ele != null,
    droppedInaccurate: dropped,
    totalM: totalM,
  );
}

List<double> _cumulative(List<math.Point<double>> xy) {
  final cum = <double>[0];
  for (var i = 1; i < xy.length; i++) {
    cum.add(cum.last + xy[i - 1].distanceTo(xy[i]));
  }
  return cum;
}

/// Die Höhen, wenn JEDER Punkt eine hat — sonst null (halbe Reihen
/// ergäben halbe Abfahrten).
List<double>? _elevations(List<TrackPoint> pts) {
  final out = <double>[];
  for (final p in pts) {
    final e = p.ele;
    if (e == null) return null;
    out.add(e);
  }
  return out;
}

/// Gleitender Median über [window] Punkte (ungerade; an den Rändern
/// kürzer). Ein Median statt eines Mittels: Ein einzelner Ausreißer
/// des GPS um 40 m verschiebt ein Mittel um 6 m, einen Median gar nicht.
List<double> smoothElevation(List<double> ele, int window) {
  if (ele.length < 3 || window < 3) return List.of(ele);
  final half = window ~/ 2;
  return [
    for (var i = 0; i < ele.length; i++)
      _median(ele.sublist(math.max(0, i - half), math.min(ele.length, i + half + 1))),
  ];
}

double _median(List<double> v) {
  final s = List.of(v)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Die Abfahrten in [ele] zwischen [from] und [to] (eingeschlossen), als
/// Indexpaare (Start am höchsten Punkt vor dem Abstieg, Ende am tiefsten
/// Punkt davor, wo es wieder um [kSplitRiseEndM] hochgeht). Nur
/// Abfahrten von mindestens [kSplitMinLossM].
List<(int, int)> descentRuns(List<double> ele, {int from = 0, int? to}) {
  final last = to ?? ele.length - 1;
  final runs = <(int, int)>[];
  if (last - from < 1) return runs;
  var top = from; // der höchste Punkt seit der letzten Abfahrt
  var bottom = from; // der tiefste Punkt seit [top]
  for (var i = from + 1; i <= last; i++) {
    if (ele[i] < ele[bottom]) {
      bottom = i;
    } else if (ele[i] - ele[bottom] >= kSplitRiseEndM) {
      // Die Abfahrt von [top] nach [bottom] ist zu Ende.
      if (ele[top] - ele[bottom] >= kSplitMinLossM) runs.add((top, bottom));
      top = i;
      bottom = i;
    } else if (ele[i] > ele[top] || (bottom == top && ele[i] == ele[top])) {
      // Höher als der Gipfel, ohne dass seit dem tiefsten Punkt 15 m
      // dazwischenlagen: Die kleine Delle davor war keine Abfahrt, der
      // Gipfel wandert mit — auf einem ebenen Stück bis zu dessen Ende,
      // damit der Kandidat nicht die Anfahrt über den Gipfel mitnimmt.
      top = i;
      bottom = i;
    }
  }
  if (ele[top] - ele[bottom] >= kSplitMinLossM) runs.add((top, bottom));
  return runs;
}

CandidateSection? _candidateFrom(
  (int, int) run,
  List<math.Point<double>> xy,
  List<double> cum,
  List<double> ele,
  List<bool> onRoad,
) {
  var (start, end) = run;
  // Die Enden auf die Straße gestutzt: Eine Abfahrt beginnt meist auf
  // dem Forstweg oben und endet auf dem unten; der Kandidat ist das
  // Stück dazwischen. Der Nutzer schneidet den Rest mit den Griffen.
  while (start < end && onRoad[start]) {
    start++;
  }
  while (end > start && onRoad[end]) {
    end--;
  }
  if (end - start < 1) return null;
  final lengthM = cum[end] - cum[start];
  if (lengthM < kTrailMinLengthM) return null;
  final lossM = ele[start] - ele[end];
  if (lossM < kSplitMinLossM) return null;
  // Der Anteil abseits über Abtastpunkte alle 5 m, nicht über die
  // Messpunkte: Auf einer schnellen Forststraße liegen die 28 m
  // auseinander, auf dem Trail 8 — die Punkte zählten die Straße zu
  // kurz.
  final samples = resampleXy(xy.sublist(start, end + 1), kMatchSampleStepM);
  var off = 0;
  for (final s in samples) {
    if (!_nearAnyRoadSample(s, xy, onRoad, start, end)) off++;
  }
  final share = off / samples.length;
  if (share <= kSplitOffRoadShare) return null;
  final startXy = xy.first, endXy = xy.last;
  bool nearHome(math.Point<double> p) =>
      p.distanceTo(startXy) <= kSplitHomeM || p.distanceTo(endXy) <= kSplitHomeM;
  return CandidateSection(
    start: start,
    end: end,
    lengthM: lengthM,
    lossM: lossM,
    offRoadShare: share,
    nearStart: nearHome(xy[start]),
    nearEnd: nearHome(xy[end]),
  );
}

/// Ob ein Abtastpunkt „auf der Straße" liegt, abgeleitet aus den
/// nächstliegenden Messpunkten: Der Punkt liegt auf der Strecke zwischen
/// zwei Messpunkten, und die Straßenfrage ist je Messpunkt schon
/// beantwortet — beide auf der Straße heißt Straße.
bool _nearAnyRoadSample(
    math.Point<double> s, List<math.Point<double>> xy, List<bool> onRoad, int start, int end) {
  var best = start;
  var bestD = double.infinity;
  for (var i = start; i <= end; i++) {
    final d = s.distanceTo(xy[i]);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return onRoad[best];
}

/// Die Stücke, die kein bekannter Trail belegt.
List<(int, int)> _freeRanges(int n, List<KnownTrailSection> known) {
  final sorted = List.of(known)..sort((a, b) => a.start.compareTo(b.start));
  final out = <(int, int)>[];
  var from = 0;
  for (final k in sorted) {
    if (k.start - 1 > from) out.add((from, k.start - 1));
    from = math.max(from, k.end + 1);
  }
  if (from < n - 1) out.add((from, n - 1));
  return out;
}

List<KnownTrailSection> _knownSections(
  List<TrackPoint> pts,
  List<LatLng> latLng,
  List<math.Point<double>> xy,
  List<double> cum,
  List<Trail> trails,
  FlatProjection proj,
) {
  final rideBox = LatBox.of(latLng);
  final out = <KnownTrailSection>[];
  for (final t in trails) {
    if (t.pending || t.points.length < 2) continue;
    if (!rideBox.near(LatBox.of(t.points), kMatchCorridorM)) continue;
    final trailXy = proj.line(t.points);
    final trailGrid = SegmentGrid([trailXy], kMatchCorridorM);
    // Die Läufe der Fahrt im Korridor des Trails, kleine Lücken überbrückt.
    final inside = [for (final p in xy) trailGrid.within(p, kMatchCorridorM)];
    (int, int)? best;
    var i = 0;
    while (i < inside.length) {
      if (!inside[i]) {
        i++;
        continue;
      }
      final start = i;
      var end = i;
      var gap = 0;
      var j = i + 1;
      while (j < inside.length) {
        if (inside[j]) {
          end = j;
          gap = 0;
        } else if (++gap > kSplitCorridorGap) {
          break;
        }
        j++;
      }
      if (best == null || end - start > best.$2 - best.$1) best = (start, end);
      i = end + 1;
    }
    if (best == null || best.$2 - best.$1 < 1) continue;
    final (start, end) = best;
    // Beidseitige Deckung wie beim Abgleich: das Stück auf dem Trail UND
    // der Trail unter dem Stück.
    final sectionXy = xy.sublist(start, end + 1);
    final ab = coverageWithin(resampleXy(sectionXy, kMatchSampleStepM), trailGrid, kMatchCorridorM);
    final ba = coverageWithin(resampleXy(trailXy, kMatchSampleStepM),
        SegmentGrid([sectionXy], kMatchCorridorM), kMatchCorridorM);
    if (ab < kMatchCoverage || ba < kMatchCoverage) continue;
    out.add(KnownTrailSection(trail: t, start: start, end: end, lengthM: cum[end] - cum[start]));
  }
  // Überlappende Treffer (zwei Trails auf demselben Stück, etwa ein Trail
  // und seine Variante): der längere gewinnt, sonst würde ein Stück
  // zweimal beigesteuert.
  out.sort((a, b) => (b.end - b.start).compareTo(a.end - a.start));
  final kept = <KnownTrailSection>[];
  for (final k in out) {
    if (kept.any((o) => k.start <= o.end && k.end >= o.start)) continue;
    kept.add(k);
  }
  kept.sort((a, b) => a.start.compareTo(b.start));
  return kept;
}
