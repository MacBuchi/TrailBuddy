// Die Firebase-Kennung der Web-App (#34; PilzBuddy #277 als Muster).
//
// **Diese Werte sind bewusst öffentlich** — genau wie der
// Supabase-Publishable-Key in `supabase_config.dart`: Sie identifizieren
// das Projekt, sie berechtigen zu nichts. Wer damit etwas anstellen will,
// scheitert an den Regeln auf der Serverseite, nicht an ihrer
// Geheimhaltung.
//
// Android liest seine Entsprechung NICHT hier, sondern nativ aus
// `android/app/google-services.json` — das Google-Services-Gradle-Plugin
// startet die Firebase-App, bevor Dart überhaupt läuft. Deshalb dürfen
// diese Optionen dort nicht ein zweites Mal übergeben werden; siehe
// `push_messaging.dart`.
//
// **Eingerichtet seit 0.37.0**, Firebase-Projekt `trailbuddy-6207b`
// (nur Cloud Messaging): Android über `google-services.json`, das Web
// über die beiden Werte hier. Ein Test hält fest, dass beide Web-Werte
// ZUSAMMEN gesetzt werden — sie kommen aus derselben Konsole, und einer
// allein wäre still nutzlos.
import 'package:firebase_core/firebase_core.dart';

/// Die Web-App des Firebase-Projekts (`null` hieße: kein Web-Push).
///
/// Beim Einsetzen: `FirebaseOptions(apiKey: …, appId: …,
/// messagingSenderId: …, projectId: …, authDomain: …, storageBucket: …)`
/// aus „Projekteinstellungen → Allgemein → Meine Apps → Web-App".
// Bewusst nullbar: `null` ist der Zustand „kein Web-Push", den
// `pushWebConfigured` und der Paar-Test abfragen.
// ignore: unnecessary_nullable_for_final_variable_declarations
const FirebaseOptions? pushFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyCzhgOrg-bk9jE6BFNaAivqiA_aKgiDp7Q',
  appId: '1:906361941288:web:c1bcc179bce77dac45b41d',
  messagingSenderId: '906361941288',
  projectId: 'trailbuddy-6207b',
  authDomain: 'trailbuddy-6207b.firebaseapp.com',
  storageBucket: 'trailbuddy-6207b.firebasestorage.app',
);

/// Der Web-Push-Schlüssel („Web Push certificate", VAPID) aus den
/// Projekteinstellungen → Cloud Messaging (leer hieße: kein Web-Push).
///
/// **Ohne ihn liefert `getToken` im Web nichts** — und zwar still, wie
/// alles an diesem Pfad. Er lässt sich nicht über die CLI erzeugen,
/// sondern nur in der Konsole.
///
/// Bewusst eine KONSTANTE und kein `--dart-define`: Ein vergessener
/// Define beim Web-Build hieße „kein Token", ohne dass irgendwo ein
/// Fehler stünde — genau die Fehlerklasse, gegen die der Rest dieser
/// Ecke geschrieben ist (siehe `webServiceWorkerPath`). Öffentlich ist
/// er ohnehin: Der Browser bekommt ihn bei jeder Registrierung zu sehen.
const pushWebVapidKey =
    'BGoGrN2xQ3OZ_Ht7wgPsreKnEzQQEO-j3laJKVasA5S4oY8ndFyszkQw7hFD8a8LwqyN46fy0W6ZepLF4RZvbkw';

/// Ist der Web-Push eingerichtet? Beide Werte oder keiner.
bool get pushWebConfigured =>
    pushFirebaseOptions != null && pushWebVapidKey.isNotEmpty;
