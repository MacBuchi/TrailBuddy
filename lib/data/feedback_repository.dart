import 'package:supabase_flutter/supabase_flutter.dart';

import 'session.dart';

enum FeedbackType { feature, bug }

/// So viele Zeichen braucht der Text, bevor „Senden" antippbar wird.
///
/// **„Senden" ist nur aktiv, wenn danach wirklich gesendet wird.** Ein
/// grauer Knopf mit dem Grund darunter sagt es vorher; eine SnackBar nach
/// dem Tipp sagt es zu spät.
const kFeedbackMinChars = 3;

/// In-App-Feedback, Text pur (`public.feedback`: user_id, type, message,
/// app_version). Der Feedback-Bot macht daraus GitHub-Issues.
class FeedbackRepository {
  FeedbackRepository(this._client);

  final SupabaseClient _client;

  /// Feature-Wunsch oder Bug-Meldung einreichen.
  ///
  /// [appVersion] steht im Issue. Ohne sie ist bei einer Feldmeldung nicht
  /// entscheidbar, ob sie ein Duplikat einer schon behobenen ist oder ein
  /// neuer Fehler im frischen Stand. `null` ist erlaubt und heißt schlicht
  /// „unbekannt": Eine erfundene Version wäre schlimmer.
  ///
  /// Sie kommt als PARAMETER und nicht aus `PackageInfo` im Repository:
  /// `appVersionProvider` hält sie ohnehin schon, und über den Parameter
  /// ist sie im Test überprüfbar statt immer null.
  Future<void> submit(FeedbackType type, String message,
      {String? appVersion}) async {
    await _client.from('feedback').insert({
      'user_id': _client.requireUid,
      'type': type == FeedbackType.bug ? 'bug' : 'feature',
      'message': message.trim(),
      'app_version': appVersion,
    });
  }
}
