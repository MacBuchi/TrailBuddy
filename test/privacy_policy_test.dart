/// Wacht über die Rechtsseiten und über die Regel „kein Netzziel ohne
/// Eintrag in der Datenschutzerklärung" (PilzBuddy #110). Nicht die
/// Erklärung wird auf Vollständigkeit geprüft, sondern der umgekehrte Weg:
/// Taucht in `lib/` oder `web/` ein Host auf, den hier niemand eingeordnet
/// hat, bricht der Test.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/app_info.dart';

const _privacy = 'web/datenschutz.html';
const _impressum = 'web/impressum.html';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path fehlt');
  return file.readAsStringSync();
}

void main() {
  test('die verlinkten Seiten liegen wirklich im Web-Verzeichnis', () {
    expect(AppInfo.privacyUrl, endsWith('/datenschutz.html'));
    expect(AppInfo.deleteAccountUrl, endsWith('/konto-loeschen.html'));
    expect(AppInfo.impressumUrl, endsWith('/impressum.html'));
    for (final p in [_privacy, _impressum, 'web/konto-loeschen.html']) {
      expect(File(p).existsSync(), isTrue, reason: p);
    }
  });

  test('das Impressum trägt eine ladungsfähige Anschrift', () {
    final html = _read(_impressum);
    expect(RegExp(r'[A-ZÄÖÜ][\wäöüß.\-]*\s?(str\.|straße|weg|platz|gasse)\s+\d',
            caseSensitive: false).hasMatch(html), isTrue);
    expect(RegExp(r'\b\d{5}\s+\S').hasMatch(html), isTrue);
    expect(html, contains('mailto:'));
  });

  test('das Impressum ist aus der App und den Nachbarseiten erreichbar', () {
    expect(_read('lib/features/profile/profile_screen.dart'), contains('AppInfo.impressumUrl'));
    expect(_read(_privacy), contains('impressum.html'));
    expect(_read('web/konto-loeschen.html'), contains('impressum.html'));
    for (final p in [_impressum, _privacy]) {
      expect(_read(p), isNot(contains('ec.europa.eu/consumers/odr')));
    }
  });

  test('die Erklärung benennt die heiklen Punkte', () {
    final html = _read(_privacy);
    expect(html, contains('tile.openstreetmap.org'));
    expect(html, contains('Trail-Aufzeichnungen'));
    expect(html, contains('verlassen dein Gerät nie'),
        reason: 'Entscheidung 4 im Konzept: Fahrten bleiben lokal');
    expect(html, contains('öffentlich'));
    expect(html, contains('Konto löschen'));
    expect(html, contains('Fehlerberichte'));
    expect(html, contains('Supabase'));
    expect(html, contains('Brevo'));
    expect(html, contains('Bestätigungsmail'));
    expect(html, contains('fonts.gstatic.com'),
        reason: 'Roboto wird im Web von Google geladen (PilzBuddy #393)');
  });

  test('kein neues Netzziel ohne Eintrag in der Datenschutzerklärung', () {
    /// Ziele, die die App von sich aus abruft — MÜSSEN in der Erklärung stehen.
    const fetched = {
      'tile.openstreetmap.org',
      'api.github.com',
      'github.com',
      'macbuchi.github.io',
      // Das Live-Projekt (lib/core/supabase_config.dart).
      'jmvnsnqyvlqdnpujoqdy.supabase.co',
    };
    /// Ziele, die erst der Nutzer mit einem Tipp öffnet.
    const onTapOnly = {
      'www.openstreetmap.org',
      'play.google.com',
    };
    /// Nur Text, nicht tippbar (Namensräume, Schemas).
    const textOnly = {
      'schemas.android.com',
      'www.topografix.com',
      'www.w3.org',
      'www.garmin.com',
      'www.locusmap.eu',
      'developer.mozilla.org',
      'docs.flutter.dev',
      'developer.android.com',
      'flutter.dev',
      'github.io',
    };
    final privacy = _read(_privacy);
    final hostPattern = RegExp(r'https?://([a-z0-9.-]+\.[a-z]{2,})', caseSensitive: false);
    final found = <String, Set<String>>{};
    for (final dir in ['lib', 'web']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!(f.path.endsWith('.dart') || f.path.endsWith('.js') ||
            f.path.endsWith('.html') || f.path.endsWith('.json'))) {
          continue;
        }
        if (f.path == _privacy || f.path == _impressum || f.path.endsWith('konto-loeschen.html')) {
          continue;
        }
        for (final m in hostPattern.allMatches(f.readAsStringSync())) {
          found.putIfAbsent(m.group(1)!.toLowerCase(), () => {}).add(f.path);
        }
      }
    }
    final unknown = found.keys
        .where((h) => !fetched.contains(h) && !onTapOnly.contains(h) && !textOnly.contains(h))
        .toList();
    expect(unknown, isEmpty,
        reason: 'Neue Hosts ohne Einordnung: ${unknown.map((h) => '$h (${found[h]!.join(', ')})').join('; ')}. '
            'In diesem Test einordnen UND, wenn abgerufen, in web/datenschutz.html erklären.');
    for (final h in fetched) {
      expect(privacy, contains(h), reason: '$h wird abgerufen und fehlt in der Erklärung');
    }
  });
}
