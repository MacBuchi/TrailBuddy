// Suchen, Filtern und Sortieren der Trail-Liste (#66), ohne Widgets —
// der Reiter „Trails" zeigt nur, was hier gerechnet wird. Keine eigene
// Abfrage: alles aus `trailsProvider`, also auch ohne Empfang und mit dem
// Ausgangskorb.
//
// **Der Filter gilt für Liste UND Karte** (seit 0.33.0, Betreiber
// 2026-09-29): EIN Provider, EINE Regel ([passesTrailFilter]). Suche und
// Sortierung bleiben in der Liste — wer „Hexentanz" sucht, will ihn
// finden, nicht die Karte leeren. Ein aktiver Filter meldet sich auf der
// Karte (PilzBuddy #154: eine Karte, die still ausblendet, sieht aus, als
// fehlten Trails).
import 'package:flutter/foundation.dart';

import '../../core/search_text.dart';
import '../../models/trail.dart';
import 'trail_condition.dart' show trailConditionLabel;

/// Wessen Trails.
enum TrailOwnerFilter {
  all('Alle'),
  mine('Meine'),
  buddies('Von Buddys');

  const TrailOwnerFilter(this.label);
  final String label;
}

enum TrailSort {
  /// Jüngster Beleg, Beitrag, Hinweis oder Meldung zuerst.
  recent('Zuletzt aktiv'),
  name('Name'),
  length('Länge'),
  descent('Abfahrt (Hm)'),

  /// Leicht zuerst; ohne Einschätzung ans Ende.
  grade('Schwierigkeit'),

  /// Beste Bewertung zuerst (#101, Rework 3.1: „Sortieren nach … in der
  /// eigenen Liste: ja"); ohne Bewertung ans Ende. Nur die Sicht aus
  /// dem eigenen Netz — eine Rangliste darüber hinaus gibt es nie.
  rating('Bewertung');

  const TrailSort(this.label);
  final String label;
}

/// Höchster S-Grad für „bis S2".
const kEasyMaxGrade = 2;

@immutable
class TrailListFilter {
  const TrailListFilter({
    this.owner = TrailOwnerFilter.all,
    this.easyOnly = false,
    this.freshNotesOnly = false,
    this.reportedOnly = false,
    this.ratingOpenOnly = false,
    this.traits = const {},
  });

  final TrailOwnerFilter owner;

  /// „bis S2" — ein Trail OHNE Einschätzung fällt heraus: Der Filter
  /// verspricht „leicht", und über einen Trail, den niemand eingeschätzt
  /// hat, weiß die App das nicht. Im Zweifel die Warnung, wie beim
  /// Median ([Trail.grade]). Wie viele es trifft, sagt die Liste.
  final bool easyOnly;

  /// Nur Trails mit einem neuen Hinweis eines Buddys (#7).
  final bool freshNotesOnly;

  /// Nur gemeldete (gesperrt, zerstört … — [TrailStatus.warns]).
  final bool reportedOnly;

  /// Nur eigene Trails ohne eigene Bewertung (Rework E13) — dieselbe
  /// Regel wie die verblassten Sterne ([Trail.ratingOpen]).
  final bool ratingOpenOnly;

  /// Nur Trails, deren Charakter (#72) ALLE diese Merkmale zeigt — gezählt
  /// wird, was Liste und Blatt zeigen ([Trail.topTraits]), nicht jede
  /// einzelne Nennung: Sonst fände „Flowig" einen Trail, den neun von
  /// zehn Buddys verblockt nennen.
  final Set<TrailTrait> traits;

  bool get isActive =>
      owner != TrailOwnerFilter.all ||
      easyOnly ||
      freshNotesOnly ||
      reportedOnly ||
      ratingOpenOnly ||
      traits.isNotEmpty;

  /// Was gefiltert ist, in Worten — für die Zeile auf der Karte.
  String describe() => [
        if (owner != TrailOwnerFilter.all) owner.label,
        if (easyOnly) 'bis S$kEasyMaxGrade',
        if (freshNotesOnly) 'neuer Hinweis',
        if (reportedOnly) 'gemeldet',
        if (ratingOpenOnly) 'Bewertung offen',
        for (final t in TrailTrait.values)
          if (traits.contains(t)) t.label,
      ].join(' · ');

