// Bereiche zeichnen (Offline-Karten, Stufe C; Betreiber, 2026-09-28:
// „alle Kacheln, die umschlossen oder berührt von der gezeichneten
// Fläche sind, werden offline geladen … additiv … theoretisch auch ein
// subtraktiver Bereich"). Pur bis auf den Notifier am Ende: aus einem
// Fingerstrich die Kacheln bei [kAreaShapeZoom], und der Entwurf, der
// Striche addiert oder abzieht, bis er gespeichert wird.
//
// **Ein Strich ist eine Fläche.** Er wird geschlossen (Ende zum Anfang),
// und dazu gehört jede Kachel, die der Rand berührt oder die innen liegt.
// Ein offener Zickzack ergibt damit eine dünne Fläche — seine Kacheln
// sind die, über die er läuft. Das ist dieselbe Regel für beides, und sie
// macht den Radierer zu einem Werkzeug, das genau wegnimmt, worüber man
// gewischt hat.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_view/map_view.dart';
import 'area_overlay.dart' show offlineOverlayBox, offlineOverlayZoom;
import 'area_plan.dart';

/// Größer als so viele Kacheln (Rahmen des Strichs, bei Zoom 13) wird
/// ein Strich nicht ausgewertet: ein Kreis um halb Europa ist ein
/// Versehen, und ihn Kachel für Kachel zu prüfen hielte die Oberfläche an.
/// Weit über [kAreaMaxTiles], damit das Abziehen aus einem großen
/// Entwurf nicht daran scheitert.
const kAreaDrawMaxSpanTiles = 250000;

/// Wie viele Schritte ein Entwurf zurücknehmen kann.
const kAreaDraftHistory = 20;

/// Wie viele Rechtecke die Anzeige des Entwurfs höchstens zeichnet —
/// darüber eine Zoomstufe gröber (wie die Maske aus Stufe B).
const kAreaDraftMaxRects = 1500;

/// Die Farbe des Entwurfs auf der Karte: sichtbar über der Abdunkelung,
/// verschieden von den hellen gespeicherten Kacheln.
const kAreaDraftFill = Color(0x5530A46C);
const kAreaDraftBorder = Color(0xCC1F6F5F);

/// Der Strich des Radierers, solange der Finger auf der Karte ist.
const kAreaEraseStroke = Color(0xCCC62828);

double _tileX(double lon, int n) => (lon + 180) / 360 * n;

double _tileY(double lat, int n) {
  final r = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
}

/// Die Kacheln bei [zoom] (Schlüssel wie [TileSetShape.keyOf]), die die
/// geschlossene Fläche [ring] berührt oder umschließt. Null, wenn der
/// Rahmen des Strichs mehr als [maxSpanTiles] Kacheln umfasst — leer bei
/// weniger als zwei Punkten.
Set<int>? tilesTouchedByRing(List<LatLng> ring,
    {int zoom = kAreaShapeZoom, int maxSpanTiles = kAreaDrawMaxSpanTiles}) {
  if (ring.length < 2) return <int>{};
  final n = 1 << zoom;
  final pts = [for (final p in ring) (x: _tileX(p.longitude, n), y: _tileY(p.latitude, n))];
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final span = (maxX.floor() - minX.floor() + 1) * (maxY.floor() - minY.floor() + 1);
  if (span > maxSpanTiles) return null;

  final keys = <int>{};
  void add(int x, int y) {
    if (x < 0 || y < 0 || x >= n || y >= n) return;
    keys.add(TileSetShape.keyOf(x, y, zoom));
  }

  // Der Rand: jede Kante in Schritten von höchstens einer Zehntelkachel
  // abgetastet. Eine Ecke, die eine Kachel um weniger streift, fehlt —
  // die harmlose Richtung.
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    final len = math.max((b.x - a.x).abs(), (b.y - a.y).abs());
    final steps = math.max(1, (len / 0.1).ceil());
    for (var k = 0; k <= steps; k++) {
      final f = k / steps;
      add((a.x + (b.x - a.x) * f).floor(), (a.y + (b.y - a.y) * f).floor());
    }
  }

  // Das Innere: je Kachelzeile die Schnittpunkte der Mittellinie mit den
  // Kanten (gerade-ungerade), dazwischen jede Kachel, deren Mitte innen
  // liegt. Was innen UND am Rand liegt, hat die Abtastung schon.
  for (var row = minY.floor(); row <= maxY.floor(); row++) {
    final yc = row + 0.5;
    final xs = <double>[];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      if ((a.y <= yc) != (b.y <= yc)) {
        xs.add(a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y));
      }
    }
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i += 2) {
      for (var col = (xs[i] - 0.5).ceil(); col <= (xs[i + 1] - 0.5).floor(); col++) {
        add(col, row);
      }
    }
  }
  return keys;
}

/// Wie ein Strich wirkt: dazu oder weg.
enum AreaDrawTool { add, remove }

/// Der Entwurf eines gezeichneten Bereichs: die Kacheln bei
/// [kAreaShapeZoom], die Schritte davor (für „Rückgängig") und das
/// Werkzeug, das gerade auf den nächsten Strich wartet.
@immutable
class AreaDraft {
  AreaDraft({required Set<int> keys, this.history = const [], this.tool})
      : shape = TileSetShape(zoom: kAreaShapeZoom, keys: Set.unmodifiable(keys));

  /// Die Form, einmal je Stand gebaut — sie geht so in den Plan.
  final TileSetShape shape;
  final List<Set<int>> history;
  final AreaDrawTool? tool;

