// Übernehmen beim ersten Befahren (#102, Rework Abschnitt 1 und 9): Wer
// einen Trail fährt, den er bisher nur über Buddys sieht, macht ihn sich
// mit einer Bewertung zu eigen — ein vollständiger eigener Beitrag,
// vorbelegt aus dem, was er sieht. Danach hängt nichts mehr an einem
// fremden Beitrag: Entfreundet der Buddy oder löscht er seinen, steht
// der Trail weiter mit Namen da.
//
// Rein: Trail rein, Vorbelegung raus. Die Voreinstellung IST die Anzeige
// (Betreiber, 2026-09-30): Name, Median-S-Grad, Charakter und
// Median-Sterne der sichtbaren Beiträge — auf dem Gerät gerechnet, nie
// über alle Nutzer (Konzept 12). Ausnahme Zustand: der jüngste
// bestätigte der letzten 90 Tage, sonst nichts.
import '../../models/trail.dart';

/// Wie lange ein bestätigter Zustand als Vorbelegung taugt.
const kTakeOverConditionDays = 90;

/// Die Vorbelegung eines Beitrags beim Übernehmen.
class TakeOver {
  const TakeOver({
    required this.name,
    this.grade,
    this.traits = const {},
    this.rating,
    this.condition,
  });

  /// Leer, wenn der Trail nirgends einen Namen hat.
  final String name;
  final int? grade;
  final Set<TrailTrait> traits;
  final int? rating;
  final int? condition;
}

/// Muss dieser Trail übernommen werden? Genau dann, wenn es noch keinen
/// eigenen Beitrag gibt (Rework Abschnitt 1: „wer ihn schon beschrieben
/// hat, wird nicht noch einmal gefragt"). Wartende Trails haben keine
/// Server-Kennung und damit nichts, woran ein Beitrag hängen könnte.
bool needsTakeOver(Trail t) => !t.pending && t.myDetails == null;

/// Die Voreinstellung aus dem, was ich sehe.
TakeOver takeOverOf(Trail t, {DateTime? now}) {
  final named = t.details.any((d) => (d.name ?? '').trim().isNotEmpty);
  final c = t.shownCondition.confirmed;
  final since = (now ?? DateTime.now()).subtract(const Duration(days: kTakeOverConditionDays));
  return TakeOver(
    name: named ? t.displayName : '',
    grade: t.grade,
    traits: t.topTraits.toSet(),
    rating: t.rating,
    condition: c != null && c.reportedAt.isAfter(since) ? c.condition : null,
  );
}
