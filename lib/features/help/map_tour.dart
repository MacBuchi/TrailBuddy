// Die geführte Tour über die Karte (#132, Plan `docs/konzept-onboarding.md`
// 3.2 und 4.1; Vorlage PilzBuddys `map_tour.dart`, #350/#596).
//
// **Sie erklärt Wege und Zeichen, nicht Knöpfe allein.** PilzBuddys Karte
// ist selbst Inhalt; TrailBuddys ist am Anfang leer. Deshalb zeigt die
// Tour, was auf der Karte steht (Schild, Blatt, die Regeln der Linien),
// dann, was hinter den Knöpfen liegt — und sie FÜHRT VOR: Die
// Werkzeugleiste und das Filter-Blatt gehen auf und wieder zu.
//
// **Sie blockiert nie.** „Überspringen" steht in jedem Schritt, und ein
// Tipp irgendwohin geht weiter. Was sie öffnet, schließt sie wieder, ohne
// dass etwas ausgelöst wird.
//
// Schritttitel dürfen nicht lauten wie etwas auf dem Schirm — ein Test
// fände sonst das Element statt der Blase (PilzBuddy, zweimal passiert).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../coach/coach.dart';
import 'tour_intro_art.dart';
import 'tour_legend.dart';

/// Die Leiste unten — die Karten-Tour nennt ihre Bereiche zum Schluss.
abstract final class NavCoach {
  static const bar = 'nav.bar';
  static const map = 'nav.map';
  static const trails = 'nav.trails';
  static const buddys = 'nav.buddys';
  static const profile = 'nav.profile';

  /// Je Reiter der `AppShell`, in dieser Reihenfolge.
  static const tabs = [map, trails, buddys, profile];
}

/// Die Anker der Karte — eine Stelle für die Kennungen, damit Skript und
/// Widgets dieselben Wörter benutzen.
abstract final class MapCoach {
  /// Die Knopfspalte rechts.
  static const buttons = 'map.buttons';
  static const feedback = 'map.feedback';
  static const layers = 'map.layers';
  static const locate = 'map.locate';

  /// Die Aufnahme — nur, wo man aufzeichnen kann (Android).
  static const record = 'map.record';

  /// Das Schild am Anfang des Trails, dessen Blatt die Tour öffnet.
  static const trailBadge = 'map.trailBadge';

  /// Der leere Kartenzustand — da heißt: kein Trail, kein Blatt.
  static const empty = 'map.empty';

  /// Die Werkzeugleiste „Ebenen" — Anker UND Szene.
  static const rail = 'map.rail';

  /// Ein Knopf der Leiste, je `ValueKey` in `OfflineToolRail`.
  static String railButton(String key) => 'map.rail.$key';
  static const railFilter = 'map.rail.rail-filter';

  /// Szene: das Filter-Blatt, geöffnet AUF der Leiste.
  static const filterSheet = 'map.rail/filter';
  static const filterTrails = 'map.filter.trails';
  static const filterOfficial = 'map.filter.official';
  static const filterPois = 'map.filter.pois';

  /// Szene: das Blatt des Trails, dessen Schild [trailBadge] trägt.
  static const trailSheet = 'map.trailSheet';
}

/// Die Anker im Trail-Blatt. Das Blatt teilt sich die Karte mit der
/// Trails-Tour (#136), deshalb ein eigener Bereich.
abstract final class SheetCoach {
  static const metrics = 'sheet.metrics';
  static const grade = 'sheet.grade';
  static const ownGrade = 'sheet.ownGrade';
  static const contribution = 'sheet.contribution';
  static const addNote = 'sheet.addNote';
  static const report = 'sheet.report';
  static const showOnMap = 'sheet.showOnMap';
}

/// Die Startseite beim ERSTEN Start (#133). Sie nennt die drei Wege, auf
/// denen Trails hierher kommen — die Karte ist am Anfang leer, anders als
/// bei PilzBuddy. „Nicht jetzt" fragt beim nächsten Start wieder.
const kWelcomeIntro = CoachStep(
  title: 'Willkommen bei TrailBuddy',
  text: 'Hier liegen die Trails, die du gefahren bist, und die deiner Buddys '
      '— sonst niemandes. Drei Wege bringen Trails hierher: GPX importieren, '
      'eine Fahrt aufzeichnen, Buddys verbinden.',
  art: welcomeArt,
  startLabel: 'Tour starten',
);

/// Die Startseite, wenn die Karten-Tour aus der Kurzanleitung kommt.
const kMapIntro = CoachStep(
  title: 'Die Karte',
  text: 'Hier liegen deine Trails und die deiner Buddys, jede Linie in der '
      'Farbe ihrer Schwierigkeit. Die Tour zeigt, was die Karte sagt — und was '
      'hinter den Knöpfen liegt.',
  art: mapArt,
);

/// Zum Schluss der Karten-Tour die Bereiche unten, je ein Halbsatz.
const kNavStep = CoachStep(
  title: 'Unten die Bereiche',
  text: 'Trails: alle als Liste, suchen und filtern. Buddys: wer deine '
      'Trails sieht — und du ihre. Profil: Import, Fahrten, Bereiche und die '
      'Kurzanleitung.',
  lit: [NavCoach.bar],
  ring: [NavCoach.trails, NavCoach.buddys, NavCoach.profile],
);

