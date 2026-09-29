// Glattere Linien und Namen entlang der Linie (Betreiber, 2026-09-29):
// Glättung nur fürs Bild, runde Ecken in MapLibre, Namen als Symbol-Ebene
// entlang der Linie, in flutter_map einmal in der Mitte, nie kopfüber.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:trailbuddy/features/map/line_smoothing.dart';
import 'package:trailbuddy/features/map/map_view/line_labels.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/map_view/maplibre_map_view.dart';

void main() {
  group('Glättung', () {
    const kink = [LatLng(48, 9), LatLng(48.001, 9), LatLng(48.001, 9.001)];

    test('Anfang und Ende bleiben, die Ecke wird abgeschnitten', () {
      final s = chaikinSmooth(kink);
      expect(s.first, kink.first);
      expect(s.last, kink.last);
      expect(s.length, greaterThan(kink.length));
      expect(s, isNot(contains(kink[1])), reason: 'die spitze Ecke ist weg');
    });

    test('bleibt nah an der Linie: höchstens ein Viertel des Abschnitts neben der Ecke', () {
      final s = chaikinSmooth(kink);
      const d = Distance();
      final corner = kink[1];
      final nearest = s.map((p) => d.as(LengthUnit.Meter, p, corner)).reduce(math.min);
      final seg = d.as(LengthUnit.Meter, kink[0], kink[1]);
      expect(nearest, lessThan(seg / 4));
    });

    test('eine Gerade bleibt gerade, zwei Punkte bleiben zwei', () {
      final line = [const LatLng(48, 9), const LatLng(48.001, 9), const LatLng(48.002, 9)];
      expect(chaikinSmooth(line).every((p) => p.longitude == 9), isTrue);
      expect(chaikinSmooth(line.sublist(0, 2)), hasLength(2));
    });
  });

  group('Name in flutter_map', () {
    test('in der Mitte nach Länge, waagerecht gelesen', () {
      final a = lineLabelAnchor(const [LatLng(48, 9), LatLng(48, 9.01)])!;
      expect(a.point.longitude, closeTo(9.005, 1e-9));
      expect(a.angle, closeTo(0, 1e-9));
    });

    test('nie auf dem Kopf: eine Linie nach Westen liest sich wie eine nach Osten', () {
      final west = lineLabelAnchor(const [LatLng(48, 9.01), LatLng(48, 9)])!;
      expect(west.angle.abs(), lessThan(1e-9));
      final north = lineLabelAnchor(const [LatLng(48, 9), LatLng(48.01, 9)])!;
      expect(north.angle, closeTo(-math.pi / 2, 1e-6));
      for (final a in [west.angle, north.angle]) {
        expect(a, inInclusiveRange(-math.pi / 2, math.pi / 2));
      }
    });
  });

  test('MapLibre: runde Ecken, Namen als Symbol-Ebene entlang der Linie, darüber, ab Zoom 14', () {
    final layers = mapLibrePolylineLayers([
      const MapViewPolyline(
          points: [LatLng(48, 9), LatLng(48.01, 9)], color: Color(0xFF1F6FD1), label: 'Hexentanz'),
      const MapViewPolyline(points: [LatLng(48, 9.1), LatLng(48.01, 9.1)], color: Color(0xFF1F6FD1)),
    ]);
    final lines = layers.whereType<ml.PolylineLayer>().toList();
    expect(lines, isNotEmpty);
    for (final l in lines) {
      expect(l.getLayout(), containsPair('line-join', 'round'));
      expect(l.getLayout(), containsPair('line-cap', 'round'));
    }
    final label = layers.last as LineLabelLayer;
    expect(label.list, hasLength(1), reason: 'nur Linien mit Namen');
    expect(label.list.single.properties['label'], 'Hexentanz');
    expect(label.getLayout(), containsPair('symbol-placement', 'line'));
    expect(label.getLayout()['text-field'], '{label}');
    // Der Stack muss als Glyphen-Ordner im Paket liegen — sonst lässt
    // MapLibre den Namen still weg.
    for (final stack in label.getLayout()['text-font']! as List) {
      expect(Directory('assets/map_glyphs/$stack').existsSync(), isTrue, reason: '$stack');
    }
    // 512er-Zählung der Engine: eins weniger als die Fassade.
    expect(label.minZoom, kLineLabelMinZoom - 1);
  });
}
