// Wacht über die ausgelieferte Änderungsliste. Der wichtigste Test ist der
// letzte: Eine Version, die veröffentlicht wird, ohne in CHANGELOG.md
// aufzutauchen, macht die Liste in der App still unvollständig — und genau
// das passiert, wenn niemand daran erinnert wird.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/changelog/changelog_parser.dart';
import 'package:trailbuddy/features/changelog/changelog_screen.dart';

String _changelog() {
  final file = File(changelogAsset);
  expect(file.existsSync(), isTrue, reason: '$changelogAsset fehlt');
  return file.readAsStringSync();
}

void main() {
  group('Parser', () {
    test('erkennt Überschrift, Metazeile, Absatz und Aufzählung', () {
      final lines = parseChangelog('''
# Titel

## Ein Block

*2. August 2026 · Version 1.33.0*

Ein Absatz, der über
zwei Zeilen umgebrochen ist.

- Ein Punkt
- Noch einer
''');

      expect(lines.map((l) => l.kind), [
        ChangelogLineKind.title,
        ChangelogLineKind.section,
        ChangelogLineKind.meta,
        ChangelogLineKind.text,
        ChangelogLineKind.bullet,
        ChangelogLineKind.bullet,
      ]);
      expect(lines[1].text, 'Ein Block');
      expect(lines[2].text, '2. August 2026 · Version 1.33.0');
      // Umbruch innerhalb des Absatzes wird zusammengefasst, sonst bräche
      // der Text auf dem Handy an den Stellen der Datei statt am Rand.
      expect(lines[3].text, 'Ein Absatz, der über zwei Zeilen umgebrochen ist.');
      expect(lines[5].text, 'Noch einer');
    });

    test('trennt **fett** heraus und lässt unpaarige Sternchen stehen', () {
      final bold = parseChangelog('**Behoben:** Die Karte blieb leer.').single;
      expect(bold.segments.map((s) => s.bold), [true, false]);
      expect(bold.segments.first.text, 'Behoben:');
      expect(bold.text, 'Behoben: Die Karte blieb leer.');

      // Ein einzelnes ** darf nicht den Rest der Zeile verschlucken.
      final broken = parseChangelog('Ein **halb offener Text').single;
      expect(broken.text, 'Ein **halb offener Text');
      expect(broken.segments.every((s) => !s.bold), isTrue);
    });

    test('hält eine fett beginnende Zeile nicht für die Metazeile', () {
      // `*…*` und `**…**` unterscheiden sich nur im zweiten Zeichen.
      final line = parseChangelog('**Behoben:** etwas*').single;
      expect(line.kind, ChangelogLineKind.text);
    });
  });

  group('Die ausgelieferte Datei', () {
    test('besteht aus Themenblöcken mit Datums- und Versionszeile', () {
      final lines = parseChangelog(_changelog());
      final sections = lines
          .where((l) => l.kind == ChangelogLineKind.section)
          .toList();
      expect(sections, isNotEmpty,
          reason: 'Die Liste soll nach Themen gegliedert sein');

      // Jeder Block außer „Unter der Haube" (ohne Versionen) nennt Datum
      // und Versionen — ohne die lässt sich ein Eintrag keiner
      // installierten App zuordnen.
      for (var i = 0; i < lines.length - 1; i++) {
        if (lines[i].kind != ChangelogLineKind.section) continue;
        if (lines[i].text == 'Unter der Haube') continue;
        expect(lines[i + 1].kind, ChangelogLineKind.meta,
            reason: 'Block „${lines[i].text}" hat keine Datums-/Versionszeile');
      }
    });

    test('enthält keine Markdown-Links', () {
      // Die App rendert nur Überschriften, Aufzählungen und **fett** — ein
      // `[Text](URL)` stünde dort roh auf dem Bildschirm.
      expect(RegExp(r'\[[^\]]+\]\([^)]+\)').hasMatch(_changelog()), isFalse,
          reason: 'Nackte URL schreiben statt [Text](URL)');
    });

    test('nennt die aktuelle Version aus pubspec.yaml', () {
      // Wer die Version hochsetzt, trägt sie hier ein — entweder als neuer
      // Block oder indem er den obersten Block darauf erweitert. Ohne
      // diesen Test fällt eine vergessene Zeile erst auf, wenn jemand in
      // der App nachsieht.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
              multiLine: true)
          .firstMatch(pubspec)
          ?.group(1);
      expect(version, isNotNull, reason: 'version fehlt in pubspec.yaml');

      expect(_changelog(), contains(version!),
          reason: 'Version $version steht in pubspec.yaml, aber nicht in '
              '$changelogAsset. Neuen Block anlegen oder den obersten Block '
              'auf diese Version erweitern.');
    });
  });
}