  Set<int> get keys => shape.keys;
  bool get isEmpty => keys.isEmpty;

  AreaDraft _with({Set<int>? keys, List<Set<int>>? history, AreaDrawTool? tool, bool clearTool = false}) =>
      AreaDraft(
        keys: keys ?? this.keys,
        history: history ?? this.history,
        tool: clearTool ? null : (tool ?? this.tool),
      );

  /// Ein neuer Stand; der alte wandert in die Geschichte. Ohne Änderung
  /// kein Schritt — „Rückgängig" soll immer etwas tun.
  AreaDraft _step(Set<int> next) {
    if (next.length == keys.length && next.containsAll(keys)) return _with(clearTool: true);
    final h = [...history, keys];
    return _with(
      keys: next,
      history: h.length > kAreaDraftHistory ? h.sublist(h.length - kAreaDraftHistory) : h,
      clearTool: true,
    );
  }
}

/// Der Entwurf — null, solange niemand zeichnet. Er überlebt das
/// Schließen des Blatts: Wer zwischendurch nachsieht, was liegt, verliert
/// seine Striche nicht.
class AreaDraftNotifier extends Notifier<AreaDraft?> {
  @override
  AreaDraft? build() => null;

  void start() => state ??= AreaDraft(keys: const {});

  /// Das Werkzeug für den NÄCHSTEN Strich; derselbe Knopf noch einmal
  /// nimmt es zurück. Nach dem Strich ist es wieder weg — die Karte lässt
  /// sich zwischen zwei Strichen verschieben, ohne umzuschalten.
  void arm(AreaDrawTool tool) {
    final d = state;
    if (d == null) return;
    state = d.tool == tool ? d._with(clearTool: true) : d._with(tool: tool);
  }

  void disarm() {
    final d = state;
    if (d != null && d.tool != null) state = d._with(clearTool: true);
  }

  /// Ein Strich: seine Kacheln dazu oder weg, je nach Werkzeug.
  void applyStroke(Set<int> stroke) {
    final d = state;
    if (d == null || d.tool == null) return;
    state = d._step(d.tool == AreaDrawTool.add
        ? {...d.keys, ...stroke}
        : ({...d.keys}..removeAll(stroke)));
  }

  /// Kacheln dazu, ohne Strich (die Kacheln entlang der eigenen Trails
  /// als Ausgangspunkt, von dem man dann abzieht).
  void addAll(Set<int> keys) {
    final d = state;
    if (d == null) return;
    state = d._step({...d.keys, ...keys});
  }

  void undo() {
    final d = state;
    if (d == null || d.history.isEmpty) return;
    state = AreaDraft(keys: d.history.last, history: d.history.sublist(0, d.history.length - 1));
  }

  void discard() => state = null;

  /// Ein fertiger Download mit genau diesen Kacheln war dieser Entwurf —
  /// er ist gespeichert, also weg.
  void discardIfSaved(AreaShape saved) {
    final d = state;
    if (d == null || saved is! TileSetShape || saved.zoom != kAreaShapeZoom) return;
    if (saved.keys.length == d.keys.length && saved.keys.containsAll(d.keys)) state = null;
  }
}

final areaDraftProvider = NotifierProvider<AreaDraftNotifier, AreaDraft?>(AreaDraftNotifier.new);

/// Der Entwurf auf der Karte: im Ausschnitt (mit Rand) bei dem Zoom, den
/// auch die Maske nimmt, Kacheln einer Zeile zu EINEM Rechteck
/// zusammengezogen — ein Entwurf entlang eines Tals sind sonst tausende
/// Einzelflächen. Zu viele ⇒ eine Stufe gröber.
List<MapViewPolygon> draftPolygons(AreaDraft draft, MapViewBounds view, {required double cameraZoom}) {
  if (draft.isEmpty || view.east <= view.west || view.north <= view.south) return const [];
  final box = offlineOverlayBox(view);
  var z = offlineOverlayZoom(cameraZoom);
  var rects = _rowRuns(draft.shape.tilesWithin(box, z));
  while (rects.length > kAreaDraftMaxRects && z > kAreaMinZoom) {
    z--;
    rects = _rowRuns(draft.shape.tilesWithin(box, z));
  }
  return [
    for (final r in rects)
      () {
        final nw = tileBounds(r.z, r.x0, r.y);
        final se = tileBounds(r.z, r.x1, r.y);
        return MapViewPolygon(
          points: [
            LatLng(nw.north, nw.west),
            LatLng(nw.north, se.east),
            LatLng(se.south, se.east),
            LatLng(se.south, nw.west),
          ],
          fillColor: kAreaDraftFill,
          borderColor: kAreaDraftBorder,
          borderWidth: 1,
        );
      }(),
  ];
}

List<({int z, int y, int x0, int x1})> _rowRuns(List<TileXYZ> tiles) {
  if (tiles.isEmpty) return const [];
  final sorted = [...tiles]..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
  final out = <({int z, int y, int x0, int x1})>[];
  var cur = (z: sorted.first.z, y: sorted.first.y, x0: sorted.first.x, x1: sorted.first.x);
  for (final t in sorted.skip(1)) {
    if (t.y == cur.y && t.x == cur.x1 + 1) {
      cur = (z: cur.z, y: cur.y, x0: cur.x0, x1: t.x);
    } else {
      out.add(cur);
      cur = (z: t.z, y: t.y, x0: t.x, x1: t.x);
    }
  }
  out.add(cur);
  return out;
}
