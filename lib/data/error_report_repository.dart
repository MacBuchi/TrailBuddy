import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Schreibt gefangene Fehler in `public.error_reports`.
///
/// Android Vitals zeigt nur harte Abstürze auf Play-Installationen. Die
/// Lücke sind die abgefangenen Fehler: die App zeigt eine SnackBar und läuft
/// weiter — ohne diesen Weg erfährt niemand davon.
///
/// Bewusst genügsam: keine Breadcrumbs, keine Nutzerkennung über die
/// user_id hinaus, keine Koordinaten. Was die App über den Nutzer weiß,
/// gehört nicht in einen Fehlerbericht.
class ErrorReportRepository {
  ErrorReportRepository(this._client);

  final SupabaseClient _client;

  /// Gekürzt auf die Längen aus dem Schema. Ein Fehlertext kann in
  /// Ausnahmefällen Nutzdaten enthalten (z. B. eine Server-Meldung mit
  /// Query-Fragment) — die Grenzen halten das klein und die Tabelle schlank.
  static String? _clip(String? value, int max) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
  }

  static String get _platform =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> report(
    String context,
    Object error,
    StackTrace? stackTrace,
  ) async {
    final version = await PackageInfo.fromPlatform()
        .then<String?>((info) => info.version)
        // Version ist nice-to-have; ohne sie ist der Bericht immer noch
        // wertvoll, deshalb hier schlucken statt den Bericht fallen zu
        // lassen.
        .catchError((Object _) => null);

    await _client.from('error_reports').insert({
      'user_id': _client.auth.currentUser?.id,
      'context': _clip(context, 100),
      'error_type': error.runtimeType.toString(),
      'message': _clip(error.toString(), 1000),
      'stack': _clip(stackTrace?.toString(), 4000),
      'app_version': version,
      'platform': _platform,
    });
  }
}