  TrailListFilter copyWith({
    TrailOwnerFilter? owner,
    bool? easyOnly,
    bool? freshNotesOnly,
    bool? reportedOnly,
    bool? ratingOpenOnly,
    Set<TrailTrait>? traits,
  }) =>
      TrailListFilter(
        owner: owner ?? this.owner,
        easyOnly: easyOnly ?? this.easyOnly,
        freshNotesOnly: freshNotesOnly ?? this.freshNotesOnly,
        reportedOnly: reportedOnly ?? this.reportedOnly,
        ratingOpenOnly: ratingOpenOnly ?? this.ratingOpenOnly,
        traits: traits ?? this.traits,
      );

  @override
  bool operator ==(Object other) =>
      other is TrailListFilter &&
      other.owner == owner &&
      other.easyOnly == easyOnly &&
      other.freshNotesOnly == freshNotesOnly &&
      other.reportedOnly == reportedOnly &&
      other.ratingOpenOnly == ratingOpenOnly &&
      setEquals(other.traits, traits);

  @override
  int get hashCode => Object.hash(owner, easyOnly, freshNotesOnly, reportedOnly,
      ratingOpenOnly, Object.hashAllUnordered(traits));
}

/// Was die Liste zeigt.
typedef TrailListResult = ({
  List<Trail> trails,

  /// Kein Teiltreffer — [trails] sind die nächsten Namen per Tippfehler-
  /// Ausgleich. Die Oberfläche MUSS das sagen („Meintest du …?"): Ein
  /// geratener Treffer, der aussieht wie ein gefundener, ist eine
  /// Behauptung über die Eingabe.
  bool isGuess,

  /// Wie viele „bis S2" nur deshalb verdeckt, weil niemand sie
  /// eingeschätzt hat.
  int hiddenUngraded,
});

/// Die Texte, in denen gesucht wird: der angezeigte Name, die anderen
/// Namen („auch: …") und wer von meinen Buddys ihn beigetragen hat. Kein
/// Hinweistext und keine Beschreibung — dort stünde „Baum liegt quer" als
/// Treffer für „Baum", und die Suche fände Trails über Sätze statt über
/// Namen.
List<String> trailSearchTexts(Trail t) => [
      t.displayName,
      ...t.otherNames,
      for (final d in t.details)
        if (d.userId != t.myId && d.username != null) d.username!,
    ];

/// Wann zuletzt etwas an diesem Trail passiert ist, das ich sehen kann.
DateTime lastActivity(Trail t) {
  var latest = DateTime.fromMillisecondsSinceEpoch(0);
  void take(DateTime? d) {
    if (d != null && d.isAfter(latest)) latest = d;
  }

  for (final r in t.recordings) {
    take(r.createdAt);
  }
  for (final d in t.details) {
    take(d.updatedAt);
  }
  for (final n in t.notes) {
    take(n.createdAt);
  }
  for (final r in t.reports) {
    take(r.reportedAt);
  }
  return latest;
}

/// Lässt [filter] diesen Trail durch? Die EINE Regel für Liste und Karte.
bool passesTrailFilter(Trail t, TrailListFilter filter,
    {Set<String> seenNotes = const {}, DateTime? now}) {
  if (filter.owner == TrailOwnerFilter.mine && !t.isOwn) return false;
  if (filter.owner == TrailOwnerFilter.buddies && t.isOwn) return false;
  if (filter.freshNotesOnly && !t.hasFreshNote(now: now, seen: seenNotes)) return false;
  if (filter.reportedOnly && !t.status.warns) return false;
  if (filter.ratingOpenOnly && !t.ratingOpen) return false;
  if (filter.traits.isNotEmpty && !t.topTraits.toSet().containsAll(filter.traits)) return false;
  if (filter.easyOnly) {
    final g = t.grade;
    if (g == null || g > kEasyMaxGrade) return false;
  }
  return true;
}

