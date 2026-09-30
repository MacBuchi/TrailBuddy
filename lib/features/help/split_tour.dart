// Die Tour im Zerlege-Blatt (#134, Plan `docs/konzept-onboarding.md` 3.4
// und 4.4) — auf derselben Hinweis-Maschine wie die Karten-Tour.
//
// **Warum hier und nicht im Profil.** Das Zerlege-Blatt nach der ersten
// Aufzeichnung ist der Moment, in dem man Hilfe braucht: bekannte Trails,
// Kandidaten mit Griffen, eine Übernahme, eine Nachfrage — alles auf einem
// Blatt, und nichts davon kann man erraten. Deshalb startet sie EINMAL,
// und nur nach einer eigenen Aufzeichnung (`SplitRequest.rideId`), nie aus
// dem GPX-Import.
//
// **Jede Fahrt sieht anders aus**, also hängt fast jeder Schritt an
// `requires`: ohne bekannten Trail kein „Schon bekannt", ohne Wege statt
// der Kandidaten der Ersatzschritt „Erst einen Bereich speichern". Damit
// `requires` die Zeilen weiter unten überhaupt SIEHT, baut das Blatt
// seine faule Liste während dieser Tour ganz (`cacheExtent`); die
// Maschine scrollt das Ziel dann selbst ins Bild.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../coach/coach.dart';
import 'seen_tours.dart';
import 'tour_intro_art.dart';

/// Die Anker im Zerlege-Blatt.
abstract final class SplitCoach {
  /// Die erste bekannte Zeile („wieder gefahren").
  static const known = 'split.known';

  /// Die aufgeklappte Übernahme der ersten Zeile, die ich zum ersten Mal
  /// fahre (#127).
  static const takeOver = 'split.takeover';

  /// Die erste Nachfrage zu einer unbestätigten Meldung (#124).
  static const question = 'split.question';

  /// Der erste Kandidat, seine Griffe und sein Heimzonen-Hinweis.
  static const candidate = 'split.candidate';
  static const range = 'split.range';
  static const home = 'split.home';

  /// „Die Wege kennt die App hier nicht" — ohne gespeicherten Bereich.
  static const noRoads = 'split.noRoads';

  /// „Stück selbst wählen".
  static const pick = 'split.pick';

  /// Der Knopf unten: „n beisteuern" / „Behalten".
  static const submit = 'split.submit';
}

const kSplitIntro = CoachStep(
  title: 'Deine erste Fahrt zerlegen',
  text: 'Aus der Fahrt werden Trails: Bekannte erkennt die App wieder, neue '
      'schlägt sie dir vor. Zu deinen Buddys gehen nur die Stücke, die du '
      'wählst — nie die ganze Fahrt.',
  art: splitArt,
);

/// Titel nie wie ein Text im Blatt („Wieder gefahren", „Stück selbst
/// wählen", „Übernehmen" stehen dort) — der Test fände sonst das Element
/// statt der Blase.
const kSplitTourScript = CoachScript(
  id: 'split',
  steps: [
    kSplitIntro,
    CoachStep(
      title: 'Schon bekannt',
      text: 'Trails, die du oder deine Buddys schon haben, erkennt die App an '
          'der Linie. Sie sind vorangehakt und gehen als Beleg hinaus — das hält '
          'den Trail aktuell.',
      lit: [SplitCoach.known],
      requires: [SplitCoach.known],
    ),
    CoachStep(
      title: 'Jetzt deiner',
      text: 'Einen Trail deiner Buddys fährst du zum ersten Mal: Name, Grad und '
          'Charakter sind aus dem Netz vorbelegt. Mit deinen Sternen wird er '
          'deiner — ohne Bewertung geht das Stück nicht hinaus.',
      lit: [SplitCoach.takeOver],
      requires: [SplitCoach.takeOver],
    ),
    CoachStep(
      title: 'Gilt das noch?',
      text: 'Zu diesem Trail ist etwas gemeldet, das noch niemand bestätigt hat. '
          'Du warst gerade dort — ein Tipp beantwortet es, mit der Zeit deiner '
          'Fahrt.',
      lit: [SplitCoach.question],
      requires: [SplitCoach.question],
    ),
    CoachStep(
      title: 'Ein Kandidat',
      text: 'Ein Stück, das ein neuer Trail sein könnte: Gefälle abseits der '
          'Wege oder unterwegs markiert. Mit den Griffen setzt du Anfang und '
          'Ende, die Karte zeigt es mit; Name, Grad und Charakter trägst du '
          'gleich hier ein.',
      // Nur die Griffe, nicht die ganze Karte des Kandidaten: Die ist mit
      // Grad und Charakter so hoch, dass auf einem kleinen Schirm keine
      // Blase mehr daneben passt (360×740 im Test).
      lit: [SplitCoach.range],
      requires: [SplitCoach.candidate],
    ),
    CoachStep(
      title: 'Nahe an zu Hause',
      text: 'Beginnt oder endet ein Stück nahe Start oder Ziel deiner Fahrt, sagt '
          'die App es — eine Fahrt beginnt oft an der Haustür, und ein Trail soll '
          'sie nicht verraten. Schieb den Griff weg, wenn es nötig ist.',
      lit: [SplitCoach.home],
      requires: [SplitCoach.home],
    ),
    CoachStep(
      title: 'Erst einen Bereich speichern',
      text: 'Neue Stücke findet die App nur, wo sie die Wege kennt — aus einem '
          'gespeicherten Bereich. Speichere einen über der Fahrt (Ebenen-Knopf '
          'auf der Karte) und zerlege sie dann noch einmal aus „Meine Fahrten".',
      lit: [SplitCoach.noRoads],
      requires: [SplitCoach.noRoads],
    ),
    CoachStep(
      title: 'Was die Suche nicht findet',
      text: 'Eine Jump-Line, ein flacher Flowtrail? Damit legst du einen '
          'Kandidaten über die ganze Fahrt; die Griffe machen den Rest.',
      lit: [SplitCoach.pick],
      requires: [SplitCoach.pick],
    ),
    CoachStep(
      title: 'Was zu Buddys geht',
      text: 'Nur die angehakten Stücke gehen hinaus, als Trails zu deinen Buddys. '
          'Die Fahrt selbst bleibt auf deinem Gerät, unter „Meine Fahrten".',
      lit: [SplitCoach.submit],
    ),
  ],
);

/// Eine ausdrücklich gewünschte Zerlege-Tour (aus der Kurzanleitung): Sie
/// läuft beim nächsten Öffnen des Blatts, auch wenn sie gesehen ist.
final requestedSplitTourProvider = StateProvider<bool>((ref) => false);

/// Startet die Tour. Durchgesehen oder übersprungen ⇒ gesehen; „Nicht
/// jetzt" ist kein Gesehen — beim nächsten Blatt nach einer Fahrt fragt
/// sie wieder.
void startSplitTour(WidgetRef ref) {
  final seen = ref.read(seenCoachToursProvider.notifier);
  ref.read(coachProvider.notifier).start(kSplitTourScript, onDone: () => seen.markSeen(kSplitTourScript.id));
}
