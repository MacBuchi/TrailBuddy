// Das Geräteregister für Push-Benachrichtigungen (#34, Patch 008).
//
// Eine Zeile in `push_devices` IST die Zustimmung dieses Geräts — es gibt
// bewusst keine Spalte „aktiv", die dasselbe ein zweites Mal behaupten
// könnte. Abschalten heißt: Zeile weg.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session.dart';

class PushRepository {
  PushRepository(this._client);

  final SupabaseClient _client;

  static String get _platform => kIsWeb ? 'web' : 'android';

  /// Dieses Gerät eintragen — oder die vorhandene Zeile auffrischen.
  ///
  /// `onConflict: 'token'` ist der ganze Witz: Meldet sich am selben Gerät
  /// jemand anders an, wandert die Zeile auf das neue Konto, statt daneben
  /// stehen zu bleiben. Ohne das bekäme der Vorbesitzer weiter Meldungen
  /// über fremde Trails.
  Future<void> register(String token) async {
    await _client.from('push_devices').upsert({
      'token': token,
      'user_id': _client.requireUid,
      'platform': _platform,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  /// Dieses Gerät austragen. Nach dem Löschen kommt hier nichts mehr an.
  Future<void> unregister(String token) async {
    await _client.from('push_devices').delete().eq('token', token);
  }

  /// „Schick mir einmal eine, damit ich sehe, dass es geht."
  ///
  /// Ruft `send-push` mit dem JWT der Nutzerin. Die Function hat das
  /// Job-Geheimnis nicht von uns bekommen und prüft deshalb über die RLS,
  /// ob das Token wirklich diesem Konto gehört — die App braucht dafür
  /// keine eigene Berechtigung und bekommt auch keine.
  Future<void> sendTest(String token) async {
    await _client.functions.invoke('send-push', body: {'test': token});
  }
}
