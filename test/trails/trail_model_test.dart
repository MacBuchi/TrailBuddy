import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

TrailRecording rec(String trail, String user,
        {double quality = 0.5, int day = 1, List<LatLng>? pts, List<double>? ele,
        bool reversed = false, RecordingSource source = RecordingSource.import}) =>
    TrailRecording(
      id: '$trail-$user-$day',
      trailId: trail,
      userId: user,
      source: source,
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
  test('geplant: nur wer ausschließlich Dateien ohne Fahrzeiten beigesteuert hat (#100)', () {
    const planned = RecordingSource.planned;
    final t = Trail(
      id: 't',
      myId: 'me',
      recordings: [
        rec('t', 'me', source: planned),
        rec('t', 'a', source: planned, day: 2),
        rec('t', 'a', day: 3),
        rec('t', 'b', source: planned, day: 4),
      ],
      details: const [],
    );
    expect(t.onlyPlanned('me'), isTrue);
    expect(t.onlyPlanned('a'), isFalse, reason: 'eine gefahrene Aufzeichnung reicht');
    expect(t.onlyPlanned('b'), isTrue);
    expect(t.onlyPlanned('nobody'), isFalse, reason: 'ohne Beleg kein „geplant"');
    expect(t.allPlanned, isFalse);
    final onlyPlans = Trail(
        id: 't', myId: 'me', recordings: [rec('t', 'me', source: planned)], details: const []);
    expect(onlyPlans.allPlanned, isTrue);
  });

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

  test('Schwierigkeit: Spanne, Einzelstimmen, Gleichstand zum schwereren', () {
    final t = buildTrails(recordings: [
      rec('t', 'me'),
      rec('t', 'a', day: 2),
      rec('t', 'b', day: 3),
      rec('t', 'c', day: 4),
    ], details: [
      det('t', 'me', grade: 1),
      det('t', 'a', grade: 2),
      det('t', 'b', grade: 3),
      det('t', 'c'),
    ], myId: 'me').single;
    expect(t.gradeRange, (min: 1, max: 3));
    expect(t.gradeVotes.map((d) => d.userId), ['me', 'a', 'b'],
        reason: 'ohne Angabe zählt nicht, älteste Beiträge zuerst');
    expect(t.grade, 2);
    final even = buildTrails(recordings: [rec('u', 'me'), rec('u', 'a')],
        details: [det('u', 'me', grade: 2), det('u', 'a', grade: 3)], myId: 'me').single;
    expect(even.grade, 3, reason: 'bei Gleichstand gewinnt die Warnung');
    expect(buildTrails(recordings: [rec('v', 'me')], details: [det('v', 'me')], myId: 'me')
        .single.gradeRange, isNull);
  });

  test('Hinweise: neueste zuerst, „neu" nur von Buddys, 7 Tage, ungesehen', () {
    final now = DateTime(2026, 9, 28, 12);
    TrailNote note(String user, int daysAgo) => TrailNote(
          id: '$user-$daysAgo',
          trailId: 't',
          userId: user,
          body: 'Baum quer',
          createdAt: now.subtract(Duration(days: daysAgo)),
        );
    Trail trail(List<TrailNote> notes) => buildTrails(
          recordings: [rec('t', 'me'), rec('t', 'bob')],
          details: const [],
          notes: [...notes, note('bob', 1).copyTrail('anderer')],
          myId: 'me',
        ).singleWhere((t) => t.id == 't');

    final t = trail([note('bob', 9), note('me', 0), note('bob', 3)]);
    expect(t.notes, hasLength(3), reason: 'Hinweise anderer Trails bleiben dort');
    expect(t.notesShown(now: now).map((n) => n.id), ['me-0', 'bob-3', 'bob-9']);
    expect(t.hasFreshNote(now: now), isTrue);
    expect(t.hasFreshNote(now: now, seen: {'bob-3'}), isFalse,
        reason: 'im Blatt gesehen: nicht mehr hervorgehoben');
    expect(trail([note('me', 0), note('bob', 8)]).hasFreshNote(now: now), isFalse,
        reason: 'der eigene zählt nicht, der alte ist nicht mehr neu');
  });

  test('nach 90 Tagen nur noch der jüngste', () {
    final now = DateTime(2026, 9, 28, 12);
    TrailNote note(String user, int daysAgo) => TrailNote(
          id: '$user-$daysAgo',
          trailId: 't',
          userId: user,
          body: 'x',
          createdAt: now.subtract(Duration(days: daysAgo)),
        );
    Trail trail(List<TrailNote> notes) => Trail(
        id: 't', myId: 'me', recordings: [rec('t', 'me')], details: const [], notes: notes);

    expect(trail([note('bob', 200), note('anna', 120), note('bob', 95)])
            .notesShown(now: now)
            .map((n) => n.id),
        ['bob-95'], reason: 'alle alt: der jüngste bleibt stehen');
    expect(trail([note('bob', 200), note('anna', 10), note('bob', 89)])
            .notesShown(now: now)
            .map((n) => n.id),
        ['anna-10', 'bob-89']);
  });

  test('Namen aus Dateien passen in den Check der Datenbank', () {
    expect(clampTrailName('  Wurzeltrail '), 'Wurzeltrail');
    final exact = 'x' * kTrailNameMaxLength;
    expect(clampTrailName(exact), exact);
    final words = List.filled(20, 'Wort').join(' ');   // 99 Zeichen
    final cut = clampTrailName(words);
    expect(cut.length, lessThanOrEqualTo(kTrailNameMaxLength));
    expect(cut, endsWith('Wort…'), reason: 'am Wortende gekürzt');
    final blob = 'y' * 120;
    expect(clampTrailName(blob), '${'y' * (kTrailNameMaxLength - 1)}…');
  });

  test('TrailNote.fromJson liest den Autor aus dem Embed', () {
    final n = TrailNote.fromJson({
      'id': 'n1',
      'trail_id': 't',
      'user_id': 'u',
      'body': 'Neuer Drop am Ende',
      'created_at': '2026-09-28T10:00:00Z',
      'author': {'username': 'bob'},
    });
    expect(n.username, 'bob');
    expect(n.body, 'Neuer Drop am Ende');
    expect(n.createdAt.isUtc, isFalse);
  });
}

extension on TrailNote {
  TrailNote copyTrail(String trailId) => TrailNote(
      id: '$id-x', trailId: trailId, userId: userId, body: body, createdAt: createdAt);
}
