import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/errors.dart';
import 'core/settings.dart';
import 'core/supabase_config.dart';
import 'data/error_report_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  final reports = ErrorReportRepository(Supabase.instance.client);
  // Absichtlich ohne await: das Melden darf den Programmfluss weder
  // aufhalten noch scheitern lassen. Fehler beim Melden werden geschluckt —
  // sie hier zu loggen wäre eine Endlosschleife.
  //
  // Im Web nur, wenn die App NICHT von der eigenen Maschine kommt
  // ([reportsFromHost]) — sonst schreiben Testläufe in die echte Tabelle.
  if (!kIsWeb || reportsFromHost(Uri.base.host)) {
    setErrorSink((context, error, stackTrace) {
      reports.report(context, error, stackTrace).catchError((Object _) {});
    });
  }

  // Auch nicht gefangene Fehler melden. Android Vitals sieht davon nur die
  // Play-Installationen; Web und die GitHub-APK bleiben sonst blind.
  //
  // `worthReporting` siebt vorher aus, was hier regelmäßig landet, ohne dass
  // etwas kaputt ist (Abfragen nach dem Abmelden, fehlender Empfang) — dann
  // auch nicht ins Log: Bei Hunderten Fällen pro Woche wäre es dort genauso
  // Rauschen wie in der Datenbank. Nur diese globalen Handler filtern; ein
  // `logError` mit eigenem Kontext meldet weiterhin alles.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    if (worthReporting(details.exception)) {
      logError('Flutter-Fehler', details.exception, details.stack);
    }
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (worthReporting(error)) logError('Unbehandelter Fehler', error, stack);
    return false; // false: Standardbehandlung nicht unterdrücken.
  };

  // Vor runApp, damit die Einstellungen schon im ersten Frame gelten. Der
  // Aufruf liest eine kleine lokale Datei — er darf den Start aufhalten,
  // ein sichtbares Umschalten nicht.
  final settings = PrefsSettings(await SharedPreferences.getInstance());

  runApp(ProviderScope(
    overrides: [settingsProvider.overrideWithValue(settings)],
    child: const TrailBuddyApp(),
  ));
}
