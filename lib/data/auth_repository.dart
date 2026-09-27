import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  String? get currentUserId => _client.auth.currentUser?.id;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Legt ein Konto an. Liefert `true`, wenn die Adresse erst bestätigt
  /// werden muss.
  ///
  /// Steht „Confirm email" im Dashboard an, kommt aus `signUp` ein Nutzer
  /// OHNE Sitzung zurück — niemand ist danach angemeldet, und der Router
  /// bewegt sich nicht. Genau darauf verlässt sich der Registrieren-Screen
  /// sonst; ohne diese Rückgabe bliebe er stumm stehen. Der
  /// Rückgabewert macht beide Dashboard-Einstellungen bedienbar, ohne dass
  /// die App wissen muss, welche gerade gilt.
  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );
    return response.session == null;
  }

  /// Schickt die Bestätigungsmail noch einmal — für den häufigsten Fall,
  /// dass sie im Spam landet oder gelöscht wurde. Ohne das bliebe nur,
  /// ein zweites Konto anzulegen, und die Adresse ist schon vergeben.
  Future<void> resendConfirmation(String email) =>
      _client.auth.resend(type: OtpType.signup, email: email);

  /// Bestätigt die Adresse mit dem Code aus der Mail und meldet an.
  ///
  /// Wie beim Reset bewusst der Code und nicht der Link aus der Mail:
  /// `signUp` legt genauso einen PKCE-Verifier auf dem anfordernden Gerät
  /// ab (`gotrue_client.dart`), der Link wäre also gerätegebunden und
  /// stürbe beim Öffnen im Handy-Browser. Der Code funktioniert überall
  /// und meldet direkt an — `verifyOTP` liefert die Sitzung mit.
  Future<void> confirmEmailWithCode({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.signup,
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Meldet alle ANDEREN Geräte ab — die eigene Sitzung bleibt.
  ///
  /// Der Fall dahinter: Passwort auf einem verlorenen oder geteilten
  /// Gerät geändert — das alte Passwort gilt dort nicht mehr, die
  /// laufende Sitzung aber schon, bis ihr Refresh-Token stirbt. Dieser
  /// Aufruf beendet sie sofort. Eine Geräteliste mit Einzel-Abmeldung
  /// gibt GoTrue clientseitig nicht her; „alle anderen" ist das
  /// ehrliche Maximum.
  Future<void> signOutOtherDevices() =>
      _client.auth.signOut(scope: SignOutScope.others);

  /// Schickt einen Zahlencode zum Zurücksetzen des Passworts per Mail.
  ///
  /// Bewusst der Code aus der Mail und NICHT der enthaltene Link: Im
  /// PKCE-Standardflow legt Supabase beim Anfordern einen „code verifier"
  /// im Speicher des *anfragenden* Geräts ab und verlangt ihn beim Einlösen
  /// wieder (`gotrue`: `_generatePKCECodeChallenge`). Wer in der App
  /// anfordert und die Mail dann im Browser öffnet, hat ihn dort nicht —
  /// der Link stirbt mit „Code verifier could not be found in local
  /// storage.". Der Code ist gerätefrei und bleibt in derselben Maske.
  /// Die Mail-Vorlage im Dashboard führt deshalb `{{ .Token }}` und keinen
  /// Link; sonst existiert der kaputte Weg weiter.
  ///
  /// Wirft nicht, wenn es zu der Adresse kein Konto gibt — Supabase
  /// antwortet absichtlich gleich, damit daraus kein Konto-Orakel wird.
  /// Die Oberfläche muss dieselbe Meldung zeigen.
  Future<void> sendPasswordResetCode(String email) =>
      _client.auth.resetPasswordForEmail(email);

  /// Löst den Code ein und setzt das neue Passwort — in einem Schritt.
  ///
  /// `verifyOTP` legt eine Recovery-Sitzung an, erst `updateUser` macht das
  /// neue Passwort gültig. Beides gehört zusammen: bliebe es dazwischen
  /// stehen, wäre jemand angemeldet, ohne sein Passwort zu kennen. Deshalb
  /// lässt der Router eine Recovery-Sitzung allein nicht in die App
  /// (siehe `lib/core/router.dart`) — erst das geänderte Passwort öffnet
  /// sie.
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.recovery,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Ändert das Passwort einer laufenden Sitzung.
  ///
  /// Der Umweg über eine erneute Anmeldung ist kein Sicherheitstheater,
  /// sondern Pflicht: Im Dashboard ist „Secure password change" aktiv
  /// (gespiegelt in `supabase/config.toml`), und dann lehnt GoTrue ein
  /// `updateUser(password:)` ohne frische Authentifizierung ab. Genau das
  /// ist der Unterschied zum Reset-Flow, dessen Sitzung frisch aus dem
  /// eingelösten Code stammt. Wer den `signInWithPassword`-Schritt hier
  /// wegkürzt, bekommt live einen 403.
  ///
  /// Nebeneffekt mit Absicht: Das falsche aktuelle Passwort scheitert schon
  /// an dieser Anmeldung, das Konto ist also nie einen Moment lang offen für
  /// jemanden, der es nicht kennt.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) {
      throw const AuthException('Keine angemeldete Sitzung.');
    }
    await _client.auth
        .signInWithPassword(email: email, password: currentPassword);
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Die Adresse der laufenden Sitzung — die UI zeigt sie im
  /// „E-Mail ändern"-Dialog an, damit klar ist, WOVON gewechselt wird.
  String? get currentEmail => _client.auth.currentUser?.email;

  /// Stößt den Wechsel der E-Mail-Adresse an.
  ///
  /// Erst die frische Anmeldung mit dem aktuellen Passwort (dasselbe
  /// Muster wie [changePassword] — ein gestohlenes Session-Token allein
  /// darf das Konto nicht umziehen; das falsche Passwort scheitert schon
  /// hier), dann `updateUser(email:)`. GoTrue verschickt daraufhin ZWEI
  /// Mails mit je eigenem Code — an die alte UND die neue Adresse
  /// („Secure email change"). Eingelöst wird mit
  /// [confirmEmailChange]; gemessen gegen echtes GoTrue (PilzBuddy).
  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final email = currentEmail;
    if (email == null) {
      throw const AuthException('Keine angemeldete Sitzung.');
    }
    await _client.auth
        .signInWithPassword(email: email, password: currentPassword);
    await _client.auth.updateUser(UserAttributes(email: newEmail));
  }

  /// Löst EINEN der beiden Wechsel-Codes ein — [email] ist die Adresse,
  /// an deren Postfach der Code ging (alte oder neue).
  ///
  /// Gemessen gegen echtes GoTrue: Der erste Code wird nur
  /// quittiert und ändert nichts; erst der zweite vollzieht den Wechsel
  /// und liefert eine frische Sitzung, die das SDK übernimmt. Der Dialog
  /// löst fest erst den Code der ALTEN, dann den der NEUEN Adresse ein —
  /// exakt der vermessene Weg; eine andere Reihenfolge ist es nicht.
  Future<void> confirmEmailChange({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.emailChange,
    );
  }

  /// Löscht das eigene Konto endgültig — sofort, ohne Karenzzeit.
  ///
  /// Serverseitig genügt eine Zeile: alle Tabellen hängen per
  /// `on delete cascade` an `profiles`, das wiederum an `auth.users`
  /// (siehe `supabase/schema.sql`). Die RPC nimmt
  /// bewusst keine id entgegen — sie löscht immer nur `auth.uid()`.
  ///
  /// Danach lokal abmelden: die Sitzung auf dem Gerät bliebe sonst liegen
  /// und würde bei jedem Request auf einen Nutzer zeigen, den es nicht
  /// mehr gibt.
  Future<void> deleteAccount() async {
    await _client.rpc<void>('delete_own_account');
    await _client.auth.signOut();
  }
}
