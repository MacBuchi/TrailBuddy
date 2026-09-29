// Die Kopie des Netzes von außen (#32): Ein Kaltstart ohne Empfang zeigt
// die Trails vom letzten Mal und sagt es; ein Serverfehler bleibt ein
// Fehler; Abmelden räumt die Kopie ab.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_trail_cache.dart';
import '../fakes/fake_trails.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late String annaId;
  late FakeTrailRepository trails;
  late FakeTrailCache cache;

  setUp(() {
    backend = FakeBackend();
    final anna = backend.addUser(username: 'anna');
    backend.signInAs(anna.id);
    annaId = anna.id;
    trails = FakeTrailRepository(myId: () => backend.currentUserId ?? '');
    trails.seedTrail(annaId, name: 'Roots', grade: 2);
    cache = FakeTrailCache();
  });

  final noticeMap = find.byKey(const ValueKey('cached-notice'));
  final noticeList = find.byKey(const ValueKey('cached-notice-list'));

  testWidgets('online: Kopie geschrieben, kein Hinweis', (tester) async {
    await pumpApp(tester, backend, trails: trails, trailCache: cache);
    await settle(tester, frames: 12);
    expect(cache.writes, 1);
    expect(cache.uid, annaId);
    expect(cache.snapshot!.recordings, hasLength(1));
    expect(noticeMap, findsNothing);
  });

  testWidgets('Kaltstart ohne Empfang: die Trails vom letzten Mal, mit Hinweis',
      (tester) async {
    // Der letzte Online-Stand liegt in der Kopie …
    await pumpApp(tester, backend, trails: trails, trailCache: cache);
    await settle(tester, frames: 12);
    // … und die App startet neu im Funkloch.
    final backend2 = FakeBackend();
    final anna = backend2.addUser(username: 'anna');
    backend2.signInAs(anna.id);
    // Dasselbe Konto wie vor dem Neustart: Die Kopie ist an die Kennung
    // gebunden.
    cache.uid = anna.id;
    trails = FakeTrailRepository(myId: () => backend2.currentUserId ?? '');
    trails.failFetch = const SocketException('offline');
    await pumpApp(tester, backend2, trails: trails, trailCache: cache);
    await settle(tester, frames: 12);
    expect(noticeMap, findsOneWidget);
    expect(find.textContaining('Kein Empfang — Trails vom'), findsOneWidget);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 12);
    expect(find.text('Roots'), findsOneWidget);
    expect(noticeList, findsOneWidget);
    // Das Blatt funktioniert auf der Kopie.
    await tester.tap(find.text('Roots'));
    await settle(tester);
    expect(findLabel('S2 · 1 Einschätzung'), findsOneWidget);
  });

  testWidgets('ein Serverfehler bleibt ein Fehler — nichts aus der Kopie', (tester) async {
    await pumpApp(tester, backend, trails: trails, trailCache: cache);
    await settle(tester, frames: 12);
    final backend2 = FakeBackend();
    final anna = backend2.addUser(username: 'anna');
    backend2.signInAs(anna.id);
    cache.uid = anna.id;
    trails = FakeTrailRepository(myId: () => backend2.currentUserId ?? '');
    trails.failFetch = StateError('42501: RLS kaputt');
    await pumpApp(tester, backend2, trails: trails, trailCache: cache);
    await settle(tester, frames: 12);
    expect(noticeMap, findsNothing);
    await openTab(tester, 'Trails');
    await settle(tester, frames: 12);
    expect(find.text('Roots'), findsNothing);
    expect(noticeList, findsNothing);
  });

  testWidgets('Abmelden räumt die Kopie ab', (tester) async {
    await pumpApp(tester, backend, trails: trails, trailCache: cache);
    await settle(tester, frames: 12);
    expect(cache.snapshot, isNotNull);
    await openTab(tester, 'Profil');
    await tester.tap(find.byTooltip('Abmelden'));
    await settle(tester, frames: 12);
    expect(cache.clears, 1);
    expect(cache.snapshot, isNull);
  });
}
