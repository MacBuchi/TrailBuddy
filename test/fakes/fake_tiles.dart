// Eine Vektor-Kachel aus der Hand (Mapbox Vector Tile, wie Protomaps sie
// schreibt): die Ebene `roads` mit Linien in Kachel-Pixeln und den
// Eigenschaften `kind`/`kind_detail`. Für die Tests des Wege-Index (#29)
// — ein echter Kachelausschnitt läge im Repo als Binärblob ohne Aussage.
import 'dart:typed_data';

import 'package:vector_tile/raw/raw_vector_tile.dart' as raw;
import 'package:vector_tile/util/command.dart';

/// Eine Linie in Kachel-Pixeln (0 … [kTileExtent]) mit ihren Eigenschaften.
typedef RoadLine = ({List<(int, int)> px, String kind, String? kindDetail, String layer});

const kTileExtent = 4096;

RoadLine road(List<(int, int)> px, String kind, {String? kindDetail, String layer = 'roads'}) =>
    (px: px, kind: kind, kindDetail: kindDetail, layer: layer);

/// Kodiert die Linien je Ebene in EINE Kachel.
Uint8List mvtTile(List<RoadLine> lines) {
  final byLayer = <String, List<RoadLine>>{};
  for (final l in lines) {
    (byLayer[l.layer] ??= []).add(l);
  }
  final tile = raw.VectorTile();
  for (final entry in byLayer.entries) {
    final keys = <String>['kind', 'kind_detail'];
    final values = <raw.VectorTile_Value>[];
    int valueIndex(String v) {
      final i = values.indexWhere((x) => x.stringValue == v);
      if (i >= 0) return i;
      values.add(raw.VectorTile_Value(stringValue: v));
      return values.length - 1;
    }

    final layer = raw.VectorTile_Layer(name: entry.key, extent: kTileExtent, version: 2);
    for (final l in entry.value) {
      final tags = <int>[0, valueIndex(l.kind)];
      if (l.kindDetail != null) tags.addAll([1, valueIndex(l.kindDetail!)]);
      final geometry = <int>[];
      var x = 0, y = 0;
      for (var i = 0; i < l.px.length; i++) {
        if (i == 0) {
          geometry.add((1 << 3) | 1); // MoveTo, 1
        } else if (i == 1) {
          geometry.add(((l.px.length - 1) << 3) | 2); // LineTo, n-1
        }
        final (px, py) = l.px[i];
        geometry.add(Command.zigZagEncode(px - x));
        geometry.add(Command.zigZagEncode(py - y));
        x = px;
        y = py;
      }
      layer.features.add(raw.VectorTile_Feature(
          type: raw.VectorTile_GeomType.LINESTRING, tags: tags, geometry: geometry));
    }
    layer.keys.addAll(keys);
    layer.values.addAll(values);
    tile.layers.add(layer);
  }
  return tile.writeToBuffer();
}
