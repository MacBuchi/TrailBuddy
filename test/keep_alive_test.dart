// Der geteilte Foreground-Service (PilzBuddy #264/#338, hier seit
// Konzept-Schritt 3): Fahrt und Bereichs-Download laufen im selben
// Prozess und brauchen beide denselben Service. Ohne Koordinator
// beendete das `stop()` des einen ihn dem anderen mitten im Lauf.
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/keep_alive/keep_alive.dart';
import 'package:trailbuddy/features/rides/ride_service.dart';

import 'fakes/fake_keep_alive.dart';

void main() {
  late FakeKeepAlive service;
  late KeepAliveCoordinator coordinator;

  setUp(() {
    service = FakeKeepAlive();
    coordinator = KeepAliveCoordinator(service);
  });

  test('zwei Melder teilen sich EINEN Service, und er endet mit dem letzten', () async {
    await coordinator.start('areas', 'Isartrails — 10 %', title: 'Bereich wird gespeichert');
    await coordinator.start('areas2', 'Alpen — 0 %', title: 'Bereich wird gespeichert');
    expect(service.running, isTrue);
    expect(service.starts, 1, reason: 'nicht zwei Services nebeneinander');
    expect(service.texts.last, allOf(contains('Isartrails'), contains('Alpen')));

    await coordinator.stop('areas');
    expect(service.running, isTrue);
    expect(service.texts.last, isNot(contains('Isartrails')));
    await coordinator.stop('areas2');
    expect(service.running, isFalse, reason: 'eine Dauerbenachrichtigung wäre grob unhöflich');
    await coordinator.stop('areas2');
    expect(service.starts, 1);
  });

  test('unveränderter Text und unbekannte Schlüssel gehen nicht über den Kanal', () async {
    await coordinator.start('areas', 'Isartrails — 10 %', title: 'Bereich wird gespeichert');
    final before = service.texts.length;
    await coordinator.update('areas', 'Isartrails — 10 %');
    await coordinator.update('nobody', 'x');
    expect(service.texts.length, before);
    await coordinator.update('areas', 'Isartrails — 20 %');
    expect(service.texts.last, 'Isartrails — 20 %');
  });

  test('eine Fahrt startet als location; ein Download dazu startet den Service NEU', () async {
    await coordinator.start('ride', 'Fahrt läuft',
        title: 'Fahrt wird aufgezeichnet', types: const {KeepAliveType.location});
    expect(service.types, {KeepAliveType.location});
    await coordinator.start('areas', 'Isartrails — 0 %', title: 'Bereich wird gespeichert');
    expect(service.starts, 2, reason: 'die Typmenge hat sich geändert');
    expect(service.types, {KeepAliveType.location, KeepAliveType.dataSync});
    expect(service.titles.last, 'TrailBuddy arbeitet', reason: 'zwei Sorten ⇒ neutraler Titel');

    // Gleiche Typen starten nicht neu.
    await coordinator.start('areas2', 'Alpen — 0 %', title: 'Bereich wird gespeichert');
    expect(service.starts, 2);
  });

  test('die Fahrt setzt den Takt und nimmt ihn beim Beenden zurück', () async {
    final ride = CoordinatedRideService(coordinator);
    await ride.start(title: 'Fahrt wird aufgezeichnet', text: 'läuft', every: const Duration(seconds: 5));
    expect(service.running, isTrue);
    expect(service.repeat, const Duration(seconds: 5));
    expect(service.types, {KeepAliveType.location});
    await ride.stop();
    expect(service.repeat, isNull);
    expect(service.running, isFalse);
  });
}
