// Das „x" am Kopf eines Blatts (Betreiberwunsch, aus PilzBuddy übernommen).
//
// **Drei Wege hinaus, und keiner davon ist überflüssig.** Ein Blatt
// schließt sich durch Wischen, durch die Zurück-Geste des Systems und
// durch dieses Zeichen. Das sieht nach zweimal dasselbe aus und ist es
// nicht:
//
//   * Die **Wischgeste** kennt, wer Blätter kennt. Sie ist unsichtbar
//     und bleibt es: Der Griffbalken (`showDragHandle: true`) wäre der
//     Hinweis darauf, kostet aber rund 38 px am Kopf jedes Blatts.
//     In PilzBuddy lagen damit zwei Blätter über ihrer Höhengrenze —
//     gemessen, nicht vermutet. Ein sichtbarer Ausweg genügt, und das
//     ist das x.
//   * Die **Zurück-Geste** ist auf Android der Systemweg und auf keinem
//     Bildschirm zu sehen. Im Web gibt es sie als Browser-Zurück, wo sie
//     eher nach „Seite verlassen" aussieht.
//   * Das **x** ist der einzige Weg, der sich selbst erklärt. Genau
//     deshalb steht es da, obwohl die anderen beiden funktionieren.
//
// Die App wird im Gehen bedient, oft mit einer Hand und nassen Fingern.
// Ein Ausweg, den man kennen muss, ist dort keiner.
import 'package:flutter/material.dart';

/// Schließt das Blatt, in dem es steht.
///
/// Gehört an das ENDE der Kopfzeile, hinter einen `Spacer` — links steht
/// der Titel, und ein Knopf davor schöbe ihn aus der Lesespur.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({
    super.key,
    this.tooltip = 'Schließen',
    this.background,
  });

  final String tooltip;

  /// Eine Fläche unter dem Zeichen — für die Bildansicht.
  ///
  /// **Nur dort, und nur weil der Untergrund fremd ist.** Auf einem
  /// Blatt liegt das x auf der Blattfarbe und ist immer zu sehen; auf
  /// einem Foto kann es in einem hellen Himmel verschwinden. Eine
  /// Fläche an jedem x wäre Lärm, eine Fläche auf einem Bild ist die
  /// Bedingung dafür, dass es überhaupt eins gibt.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close),
      tooltip: tooltip,
      style: background == null
          ? null
          : IconButton.styleFrom(backgroundColor: background),
      // **44 bleiben 44.** Dieselbe Trefferfläche wie in der
      // Werkzeugleiste; an der wird nicht gespart, weil die App im Gehen
      // bedient wird.
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      // **`standard`, obwohl `compact` hier naheliegt.** Die Dichte
      // rechnet auf die Grenzen oben drauf, und zwar mit negativem
      // Vorzeichen: `compact` macht aus den 44 genau 36. Im Bild sieht
      // man davon nichts, im Gehen schon — ein Test misst deshalb nach.
      visualDensity: VisualDensity.standard,
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}
