import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

TrailRecording rec(String trail, String user,
        {double quality = 0.5, int day = 1, List<LatLng>? pts, List<double>? ele,
        bool reversed = false}) =>
    TrailRecording(
      id: '$trail-$user-$day',
      trailId: trail,
      userId: user,
      source: RecordingSource.import,
      recordedAt: null,
      reversed: reversed,
      quality: quality,
      createdAt: DateTime(2026, 1, day),
      points: pts ?? const [LatLng(48, 9), LatLng(48.01, 9)],
      lengthM: 1000,
      ele: ele,
    );

TrailDetails det(String trail, String user,
        {String? name, int? grade, TrailStatus status = TrailStatus.open, DateTime? at}) =>
    TrailDetails(trailId: trail, userId: user, name: name, grade: grade, status: status, statusAt: at);

void main() {
  test('eigener Name vor dem des ältesten Beitrags, Rest als „auch"', () {
    final t = Trail(
      id: 't1',
      myId: 'me',
      recordings: [rec('t1', 'anna', day: 1), rec('t1', 'bob', day: 5), rec('t1', 'me', day: 9)],
      details: [det('t1', 'bob', name: 'Roots'), det('t1', 'anna', name: 'Hexentanz')],
    );
    expect(t.displayName, 'Hexentanz');
    expect(t.otherNames, ['Roots']);
    final mine = Trail(
      id: 't1',
      myId: 'me',
      recordings: t.recordings,
      details: [...t.details, det('t1', 'me', name: 'Mein Weg')],
    );
    expect(mine.displayName, 'Mein Weg');
    expect(mine.otherNames, containsAll(['Roots', 'Hexentanz']));
  });

  test('beste Linie ist die mit der höchsten Qualität, bei Gleichstand die ältere', () {
    final a = rec('t', 'a', quality: 0.4, day: 1, pts: const [LatLng(1, 1), LatLng(1, 2)]);
    final b = rec('t', 'b', quality: 0.6, day: 2, pts: const [LatLng(2, 2), LatLng(2, 3)]);
    final c = rec('t', 'c', quality: 0.6, day: 3);
    expect(Trail(id: 't', myId: 'x', recordings: [a, c, b], details: const []).best.id, b.id);
  });

  test('jüngster Status gewinnt, Median der S-Grade, Buddys gezählt', () {
    final t = Trail(
      id: 't',
      myId: 'me',
      recordings: [rec('t', 'me'), rec('t', 'a'), rec('t', 'b')],
      details: [
        det('t', 'a', grade: 2, status: TrailStatus.closed, at: DateTime(2026, 3, 1)),
        det('t', 'b', grade: 3, status: TrailStatus.open, at: DateTime(2026, 4, 1)),
        det('t', 'me', grade: 5),
      ],
    );
    expect(t.status, TrailStatus.open);
    expect(t.grade, 3);
    expect(t.buddyIds, {'a', 'b'});
    expect(t.isOwn, isTrue);
  });

  test('buildTrails gruppiert und lässt Beiträge ohne Beleg weg', () {
    final trails = buildTrails(
      recordings: [rec('t1', 'me'), rec('t2', 'a')],
      details: [det('t1', 'me', name: 'B-Trail'), det('t2', 'a', name: 'A-Trail'), det('t3', 'a', name: 'Geist')],
      myId: 'me',
    );
    expect(trails.map((t) => t.displayName), ['A-Trail', 'B-Trail']);
  });

  test('fromJson nimmt GeoJSON als Text und als Objekt', () {
    final base = {
      'id': 'r', 'trail_id': 't', 'user_id': 'u', 'source': 'planned',
      'reversed': true, 'quality': 0.1, 'created_at': '2026-01-01T00:00:00Z',
      'length_m': 12.5,
    };
    final asText = TrailRecording.fromJson({...base,
        'geojson': '{"type":"LineString","coordinates":[[9.0,48.0],[9.1,48.1]]}'});
    final asMap = TrailRecording.fromJson({...base,
        'geojson': {'type': 'LineString', 'coordinates': [[9.0, 48.0], [9.1, 48.1]]}});
    for (final r in [asText, asMap]) {
      expect(r.points, const [LatLng(48, 9), LatLng(48.1, 9.1)]);
      expect(r.source, RecordingSource.planned);
      expect(r.reversed, isTrue);
    }
  });

  test('Höhen: aus der besten Aufzeichnung MIT Höhen, in Trail-Richtung', () {
    // Die beste Linie (0,6) ist alt und ohne Höhen; die Höhen kommen aus
    // der schlechteren, und die ist gegen die Richtung gefahren.
    final t = buildTrails(recordings: [
      rec('t', 'me', quality: 0.6),
      rec('t', 'bob', quality: 0.4, day: 2, ele: [500, 620], reversed: true),
    ], details: const [], myId: 'me').single;
    expect(t.best.userId, 'me');
    expect(t.elevationRecording!.userId, 'bob');
    expect(t.elevation!.lossM, 120, reason: 'bergauf gefahren, bergab gemeint');
    expect(t.elevation!.gainM, 0);
    expect(buildTrails(recordings: [rec('u', 'me')], details: const [], myId: 'me')
        .single.elevation, isNull);
  });

  test('fromJson liest ele nur, wenn es zu den Punkten passt', () {
    Map<String, dynamic> row(Object? ele) => {
          'id': 'r', 'trail_id': 't', 'user_id': 'u', 'source': 'import',
          'recorded_at': null, 'reversed': false, 'quality': 0.4,
          'created_at': '2026-09-27T10:00:00Z', 'length_m': 1000,
          'geojson': '{"type":"LineString","coordinates":[[9,48],[9,48.01]]}',
          'ele': ele,
        };
    expect(TrailRecording.fromJson(row([500, 480.5])).ele, [500, 480.5]);
    expect(TrailRecording.fromJson(row(null)).ele, isNull);
    expect(TrailRecording.fromJson(row([500])).ele, isNull,
        reason: 'eine verschobene Reihe wäre schlimmer als keine');
  });
}
