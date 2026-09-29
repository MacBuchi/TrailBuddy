// Suchen, Filtern und Sortieren der Trail-Liste (#66), ohne Widgets —
// der Reiter „Trails" zeigt nur, was hier gerechnet wird. Keine eigene
// Abfrage: alles aus `trailsProvider`, also auch ohne Empfang und mit dem
// Ausgangskorb.
//
// Die Karte hat keinen Filter bekommen, bewusst (PilzBuddy-Regel aus dem
// Reiter „Spots"): Ein Filter, der an zwei Orten verschieden wirkt, wäre
// schlimmer als zwei getrennte.
import 'package:flutter/foundation.dart';

import '../../core/search_text.dart';
import '../../models/trail.dart';

/// Wessen Trails.
enum TrailOwnerFilter {
  all('Alle'),
  mine('Meine'),
  buddies('Von Buddys');

  const TrailOwnerFilter(this.label);
  final String label;
}

enum TrailSort {
  /// Jüngster Beleg, Beitrag, Hinweis oder Statusmeldung zuerst.
  recent('Zuletzt aktiv'),
  name('Name'),
  length('Länge'),
  descent('Abfahrt (Hm)'),

  /// Leicht zuerst; ohne Einschätzung ans Ende.
  grade('Schwierigkeit');

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

  bool get isActive => owner != TrailOwnerFilter.all || easyOnly || freshNotesOnly || reportedOnly;

  TrailListFilter copyWith({
    TrailOwnerFilter? owner,
    bool? easyOnly,
    bool? freshNotesOnly,
    bool? reportedOnly,
  }) =>
      TrailListFilter(
        owner: owner ?? this.owner,
        easyOnly: easyOnly ?? this.easyOnly,
        freshNotesOnly: freshNotesOnly ?? this.freshNotesOnly,
        reportedOnly: reportedOnly ?? this.reportedOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is TrailListFilter &&
      other.owner == owner &&
      other.easyOnly == easyOnly &&
      other.freshNotesOnly == freshNotesOnly &&
      other.reportedOnly == reportedOnly;

  @override
  int get hashCode => Object.hash(owner, easyOnly, freshNotesOnly, reportedOnly);
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
    take(d.statusAt);
  }
  for (final n in t.notes) {
    take(n.createdAt);
  }
  return latest;
}

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
    if (filter.owner == TrailOwnerFilter.mine && !t.isOwn) continue;
    if (filter.owner == TrailOwnerFilter.buddies && t.isOwn) continue;
    if (filter.freshNotesOnly && !t.hasFreshNote(now: now, seen: seenNotes)) continue;
    if (filter.reportedOnly && !t.status.warns) continue;
    if (filter.easyOnly) {
      final g = t.grade;
      if (g == null) {
        hiddenUngraded++;
        continue;
      }
      if (g > kEasyMaxGrade) continue;
    }
    candidates.add(t);
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
  };
  return List.of(trails)
    ..sort((a, b) {
      final c = primary(a, b);
      return c != 0 ? c : byName(a, b);
    });
}
