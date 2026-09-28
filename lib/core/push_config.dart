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
// **Noch leer.** Das Firebase-Projekt für TrailBuddy legt der Betreiber
// an (Konsole: Projekt, Android-App `de.mcbuchi.trailbuddy`, Web-App,
// Web-Push-Zertifikat). Bis dahin: Im Web gibt es kein Token und der
// Schalter sagt es; auf Android entscheidet `google-services.json`, das
// der Gradle-Build nur einbindet, wenn die Datei da ist. Ein Test hält
// fest, dass beide Web-Werte ZUSAMMEN gesetzt werden — sie kommen aus
// derselben Konsole, und einer allein wäre still nutzlos.
import 'package:firebase_core/firebase_core.dart';

/// Die Web-App des Firebase-Projekts; `null`, solange es keines gibt.
///
/// Beim Einsetzen: `FirebaseOptions(apiKey: …, appId: …,
/// messagingSenderId: …, projectId: …, authDomain: …, storageBucket: …)`
/// aus „Projekteinstellungen → Allgemein → Meine Apps → Web-App".
const FirebaseOptions? pushFirebaseOptions = null;

/// Der Web-Push-Schlüssel („Web Push certificate", VAPID) aus den
/// Projekteinstellungen → Cloud Messaging; leer, solange es keinen gibt.
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
const pushWebVapidKey = '';

/// Ist der Web-Push eingerichtet? Beide Werte oder keiner.
bool get pushWebConfigured =>
    pushFirebaseOptions != null && pushWebVapidKey.isNotEmpty;