const kMapTourScript = CoachScript(
  id: 'map',
  endLink: ('Kurzanleitung', '/profile/help'),
  steps: [
    kMapIntro,
    CoachStep(
      title: 'Das Schild am Anfang',
      text: 'Am Anfang jedes Trails steht sein Schild mit Grad und Charakter. '
          'Ein Tipp darauf — oder auf die Linie — öffnet das Blatt.',
      lit: [MapCoach.trailBadge],
      gesture: CoachGesture.tap,
      requires: [MapCoach.trailBadge],
    ),
    CoachStep(
      title: 'Das Blatt zum Trail',
      text: 'Länge, Höhenmeter und die Schwierigkeit, wie dein Netz sie sieht '
          '— ein Tipp auf den Grad zeigt, wer wie eingeschätzt hat.',
      scene: MapCoach.trailSheet,
      lit: [SheetCoach.metrics],
      // Ohne Trail kein Blatt. Der Anker im Blatt steht NICHT in
      // `requires` — er entsteht erst mit der Szene dieses Schritts.
      unless: [MapCoach.empty],
    ),
    CoachStep(
      title: 'Farbe heißt Schwierigkeit',
      text: 'Jede Linie trägt die Schwierigkeit ihres Trails wie eine Piste. '
          'Die Art der Linie sagt den Zustand: durchgezogen, bröckelig, '
          'gestrichelt, verblasst. Ein orangener Rand heißt gemeldet, ein '
          'gelber ein neuer Hinweis.',
      // Nichts ausgespart: Die Linien zeichnet die Engine, sie sind keine
      // Widgets. Die Legende steht deshalb in der Blase.
      illustration: TourLegend(),
    ),
    CoachStep(
      title: 'Hinter dem Ebenen-Knopf',
      text: 'Orte wie Einkehr, Wasser und Rad-Service, die offiziellen Trails '
          'der Region — und die Werkzeuge für Karten ohne Empfang.',
      lit: [MapCoach.buttons],
      ring: [MapCoach.layers],
    ),
    CoachStep(
      title: 'Die Werkzeugleiste',
      text: 'Oben der Filter für Orte und offizielle Trails. Darunter '
          'zeichnest du einen Bereich, den die App für unterwegs speichert; '
          '„Meine Bereiche" im Profil verwaltet sie.',
      scene: MapCoach.rail,
      lit: [MapCoach.rail],
      ring: [MapCoach.railFilter],
    ),
    CoachStep(
      title: 'Orte und offizielle Trails wählen',
      text: 'Offizielle Trails an oder aus, Orte nach Gruppe. Was hier aus '
          'ist, bleibt aus, bis du es wieder einschaltest.',
      scene: MapCoach.filterSheet,
      lit: [MapCoach.filterOfficial, MapCoach.filterPois],
    ),
    CoachStep(
      title: 'Zu dir und zu uns',
      text: 'Der Positionsknopf holt die Karte zu dir — dein Standort verlässt '
          'das Gerät nie. Darüber die Glühbirne: Idee oder Fehler melden, das '
          'wird ein öffentlicher Eintrag auf GitHub.',
      lit: [MapCoach.buttons],
      ring: [MapCoach.feedback, MapCoach.locate],
    ),
    CoachStep(
      title: 'Eine Fahrt aufzeichnen',
      text: 'Der große Knopf zeichnet eine Fahrt auf — Haustür bis Haustür, '
          'nur auf deinem Gerät, auch ohne Empfang. Danach zerlegst du sie in '
          'Trails; erst die kommen zu deinen Buddys.',
      lit: [MapCoach.buttons],
      ring: [MapCoach.record],
      // Nur in der Android-App; im Browser fällt der Schritt weg.
      requires: [MapCoach.record],
    ),
    kNavStep,
  ],
);

/// Die Karten-Tour beim ersten Start: mit der Willkommensseite statt der
/// Karten-Startseite und OHNE den Weg in die Kurzanleitung am Ende —
/// `startWelcomeTour` (`tab_tours.dart`) hängt die Reiter-Touren an, und
/// die Kette liefe sonst gleichzeitig in die Kurzanleitung.
final kWelcomeTourScript = CoachScript(
  id: 'map',
  steps: [kWelcomeIntro, ...kMapTourScript.tourSteps],
);

/// Startet die Tour und merkt sich danach, dass sie gesehen wurde —
/// durchgesehen ODER übersprungen: Wer abbricht, hat entschieden.
///
/// Gemerkt wird über den NOTIFIER, nicht über [ref]: Aus der
/// Kurzanleitung gestartet, kann das aufrufende Widget weg sein, bevor
/// die Tour endet — und ein `ref` eines abgebauten Widgets wirft.
void startMapTour(WidgetRef ref) {
  final seen = ref.read(mapTourSeenProvider.notifier);
  ref.read(coachProvider.notifier).start(kMapTourScript, onDone: () => seen.set(true));
}

/// Hat der Nutzer die Karten-Tour schon gesehen? Gerätelokal, Schlüssel
/// `map_tour_seen` ohne Suffix (Reset-Konvention in CLAUDE.md).
final mapTourSeenProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.mapTourSeen,
    write: (s, v) => s.setMapTourSeen(v),
    label: 'Karten-Tour merken',
  ),
);
