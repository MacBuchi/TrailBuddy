import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'official_trails.dart';

/// „Auch ausgeschildert als …" (#13, Schritt 4): Deckt ein Trail des
/// Netzes eine offizielle Linie? Gerechnet auf dem Gerät mit der Deckung
/// des Abgleichs — Korridor und Anteil wie `contribute_recording` und
/// `tool/trail_match.py` (`DEFAULT_D`, `DEFAULT_COV`, `STEP`); ändern sich
/// die Schwellen dort, ändern sie sich hier im selben PR.
///
/// Bewusst OHNE Fréchet: Es wird nichts verschmolzen, nur ein Satz im
/// Blatt gezeigt, und beide Linien sieht der Nutzer auf der Karte. Über
/// Netzgrenzen geht nichts (Konzept 12) — die offiziellen Linien sind
/// öffentlich, der Trail ist einer, den der Nutzer ohnehin sieht.
const kOfficialCorridorM = 15.0;
const kOfficialCoverage = 0.8;
const kOfficialSampleStepM = 5.0;

const _earthRadiusM = 6371000.0;

enum OfficialOverlap {
  /// Beide decken einander: derselbe Trail.
  same,

  /// Der Trail des Netzes liegt auf einem Stück des offiziellen.
  partOf,

  /// Der offizielle liegt ganz auf dem (längeren) Trail des Netzes.
  contains,
}

typedef OfficialMatch = ({OfficialTrail trail, OfficialOverlap overlap});

/// Die offiziellen Trails, die [line] deckt, „derselbe" zuerst.
///
/// Die Hauptroute zählt für die Rückrichtung, Varianten nicht: Wer die
/// Hauptroute fährt, fährt den ausgeschilderten Trail, auch wenn er die
/// Varianten auslässt. Für die Hinrichtung zählt jeder Teil — wer eine
/// Variante fährt, ist trotzdem auf dem offiziellen Trail.
List<OfficialMatch> matchOfficial(List<LatLng> line, Iterable<OfficialTrail> candidates) {
  if (line.length < 2) return const [];
  final lat0 = line.fold<double>(0, (a, p) => a + p.latitude) / line.length;
  final proj = _Projection(lat0);
  final lineBox = _Box.of(line);
  final lineXy = [for (final p in line) proj.xy(p)];
  final lineSamples = _resample(lineXy, kOfficialSampleStepM);
  _SegmentGrid? lineGrid;

  final out = <OfficialMatch>[];
  for (final t in candidates) {
    final all = [for (final s in t.sections) ...s.points];
    if (!lineBox.near(_Box.of(all), kOfficialCorridorM)) continue;
    final sectionsXy = [
      for (final s in t.sections) [for (final p in s.points) proj.xy(p)],
    ];
    final there = _SegmentGrid(sectionsXy, kOfficialCorridorM);
    final ab = _coverage(lineSamples, there);
    final main = [
      for (var i = 0; i < t.sections.length; i++)
        if (!t.sections[i].variant) sectionsXy[i],
    ];
    lineGrid ??= _SegmentGrid([lineXy], kOfficialCorridorM);
    final mainSamples = [
      for (final s in main.isEmpty ? sectionsXy : main)
        ..._resample(s, kOfficialSampleStepM),
    ];
    final ba = _coverage(mainSamples, lineGrid);
    final overlap = switch ((ab >= kOfficialCoverage, ba >= kOfficialCoverage)) {
      (true, true) => OfficialOverlap.same,
      (true, false) => OfficialOverlap.partOf,
      (false, true) => OfficialOverlap.contains,
      _ => null,
    };
    if (overlap != null) out.add((trail: t, overlap: overlap));
  }
  out.sort((a, b) => a.overlap.index.compareTo(b.overlap.index));
  return out;
}

/// Anteil der [samples], die näher als der Korridor an [grid] liegen.
double _coverage(List<math.Point<double>> samples, _SegmentGrid grid) {
  if (samples.isEmpty) return 0;
  var inside = 0;
  for (final p in samples) {
    if (grid.within(p, kOfficialCorridorM)) inside++;
  }
  return inside / samples.length;
}

/// Eben um eine Breite — auf den Metern eines Trails genau genug, wie im
/// Werkzeug (`project`).
class _Projection {
  _Projection(double lat0) : _k = math.cos(lat0 * math.pi / 180);
  final double _k;

  math.Point<double> xy(LatLng p) => math.Point(
      p.longitude * math.pi / 180 * _earthRadiusM * _k,
      p.latitude * math.pi / 180 * _earthRadiusM);
}

class _Box {
  _Box(this.s, this.w, this.n, this.e);
  final double s, w, n, e;

  static _Box of(List<LatLng> pts) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final p in pts) {
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
    return _Box(s, w, n, e);
  }

  bool near(_Box o, double marginM) {
    final dLat = marginM / 111320.0;
    final dLon = marginM / (111320.0 * math.cos((s + n) / 2 * math.pi / 180));
    return !(n + dLat < o.s || o.n + dLat < s || e + dLon < o.w || o.e + dLon < w);
  }
}

/// Punkte alle [step] Meter entlang der Linie, erster und letzter
/// eingeschlossen (`resample` im Werkzeug): Die Stützpunkte allein
/// verfehlten die Linie zwischen ihnen.
List<math.Point<double>> _resample(List<math.Point<double>> xy, double step) {
  if (xy.length < 2) return [...xy];
  final out = [xy.first];
  var carry = 0.0;
  for (var i = 1; i < xy.length; i++) {
    final a = xy[i - 1], b = xy[i];
    final seg = a.distanceTo(b);
    if (seg == 0) continue;
    var pos = step - carry;
    while (pos <= seg) {
      final t = pos / seg;
      out.add(math.Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)));
      pos += step;
    }
    carry = seg - (pos - step);
  }
  if (out.last != xy.last) out.add(xy.last);
  return out;
}

typedef _Segment = (math.Point<double>, math.Point<double>);

/// Gitter über die Strecken einer oder mehrerer Linien, für „liegt ein
/// Punkt im Korridor?" ohne jede Strecke anzufassen.
class _SegmentGrid {
  _SegmentGrid(List<List<math.Point<double>>> lines, this.cell) {
    for (final l in lines) {
      for (var i = 1; i < l.length; i++) {
        final a = l[i - 1], b = l[i];
        final seg = (a, b);
        for (var cx = (math.min(a.x, b.x) / cell).floor();
            cx <= (math.max(a.x, b.x) / cell).floor();
            cx++) {
          for (var cy = (math.min(a.y, b.y) / cell).floor();
              cy <= (math.max(a.y, b.y) / cell).floor();
              cy++) {
            (_cells[(cx, cy)] ??= []).add(seg);
          }
        }
      }
    }
  }

  final double cell;
  final _cells = <(int, int), List<_Segment>>{};

  bool within(math.Point<double> p, double d) {
    final cx = (p.x / cell).floor(), cy = (p.y / cell).floor();
    final reach = (d / cell).ceil();
    for (var dx = -reach; dx <= reach; dx++) {
      for (var dy = -reach; dy <= reach; dy++) {
        for (final (a, b) in _cells[(cx + dx, cy + dy)] ?? const <_Segment>[]) {
          if (_pointSegment(p, a, b) <= d) return true;
        }
      }
    }
    return false;
  }
}

double _pointSegment(math.Point<double> p, math.Point<double> a, math.Point<double> b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return p.distanceTo(a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
  return p.distanceTo(math.Point(a.x + t * dx, a.y + t * dy));
}
