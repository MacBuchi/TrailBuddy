/// Wächter über die Workflows — Konfigurationsfehler fängt nur ein
/// Konfigurations-Regressionstest (PilzBuddy-Muster). Die Fallen hier
/// sind alle still: Jede kompiliert, jede PR-CI bleibt grün.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflows = Directory('.github/workflows')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yml'))
      .toList();
  final ci = File('.github/workflows/ci.yml').readAsStringSync();
  final release = File('.github/workflows/release.yml').readAsStringSync();

  test('es gibt die Workflows des Grundgerüsts', () {
    final names = workflows.map((f) => f.uri.pathSegments.last).toSet();
    expect(names, containsAll([
      'ci.yml', 'release.yml', 'security.yml', 'workflow-lint.yml',
      'keepalive.yml',
    ]));
  });

  test('alle Workflows pinnen dieselbe Flutter-Version', () {
    final versions = <String>{};
    for (final f in workflows) {
      for (final m in RegExp(r'flutter-version:\s*([0-9.]+)')
          .allMatches(f.readAsStringSync())) {
        versions.add(m.group(1)!);
      }
    }
    expect(versions, hasLength(1),
        reason: 'Flutter-Version driftet zwischen Workflows: $versions');
  });

  test('jeder Web-Build holt CanvasKit aus dem eigenen Build', () {
    final builds = [
      for (final line in ci.split('\n'))
        if (line.contains('flutter build web')) line,
    ];
    expect(builds, isNotEmpty);
    for (final b in builds) {
      expect(b, contains('--no-web-resources-cdn'));
      expect(b, contains('--base-href /trailbuddy/'));
    }
  });

  test('CI fährt den Service Worker gegen einen echten Browser', () {
    expect(ci, contains('node tool/check_service_worker.mjs build/web'));
    expect(File('tool/check_service_worker.mjs').existsSync(), isTrue);
  });

  test('jeder Merge veröffentlicht als Prerelease, nie als latest', () {
    // Beide Zeilen gehören zusammen: `prerelease` allein genügt nicht.
    expect(release, contains('prerelease: true'));
    expect(release, contains('make_latest: false'));
  });

  test('kein Keystore, kein Tag: das Tor steht VOR dem Taggen', () {
    // Ein Tag ohne Release ist nur von Hand zu heilen. Der Feststell-Schritt
    // muss im version-Job vor `git tag` stehen und das `decide` daran hängen.
    final versionJob = release.substring(
        release.indexOf('  version:'), release.indexOf('  build-android:'));
    final gate = versionJob.indexOf('id: keystore');
    final tag = versionJob.indexOf('git tag');
    expect(gate, greaterThan(-1));
    expect(tag, greaterThan(gate));
    expect(versionJob, contains("if: steps.keystore.outputs.have == 'true'"));
  });

  test('kein secrets-Kontext in if-Bedingungen', () {
    // `secrets` ist in `if:` NICHT verfügbar — GitHub verwirft dann die
    // ganze Datei beim Einlesen, ohne roten Check (PilzBuddy, 2026-08-13).
    final offenders = <String>[];
    for (final file in workflows) {
      var line = 0;
      for (final raw in file.readAsLinesSync()) {
        line++;
        final code = raw.split('#').first;
        if (RegExp(r'\bif:').hasMatch(code) && code.contains('secrets.')) {
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('Secrets gehen über env: in die Shell, nie interpoliert', () {
    // `${{ secrets.X }}` direkt in einem run:-Block landet im Klartext im
    // Skript; über env: bleibt es eine Umgebungsvariable.
    for (final file in workflows) {
      var inRun = false;
      var line = 0;
      for (final raw in file.readAsLinesSync()) {
        line++;
        if (RegExp(r'^\s*run:').hasMatch(raw)) inRun = true;
        if (RegExp(r'^\s*-\s*(name|uses|id):|^\s*(env|with|if):').hasMatch(raw)) {
          inRun = false;
        }
        if (inRun && raw.contains(r'${{ secrets.')) {
          fail('${file.path}:$line interpoliert ein Secret im run:-Block');
        }
      }
    }
  });

  test('Release baut beide Flavors, und die Pfade tragen den Namen', () {
    expect(release, contains('--flavor github'));
    expect(release, contains('app-github-release.apk'));
    expect(release, contains('--flavor play'));
    expect(release, contains('playRelease/app-play-release.aab'));
    expect(release, contains('-Pdisable-abi-filtering=true'));
    expect(ci, contains('--flavor play'));
  });

  test('der Dry Run fährt beide Wege und den Abgleich', () {
    expect(ci, contains('tool/patch_guard.sh'));
    expect(ci, contains('tool/db_migrate.sh'));
    expect(ci, contains('tool/schema_check.sh'));
    expect(ci, contains('tool/matcher_check.sql'));
    expect(ci, contains('supabase db reset'));
    // Portblock 5452x (supabase/config.toml) — Drift zwischen Workflow und
    // Konfiguration wäre ein Dry Run gegen eine fremde Datenbank.
    final config = File('supabase/config.toml').readAsStringSync();
    expect(config, contains('port = 54521'));
    expect(config, contains('port = 54522'));
    expect(ci, contains('127.0.0.1:54522'));
    expect(ci, contains('http://127.0.0.1:54521'));
  });

  test('Version Guard nimmt genau die Nicht-Binary-Pfade aus', () {
    for (final ex in [":!*.md'", ":!.github'", ":!tool'", ":!supabase'", ":!docs'"]) {
      expect(ci, contains(ex));
    }
    expect(ci, contains('-- CHANGELOG.md'),
        reason: 'CHANGELOG.md liegt im Binary und braucht den Bump');
  });

  test('die Live-Datenbank wird erst nach dem Dry Run angefasst', () {
    final job = ci.substring(
        ci.indexOf('  schema-check:'), ci.indexOf('  housekeeping:'));
    expect(job, contains('needs: schema-dry-run'));
    expect(job, contains('SUPABASE_DB_URL: \${{ secrets.SUPABASE_DB_URL }}'));
    expect(job, contains('bash tool/db_migrate.sh'));
    expect(job, contains('bash tool/schema_check.sh'));
    // Ohne Historie hält db_migrate.sh jeden secretlosen Lauf für rot.
    expect(job, contains('fetch-depth: 0'));
  });

  test('Release migriert und prüft VOR dem Bauen', () {
    final build = release.substring(release.indexOf('  build-android:'));
    expect(build, contains('needs: [version, migrate]'));
    final migrate = release.substring(
        release.indexOf('  migrate:'), release.indexOf('  build-android:'));
    expect(migrate, contains('bash tool/db_migrate.sh'));
    expect(migrate, contains('bash tool/schema_check.sh'));
  });

  test('der Frisch-Weg im Dry Run ist der Bootstrap des Live-Projekts', () {
    // Ein leeres Projekt bekommt schema.sql über db_migrate.sh — derselbe
    // Zweig muss im Dry Run laufen, sonst fährt die Produktion etwas, das
    // CI nie gesehen hat.
    final fresh = ci.substring(ci.indexOf('supabase db reset'));
    expect(fresh.indexOf('bash tool/db_migrate.sh'), greaterThan(-1));
    expect(fresh, isNot(contains('-f supabase/schema.sql')));
    expect(File('tool/db_migrate.sh').readAsStringSync(),
        contains('-f supabase/schema.sql'));
  });

  test('das Live-Projekt wird wach gehalten', () {
    // Free-Plan pausiert nach ~1 Woche ohne Zugriff.
    final keep = File('.github/workflows/keepalive.yml').readAsStringSync();
    final cron = RegExp(r'cron: "[^"]*\* \* ([0-9,]+)"').firstMatch(keep);
    expect(cron, isNotNull);
    final days = cron!.group(1)!.split(',').map(int.parse).toList()..sort();
    // Größte Lücke zwischen zwei Läufen, über das Wochenende hinweg.
    var gap = days.first + 7 - days.last;
    for (var i = 1; i < days.length; i++) {
      gap = gap > days[i] - days[i - 1] ? gap : days[i] - days[i - 1];
    }
    expect(gap, lessThan(7));
    expect(keep, contains('bash tool/schema_check.sh'));
  });

  test('der Dry Run gibt Tabellen nicht automatisch frei', () {
    // Mit `true` ersetzte die Vorgabe einen vergessenen Grant still.
    final config = File('supabase/config.toml').readAsStringSync();
    expect(config, contains('auto_expose_new_tables = false'));
  });

  test('Workflows mit Pflicht-Checks starten auf JEDEM PR', () {
    // Ein Pflicht-Check hinter einem Pfadfilter meldet sich auf einem PR,
    // der die Pfade nicht berührt, nie — der PR bleibt „blocked", obwohl
    // alles grün ist (so passiert mit Workflow Lint an PR #6).
    for (final name in ['ci.yml', 'security.yml', 'workflow-lint.yml']) {
      final text = File('.github/workflows/$name').readAsStringSync();
      final code = text.split('\n').map((l) => l.split('#').first).join('\n');
      expect(RegExp(r'^\s*(paths|paths-ignore):', multiLine: true).hasMatch(code), isFalse,
          reason: '$name trägt einen Pfadfilter');
    }
  });
}
