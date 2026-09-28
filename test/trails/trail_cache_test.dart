// Die Kopie des Netzes (#32): Rundlauf Feld für Feld, fremdes Konto,
// Datei über `.part` + `rename` — und die Regel „nur ohne Empfang".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailbuddy/data/trail_cache.dart';
import 'package:trailbuddy/features/trails/trail_geometry.dart';
import 'package:trailbuddy/models/trail.dart';

import '../fakes/fake_trail_cache.dart';

void main() {
  final at = DateTime.utc(2026, 9, 28, 10);
  final recording = TrailRecording(
    id: 'rec-1',
    trailId: 'trail-1',
    userId: 'me',
    source: RecordingSource.app,
    recordedAt: at.subtract(const Duration(days: 2)).toLocal(),
    reversed: true,
    quality: 0.6,
    createdAt: at.toLocal(),
    points: const [LatLng(47.0, 11.0), LatLng(47.001, 11.001), LatLng(47.002, 11.0)],
    lengthM: 250.5,
    ele: const [900, 890, 880],
  );
  final noEle = TrailRecording(
    id: 'rec-2', trailId: 'trail-1', userId: 'bob', source: RecordingSource.planned,
    recordedAt: null, reversed: false, quality: 0.1, createdAt: at.toLocal(),
    points: const [LatLng(47.0, 11.0), LatLng(47.001, 11.001)], lengthM: 140,
  );
  final details = TrailDetails(
    trailId: 'trail-1', userId: 'bob', username: 'bob', name: 'Roots',
    description: 'wurzelig', grade: 3, kind: TrailKind.tech,
    visibility: TrailVisibility.buddies, status: TrailStatus.closed,
    statusAt: at.toLocal(), updatedAt: at.toLocal(),
  );
  final note = TrailNote(
      id: 'note-1', trailId: 'trail-1', userId: 'bob', body: 'Baum quer',
      createdAt: at.toLocal(), username: 'bob');
  final snapshot = (recordings: [recording, noEle], details: [details], notes: [note]);

  test('Rundlauf: die Kopie liest sich wie das Netz', () {
    final back = decodeTrailCache(encodeTrailCache(uid: 'me', snapshot: snapshot, savedAt: at), uid: 'me')!;
    expect(back.savedAt, at.toLocal());
    final r = back.snapshot.recordings[0];
    expect(r.id, 'rec-1');
    expect(r.trailId, 'trail-1');
    expect(r.userId, 'me');
    expect(r.source, RecordingSource.app);
    expect(r.recordedAt, recording.recordedAt);
    expect(r.reversed, isTrue);
    expect(r.quality, 0.6);
    expect(r.createdAt, recording.createdAt);
    expect(r.points, recording.points);
    expect(r.lengthM, 250.5);
    expect(r.ele, [900, 890, 880]);
    final r2 = back.snapshot.recordings[1];
    expect(r2.recordedAt, isNull);
    expect(r2.ele, isNull);
    expect(r2.source, RecordingSource.planned);
    final d = back.snapshot.details.single;
    expect(d.username, 'bob');
    expect(d.name, 'Roots');
    expect(d.description, 'wurzelig');
    expect(d.grade, 3);
    expect(d.kind, TrailKind.tech);
    expect(d.status, TrailStatus.closed);
    expect(d.statusAt, details.statusAt);
    expect(d.updatedAt, details.updatedAt);
    final n = back.snapshot.notes.single;
    expect(n.body, 'Baum quer');
    expect(n.username, 'bob');
    expect(n.createdAt, note.createdAt);
  });

  test('fremdes Konto und Unlesbares ergeben keine Kopie', () {
    final text = encodeTrailCache(uid: 'me', snapshot: snapshot, savedAt: at);
    expect(decodeTrailCache(text, uid: 'someone'), isNull);
    expect(decodeTrailCache('kaputt', uid: 'me'), isNull);
    expect(decodeTrailCache('{"uid":"me"}', uid: 'me'), isNull);
  });

  group('FileTrailCache', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('trail_cache_'));
    tearDown(() async => dir.delete(recursive: true));

    test('schreiben, lesen, löschen — keine .part bleibt liegen', () async {
      final cache = FileTrailCache(baseDir: dir);
      expect(await cache.read(uid: 'me'), isNull);
      await cache.write(uid: 'me', snapshot: snapshot, savedAt: at);
      final back = await FileTrailCache(baseDir: dir).read(uid: 'me');
      expect(back!.snapshot.recordings, hasLength(2));
      expect(await cache.read(uid: 'someone'), isNull);
      final files = dir.listSync(recursive: true).map((f) => f.path).toList();
      expect(files.where((p) => p.endsWith('.part')), isEmpty);
      await cache.clear();
      expect(await cache.read(uid: 'me'), isNull);
    });

    test('schreiben wirft nie, auch wenn es nicht geht', () async {
      await File('${dir.path}/blocked').writeAsString('x');
      final cache = FileTrailCache(baseDir: Directory('${dir.path}/blocked'));
      await cache.write(uid: 'me', snapshot: snapshot, savedAt: at);
      expect(await cache.read(uid: 'me'), isNull);
    });
  });

  group('fetchWithCache', () {
    test('Netz geht: frisch, und die Kopie wird geschrieben', () async {
      final cache = FakeTrailCache();
      final r = await fetchWithCache(fetch: () async => snapshot, cache: cache, uid: 'me', now: at);
      expect(r.cachedAt, isNull);
      expect(r.snapshot.recordings, hasLength(2));
      expect(cache.writes, 1);
      expect(cache.savedAt, at);
    });

    test('kein Netz: die Kopie, mit ihrem Alter', () async {
      final cache = FakeTrailCache()
        ..uid = 'me'
        ..snapshot = snapshot
        ..savedAt = at;
      final r = await fetchWithCache(
          fetch: () async => throw const SocketException('offline'),
          cache: cache, uid: 'me', now: at.add(const Duration(hours: 3)));
      expect(r.cachedAt, at);
      expect(r.snapshot.details.single.name, 'Roots');
      expect(cache.writes, 0);
    });

    test('kein Netz und keine Kopie: der Netzfehler', () async {
      expect(
          fetchWithCache(
              fetch: () async => throw const SocketException('offline'),
              cache: FakeTrailCache(), uid: 'me', now: at),
          throwsA(isA<SocketException>()));
    });

    test('ein Serverfehler wird NICHT aus der Kopie bedient', () async {
      final cache = FakeTrailCache()
        ..uid = 'me'
        ..snapshot = snapshot
        ..savedAt = at;
      expect(
          fetchWithCache(
              fetch: () async => throw StateError('42501: RLS'),
              cache: cache, uid: 'me', now: at),
          throwsA(isA<StateError>()));
    });
  });
}
