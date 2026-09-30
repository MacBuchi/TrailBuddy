// Die Kurzanleitung (#131, Plan `docs/konzept-onboarding.md` 3.1; Vorlage
// PilzBuddy #350, Baustein A).
//
// **Warum ein Bildschirm aus Widgets und keine mitgelieferte Textdatei.**
// „Was ist neu" liest `CHANGELOG.md` als Asset, und dieselbe Mechanik
// hätte hier nahegelegen. Sie kann aber genau das nicht, worauf es einer
// Anleitung ankommt: das ECHTE Symbol zeigen. Wer das Schild sucht, sucht
// ein Bild, keine Beschreibung eines Bildes — und dieselben Symbole, die
// hier stehen, stehen auf der Karte. Zweiter Grund: Eine `.md` unter
// `assets/` liegt im Binary, wäre für den Version Guard aber eine
// `*.md`-Datei und damit von der Bump-Pflicht ausgenommen — genau die
// Falle, die CLAUDE.md für `CHANGELOG.md` beschreibt. Und eine
// `web/anleitung.html` gibt es auch nicht (Betreiber, Plan 1.2): zwei
// Stellen zu pflegen, und die PWA IST die App.
//
// **Der Umfang ist die Entscheidung.** Erklärt wird, was man nicht
// erraten kann; alles Übrige findet man beim Benutzen. Sechs Abschnitte
// sind die Obergrenze — eine Anleitung, die man scrollen muss, liest
// niemand zu Ende.
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/widgets/safety_note.dart';
import '../trails/grade_shield.dart';
import '../trails/trail_report.dart' show kReportFieldLabel;

/// Ein Abschnitt der Anleitung: Symbol, Überschrift, ein paar Sätze.
class HelpStep {
  const HelpStep({required this.icon, required this.title, required this.text});

  /// Bewusst ein Widget und kein `IconData`: Das Schild ist gezeichnet,
  /// nicht aus Material entnommen.
  final Widget icon;
  final String title;
  final String text;
}

