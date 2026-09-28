import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/poi_source.dart';

/// Orte aus dem Speicher statt vom Kartenhost — kein Netz in Tests. Merkt
/// sich jede Abfrage, damit Tests zählen können, WANN gefragt wird (und
/// wann gerade nicht: unterhalb Zoom 12, alles aus).
class FakePoiSource implements PoiSource {
  FakePoiSource([List<Poi>? pois]) : pois = pois ?? [];

  final List<Poi> pois;

  /// Je Abfrage der Rahmen um die gefragten Zellen.
  final calls = <({double s, double w, double n, double e})>[];
  final cellsAsked = <List<PoiCell>>[];
  final groupsAsked = <Set<PoiGroup>>[];

  /// Gesetzt: Die nächste Abfrage scheitert damit.
  Object? failWith;

  @override
  Future<List<Poi>> fetch(List<PoiCell> cells, Set<PoiGroup> groups) async {
    final box = poiCellsBounds(cells);
    calls.add(box);
    cellsAsked.add(cells);
    groupsAsked.add(groups);
    final f = failWith;
    if (f != null) {
      failWith = null;
      throw f;
    }
    return [
      for (final p in pois)
        if (groups.contains(p.group) &&
            p.position.latitude >= box.s &&
            p.position.latitude <= box.n &&
            p.position.longitude >= box.w &&
            p.position.longitude <= box.e)
          p,
    ];
  }
}
