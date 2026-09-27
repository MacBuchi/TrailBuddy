import 'package:supabase_flutter/supabase_flutter.dart';

/// Liest die server-seitige App-Konfiguration aus `public.app_config` —
/// heute nur die Mindestversion.
///
/// Die Tabelle hat genau eine Zeile und ist für anon lesbar: die Prüfung
/// läuft beim Start und damit vor der Anmeldung.
class AppConfigRepository {
  AppConfigRepository(this._client);

  final SupabaseClient _client;

  /// Kleinste Version, die noch zum Live-Schema passt — oder `null`, wenn
  /// die Zeile fehlt. Der Aufrufer behandelt `null` als „unbekannt" und
  /// sperrt dann nicht.
  Future<String?> fetchMinimumSupportedVersion() async {
    final row = await _client
        .from('app_config')
        .select('minimum_supported_version')
        .maybeSingle();
    return row?['minimum_supported_version'] as String?;
  }
}
