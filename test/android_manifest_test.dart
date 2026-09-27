/// Die Android-Seite hat kein Test-Netz — außer diesem. Hält
/// applicationId, Kotlin-Pfad, Flavors, Berechtigungen und
/// Backup-Ausschlüsse zusammen (PilzBuddy-Muster, gekürzt).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final play = File('android/app/src/play/AndroidManifest.xml').readAsStringSync();
  final appId = RegExp(r'applicationId = "([a-z.]+)"').firstMatch(gradle)!.group(1)!;

  test('applicationId ist die eine Quelle', () {
    expect(appId, 'de.mcbuchi.trailbuddy');
    expect(gradle, contains('namespace = "$appId"'));
    expect(File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').existsSync(),
        isTrue, reason: 'Kotlin-Verzeichnis passt nicht zur applicationId');
    final map = File('lib/features/map/map_screen.dart').readAsStringSync();
    expect(map, contains("userAgentPackageName: '$appId'"));
  });

  test('der Install-Kanal heißt in Kotlin und Dart gleich', () {
    // Ein Tippfehler auf einer Seite antwortet stumm mit „kein Kanal",
    // und Dart fällt dann für immer auf den Browser zurück.
    final kotlin = File('android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt').readAsStringSync();
    final dart = File('lib/data/apk_installer.dart').readAsStringSync();
    const channel = 'de.mcbuchi.trailbuddy/apk_install';
    expect(kotlin, contains('"$channel"'));
    expect(dart, contains("'$channel'"));
    expect(manifest, contains('androidx.core.content.FileProvider'));
    expect(kotlin, contains('FileProvider.getUriForFile'));
  });

  test('zwei Flavors, eine App: play nimmt den Update-Weg heraus', () {
    expect(gradle, contains('create("github")'));
    expect(gradle, contains('create("play")'));
    final code = gradle.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    expect(code, isNot(contains('applicationIdSuffix')));
    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(play, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(play, contains('tools:node="remove"'));
    // Zwei Bindestriche in einem XML-Kommentar brechen den ManifestMerger.
    expect(play, isNot(contains('--dart-define')));
  });

  test('genau die Berechtigungen, die Phase 1 braucht', () {
    final perms = RegExp(r'android:name="android\.permission\.([A-Z_]+)"')
        .allMatches(manifest)
        .map((m) => m.group(1))
        .toSet();
    expect(perms, {'INTERNET', 'REQUEST_INSTALL_PACKAGES'});
  });

  test('beide Backup-Regeln schließen dasselbe aus', () {
    Set<String> excludes(String path) => RegExp(r'<exclude domain="(\w+)" path="([^"]+)"')
        .allMatches(File(path).readAsStringSync())
        .map((m) => '${m.group(1)}:${m.group(2)}')
        .toSet();
    final rules = excludes('android/app/src/main/res/xml/backup_rules.xml');
    final legacy = excludes('android/app/src/main/res/xml/full_backup_content.xml');
    expect(rules, legacy);
    expect(rules, containsAll(['sharedpref:FlutterSharedPreferences.xml',
        'file:rides', 'file:trail_cache', 'file:outbox', 'file:updates']));
    expect(manifest, contains('@xml/backup_rules'));
    expect(manifest, contains('@xml/full_backup_content'));
  });
}