/// Die Abschnitte der Kurzanleitung.
///
/// **Offen und nicht als lokale `const` in `build`**, damit
/// `help_texts_test.dart` einen EINZELNEN Abschnitt prüfen kann statt die
/// Datei als Text (PilzBuddy: die Prüfung über die ganze Datei war aus
/// dem falschen Grund grün, weil das Wort auch in einem anderen Abschnitt
/// stand).
///
/// Die Texte folgen `konzept-trails.md`: Trail ≠ Fahrt ≠ Aufzeichnung;
/// sichtbar sind eigene Beiträge und die direkter Buddys; Fahrt und
/// Position verlassen das Gerät nie.
const kHelpSteps = <HelpStep>[
  HelpStep(
    icon: _HelpIcon(Icons.file_upload_outlined),
    title: 'Trails importieren',
    text: 'GPX- oder Zip-Dateien aus anderen Apps holst du über das Symbol '
        'oben rechts im Reiter „Trails" oder im Profil unter „Trails '
        'importieren". Eine kurze Spur, die überwiegend bergab führt, wird '
        'ein Trail; eine ganze Runde ist eine Fahrt — die zerlegst du mit der '
        'Schere auf der Karte in Trails. Nur Trails gehen zu deinen Buddys, '
        'nie die ganze Fahrt.',
  ),
  HelpStep(
    icon: GradeShield(2),
    title: 'Die Karte lesen',
    // Farbe = Schwierigkeit (0.42.0), Linienart = Zustand und S4/S5 auf
    // dem Saum (0.51.0) — `docs/design/README.md` Abschnitt 2. Ändert
    // sich dort eine Regel, gehört dieser Satz in denselben PR.
    text: 'Die Farbe einer Linie ist ihre Schwierigkeit, wie auf der Piste: '
        'grün S0, blau S1, rot S2, schwarz ab S3; ein weiß gestrichelter Saum '
        'heißt S4 oder S5, grau noch ohne Einschätzung, Petrol Uphill. Die '
        'Art der Linie ist der Zustand: durchgezogen, bröckelig, gestrichelt, '
        'verblasst — je lückenhafter, desto schlechter. Ein orangener Rand '
        'heißt gemeldet, ein gelber ein neuer Hinweis; Violett gestrichelt '
        'sind offizielle Trails. Am Anfang jedes Trails steht sein Schild — '
        'ein Tipp darauf oder auf die Linie öffnet das Blatt.',
  ),
  HelpStep(
    icon: _HelpIcon(Icons.circle),
    title: 'Fahrt aufzeichnen und zerlegen',
    // Auch in der PWA gezeigt, mit dem Zusatz: Wer die Web-App benutzt,
    // soll wissen, dass es den Weg gibt — nur eben auf dem Telefon.
    text: 'In der Android-App zeichnet der große Knopf unten rechts auf der '
        'Karte eine Fahrt auf — auch ohne Empfang, und sie bleibt auf deinem '
        'Gerät. Unterwegs markierst du mit der Fahne, wo ein Trail beginnt '
        'und endet. Danach zerlegst du die Fahrt: Bekannte Trails erkennt die '
        'App wieder, neue Stücke wählst du selbst. In der Web-App gibt es '
        'keine Aufzeichnung.',
  ),
  HelpStep(
    icon: _HelpIcon(Icons.group_outlined),
    title: 'Buddys und Sichtbarkeit',
    text: 'Du siehst deine Trails und die deiner direkten Buddys — sonst '
        'niemandes, eine öffentliche Karte gibt es nicht. Buddys findest du '
        'im Reiter „Buddys" über den Benutzernamen oder die genaue E-Mail. '
        'Sind zwei Aufzeichnungen derselbe Weg, werden sie EIN Trail, auch '
        'mit zwei Namen. Was du „Nur für mich" stellst, sieht niemand.',
  ),
  HelpStep(
    icon: _HelpIcon(Icons.edit),
    title: 'Dein Beitrag zum Trail',
    // „Meldung" ist die Beschriftung im Melde-Dialog (`kReportFieldLabel`,
    // bis 0.48.0 „Status") — `help_texts_test.dart` hält beide zusammen.
    text: 'Im Blatt eines Trails, den du selbst beigesteuert hast, trägst du unter „Mein '
        'Beitrag" Name, S-Grad, Charakter, Sterne, Sichtbarkeit, Beschreibung '
        'und einen Link ein. „Melden" sagt, was gerade gilt — die '
        '$kReportFieldLabel (gesperrt, zerstört, verändert) und der Zustand; '
        'bestätigt ist sie, wenn du ihn gefahren hast oder vor Ort bist. Ein '
        'Hinweis erzählt Buddys, was los ist, und leuchtet bei ihnen gelb.',
  ),
  HelpStep(
    icon: _HelpIcon(Icons.wifi_off),
    title: 'Ohne Empfang',
    text: 'Deine Trails zeigt die App auch offline, mit dem Stand deines '
        'letzten Abrufs. Was du ohne Netz beisteuerst oder meldest, wartet im '
        'Ausgangskorb und geht los, sobald du wieder Empfang hast. Damit die '
        'Karte etwas zeigt, speicherst du vorher einen Bereich: Ebenen-Knopf '
        'auf der Karte, dann zeichnen; verwalten unter „Meine Bereiche" im '
        'Profil — am besten zu Hause im WLAN.',
  ),
];

/// Zeigt in sechs Schritten, wie TrailBuddy benutzt wird.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kurzanleitung')),
      body: ListView(
        key: const ValueKey('help-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Das Wichtigste in sechs Schritten. Alles andere findest du beim '
            'Ausprobieren.',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppPalette.of(context).muted),
          ),
          const SizedBox(height: 12),
          // Ganz oben und nicht am Ende: Wer die Kurzanleitung öffnet, soll
          // den Hinweis nicht erst finden müssen.
          const SafetyNoteTile(),
          for (final step in kHelpSteps) _StepTile(step: step),
        ],
      ),
    );
  }
}

/// Ein Material-Symbol in der Farbe, die es auf seinem Knopf trägt.
class _HelpIcon extends StatelessWidget {
  const _HelpIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 24, color: AppPalette.of(context).accentText);
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final HelpStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feste Breite statt eines ListTile-`leading`: Das Schild bringt
          // seine eigene Breite mit, und ohne Rahmen stünden die
          // Überschriften unterschiedlich weit eingerückt. `scaleDown`,
          // falls es mit großer Systemschrift breiter wird als der Rahmen.
          SizedBox(
            width: 40,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: step.icon)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(step.text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