/// Fällt [t] NUR deshalb heraus, weil „bis S2" an ist und niemand ihn
/// eingeschätzt hat? Die Liste zählt diese, damit „bis S2" nicht stumm
/// verschluckt, was die App bloß nicht weiß.
bool hiddenOnlyForMissingGrade(Trail t, TrailListFilter filter,
        {Set<String> seenNotes = const {}, DateTime? now}) =>
    filter.easyOnly &&
    t.grade == null &&
    passesTrailFilter(t, filter.copyWith(easyOnly: false), seenNotes: seenNotes, now: now);

/// Filtern, suchen, sortieren — in dieser Reihenfolge. Die Suche läuft
/// über das, was die Filter übrig lassen, damit „Meintest du …?" nie
/// einen Trail vorschlägt, den die Chips gerade ausblenden.
TrailListResult trailListOf(
  List<Trail> trails, {
  String query = '',
  TrailListFilter filter = const TrailListFilter(),
  TrailSort sort = TrailSort.recent,
  Set<String> seenNotes = const {},
  DateTime? now,
}) {
  var hiddenUngraded = 0;
  final candidates = <Trail>[];
  for (final t in trails) {
    if (passesTrailFilter(t, filter, seenNotes: seenNotes, now: now)) {
      candidates.add(t);
    } else if (hiddenOnlyForMissingGrade(t, filter, seenNotes: seenNotes, now: now)) {
      hiddenUngraded++;
    }
  }

  var isGuess = false;
  var found = candidates;
  final needle = foldSearchText(query);
  if (needle.isNotEmpty) {
    found = [
      for (final t in candidates)
        if (trailSearchTexts(t).any((s) => foldSearchText(s).contains(needle))) t,
    ];
    if (found.isEmpty) {
      isGuess = true;
      found = _closest(candidates, needle);
    }
  }
  return (trails: sortTrails(found, sort), isGuess: isGuess, hiddenUngraded: hiddenUngraded);
}

/// Der Tippfehler-Ausgleich: nur der GERINGSTE gefundene Abstand — wer
/// „Roskopf" tippt, will den Roßkopf sehen und nicht dahinter alles, was
/// zufällig auch in die Nähe passt.
List<Trail> _closest(List<Trail> candidates, String needle) {
  final tolerance = searchTypoTolerance(needle.length);
  if (tolerance < 0) return const [];
  final distances = <Trail, int>{};
  for (final t in candidates) {
    for (final s in trailSearchTexts(t)) {
      final d = nearContainsDistance(needle, foldSearchText(s));
      if (d > tolerance) continue;
      final best = distances[t];
      if (best == null || d < best) distances[t] = d;
    }
  }
  if (distances.isEmpty) return const [];
  final closest = distances.values.reduce((a, b) => a < b ? a : b);
  return [
    for (final e in distances.entries)
      if (e.value == closest) e.key,
  ];
}

