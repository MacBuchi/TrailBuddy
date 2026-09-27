import 'package:trailbuddy/features/map/poi.dart';
import 'package:trailbuddy/features/map/poi_source.dart';

/// Orte aus dem Speicher statt von Overpass — kein Netz in Tests. Merkt
/// sich jede Abfrage, damit Tests zählen können, WANN gefragt wird (und
/// wann gerade nicht: unterhalb Zoom 12, alles aus).
class FakePoiSource implements PoiSource {
  FakePoiSource([List<Poi>? pois]) : pois = pois ?? [];

  final List<Poi> pois;
  final calls = <({double s, double w, double n, double e})>[];
  final groupsAsked = <Set<PoiGroup>>[];

  /// Gesetzt: Die nächste Abfrage scheitert damit.
  Object? failWith;

  @override
  Future<List<Poi>> fetch(({double s, double w, double n, double e}) box,
      Set<PoiGroup> groups) async {
    calls.add(box);
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