/// Sortiert; bei Gleichstand nach Name, damit die Liste nicht springt.
List<Trail> sortTrails(List<Trail> trails, TrailSort sort) {
  int byName(Trail a, Trail b) =>
      foldSearchText(a.displayName).compareTo(foldSearchText(b.displayName));
  // Fehlende Werte (keine Höhen, keine Einschätzung) immer ans Ende,
  // gleich in welche Richtung sortiert wird.
  int nullsLast<T extends Comparable<T>>(T? a, T? b, {bool descending = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return descending ? b.compareTo(a) : a.compareTo(b);
  }

  final Comparator<Trail> primary = switch (sort) {
    TrailSort.recent => (a, b) => lastActivity(b).compareTo(lastActivity(a)),
    TrailSort.name => (a, b) => 0,
    TrailSort.length => (a, b) => b.lengthM.compareTo(a.lengthM),
    TrailSort.descent => (a, b) =>
        nullsLast(a.elevation?.lossM, b.elevation?.lossM, descending: true),
    TrailSort.grade => (a, b) => nullsLast(a.grade, b.grade),
    TrailSort.rating => (a, b) => nullsLast(a.rating, b.rating, descending: true),
  };
  return List.of(trails)
    ..sort((a, b) {
      final c = primary(a, b);
      return c != 0 ? c : byName(a, b);
    });
}

/// Welche Art Wort eine Zeile trägt — die Farbe wählt die Oberfläche.
/// [unconfirmed] ist eine Meldung „zu bestätigen" (#101), gedämpft;
/// [condition] der Zustand 1–2 als Wort — ohne eigene Farbe, die gehört
/// der Schwierigkeit (Rework E9).
enum TrailRowTagKind { pending, failure, warning, unconfirmed, note, condition, mine, buddy }

/// Ab diesem Zustand (und schlechter) steht er als Wort in der Liste
/// (Rework E9: „ABGEROCKT", „KAUM FAHRBAR").
const kConditionWordMax = 2;

/// Die Wörter einer Zeile der Liste (Design 1j): rechts vom Farbstreifen
/// sagt ein Wort in der Farbe, was los ist. **Ein Zustand schlägt die
/// Beziehung** — ein wartender, gemeldeter oder neu kommentierter Trail
/// nennt das; nur wenn nichts los ist, steht dort, wem er gehört („MEIN ·
/// 2 BUDDYS", „JAN, MIRA"). Die Beziehung sagt ohnehin schon der Streifen,
/// das Wort gibt sie Bildschirmlesern und allen, die Farben schlecht
/// trennen.
///
/// [nameOf] löst einen Buddy auf (Alias vor Name, `BuddyNames.of`).
List<({String text, TrailRowTagKind kind})> trailRowTags(
  Trail t, {
  required bool freshNote,
  required String Function(String userId, String? username) nameOf,
}) {
  if (t.pending) {
    final failure = t.pendingFailure;
    return [
      failure == null
          ? (text: 'WARTET AUF ÜBERTRAGUNG', kind: TrailRowTagKind.pending)
          // Eine Ablehnung ist ein Satz, kein Etikett — nicht in Versalien.
          : (text: failure, kind: TrailRowTagKind.failure),
    ];
  }
  final unconfirmed = t.shownStatus.unconfirmed?.status;
  final condition = t.shownCondition.confirmed?.condition;
  final tags = <({String text, TrailRowTagKind kind})>[
    if (t.pendingDetails) (text: 'BEITRAG WARTET AUF ÜBERTRAGUNG', kind: TrailRowTagKind.pending),
    if (t.status.warns) (text: t.status.label.toUpperCase(), kind: TrailRowTagKind.warning),
    // Eine jüngere unbestätigte Meldung, die etwas anderes sagt als die
    // bestätigte: gedämpft, mit Fragezeichen („GESPERRT?").
    if (unconfirmed != null && unconfirmed != t.status)
      (text: '${unconfirmed.label.toUpperCase()}?', kind: TrailRowTagKind.unconfirmed),
    if (freshNote) (text: 'NEUER HINWEIS', kind: TrailRowTagKind.note),
    // Der Zustand hinter Meldung und Hinweis, nur wenn er schlecht ist —
    // „Gut" in jeder Zeile wäre Lärm.
    if (condition != null && condition <= kConditionWordMax)
      (text: trailConditionLabel(condition).toUpperCase(), kind: TrailRowTagKind.condition),
  ];
  if (tags.isNotEmpty) return tags;

  final buddies = [
    for (final id in t.buddyIds)
      nameOf(id, t.details.where((d) => d.userId == id && d.username != null).firstOrNull?.username),
  ];
  if (t.isOwn) {
    final n = buddies.length;
    return [
      (
        text: n == 0 ? 'MEIN' : 'MEIN · $n ${n == 1 ? 'BUDDY' : 'BUDDYS'}',
        kind: TrailRowTagKind.mine,
      ),
    ];
  }
  if (buddies.isEmpty) return const [];
  final shown = buddies.take(2).join(', ').toUpperCase();
  return [
    (
      text: buddies.length > 2 ? '$shown +${buddies.length - 2}' : shown,
      kind: TrailRowTagKind.buddy,
    ),
  ];
}
