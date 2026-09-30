import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../features/trails/trail_elevation.dart';
import '../features/trails/trail_geometry.dart';

/// Ein Beleg: „ich bin das gefahren" (Konzept 3). Die Linie kommt aus
/// der Sicht `recordings_visible` als GeoJSON und wird hier zu Punkten.
class TrailRecording {
  const TrailRecording({
    required this.id,
    required this.trailId,
    required this.userId,
    required this.source,
    required this.recordedAt,
    required this.reversed,
    required this.quality,
    required this.createdAt,
    required this.points,
    required this.lengthM,
    this.ele,
  });

  final String id;
  final String trailId;
  final String userId;
  final RecordingSource source;
  final DateTime? recordedAt;
  final bool reversed;
  final double quality;
  final DateTime createdAt;
  final List<LatLng> points;
  final double lengthM;

  /// Eine Höhe je Punkt, oder null (Datei ohne Höhen, Aufzeichnung vor
  /// Patch 002). Passt die Anzahl nicht zu den Punkten, ist sie ebenfalls
  /// null — eine verschobene Reihe wäre schlimmer als keine.
  final List<double>? ele;

  factory TrailRecording.fromJson(Map<String, dynamic> json) {
    // `st_asgeojson` liefert Text. Je nachdem, ob die Sicht ihn nach json
    // castet, kommt er als String oder als Map — beides wird angenommen,
    // damit eine Spaltenänderung nicht still leere Linien erzeugt.
    final raw = json['geojson'];
    final geo = raw is String
        ? jsonDecode(raw)
        : raw;
    final coords = geo is Map ? geo['coordinates'] : null;
    final points = <LatLng>[];
    if (coords is List) {
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
        }
      }
    }
    final rawEle = json['ele'];
    List<double>? ele;
    if (rawEle is List && rawEle.length == points.length && rawEle.every((e) => e is num)) {
      ele = [for (final e in rawEle) (e as num).toDouble()];
    }
    return TrailRecording(
      id: json['id'] as String,
      trailId: json['trail_id'] as String,
      userId: json['user_id'] as String,
      source: RecordingSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => RecordingSource.import),
      recordedAt: json['recorded_at'] == null
          ? null
          : DateTime.parse(json['recorded_at'] as String).toLocal(),
      reversed: json['reversed'] as bool? ?? false,
      quality: (json['quality'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      points: points,
      lengthM: (json['length_m'] as num?)?.toDouble() ?? 0,
      ele: ele,
    );
  }
}

/// Höchstlänge eines Trail-Namens — dieselbe wie der Check an
/// `trail_details.name` im Schema.
const kTrailNameMaxLength = 80;

/// Ein Name aus einer Datei, so gekürzt, dass der Server ihn annimmt:
/// möglichst an einem Wortende, mit „…". Ohne das scheiterte der ganze
/// Import einer Spur an ihrem Namen, obwohl die Aufzeichnung längst lag.
String clampTrailName(String name) {
  final n = name.trim();
  if (n.length <= kTrailNameMaxLength) return n;
  var cut = n.substring(0, kTrailNameMaxLength - 1);
  final space = cut.lastIndexOf(' ');
  if (space >= kTrailNameMaxLength * 3 ~/ 4) cut = cut.substring(0, space);
  return '${cut.trimRight()}…';
}

/// Singletrail-Skala S0–S5, die in DACH übliche Schwierigkeitsangabe.
String gradeLabel(int grade) => 'S$grade';

/// Der Charakter eines Trails (#72, Patch 009, seit 0.34.0) — MEHRFACHWAHL
/// je Beitrag, ersetzt die frühere Einzelwahl „Art" (`kind`). Die sieben
/// Merkmale hat der Betreiber festgelegt (2026-09-29): die fünf aus dem
/// Design (Turn 4) plus Naturtrail und Verbindung aus der alten Art,
/// damit beim Übernehmen nichts verloren geht. Beschreibungen und
/// Symbole: `trail_traits.dart`. Die Reihenfolge hier ist die Reihenfolge
/// überall (Auswahl, Chips, Gleichstand beim Zählen).
enum TrailTrait {
  flowy('flowy', 'Flowig'),
  jumps('jumps', 'Jump-Line'),
  rocky('rocky', 'Verblockt'),
  steep('steep', 'Steil'),
  uphill('uphill', 'Uphill'),
  natural('natural', 'Naturtrail'),
  connection('connection', 'Verbindung');

  const TrailTrait(this.db, this.label);
  final String db;
  final String label;

  static TrailTrait? fromDb(String? s) =>
      s == null ? null : values.where((k) => k.db == s).firstOrNull;

  /// Die alte „Art" (`kind`) als Merkmal — dieselbe Zuordnung wie im
  /// Patch 009, für Zeilen, die noch keine `traits` tragen (ein alter
  /// Zwischenspeicher, ein wartender Auftrag im Ausgangskorb).
  static TrailTrait? fromLegacyKind(String? kind) => switch (kind) {
        'flow' => flowy,
        'jump' => jumps,
        'tech' => rocky,
        'natural' => natural,
        'connection' => connection,
        _ => null,
      };
}

/// Höchstens so viele Merkmale zeigt ein Trail (Design Turn 4): die
/// häufigsten über alle sichtbaren Beiträge.
const kShownTraits = 2;

enum TrailVisibility {
  buddies('buddies', 'Für Buddys'),
  private('private', 'Nur für mich');

  const TrailVisibility(this.db, this.label);
  final String db;
  final String label;

  static TrailVisibility fromDb(String? s) =>
      values.where((v) => v.db == s).firstOrNull ?? TrailVisibility.buddies;
}

enum TrailStatus {
  open('open', 'Offen'),
  closed('closed', 'Gesperrt'),
  destroyed('destroyed', 'Zerstört'),
  changed('changed', 'Verändert');

  const TrailStatus(this.db, this.label);
  final String db;
  final String label;

  static TrailStatus fromDb(String? s) =>
      values.where((v) => v.db == s).firstOrNull ?? TrailStatus.open;

  bool get warns => this != TrailStatus.open;
}

/// Was ein Nutzer über einen Trail sagt — genau eine Zeile je Nutzer und
/// Trail (Konzept 3). Name, Schwierigkeit und Status sind Eigenschaften
/// des BEITRAGS, nicht des Trails.
class TrailDetails {
  const TrailDetails({
    required this.trailId,
    required this.userId,
    this.username,
    this.name,
    this.description,
    this.grade,
    this.traits = const {},
    this.visibility = TrailVisibility.buddies,
    this.status = TrailStatus.open,
    this.statusAt,
    this.updatedAt,
  });

  final String trailId;
  final String userId;

  /// Aus dem Embed `contributor:profiles(...)`; leer bei der eigenen Zeile,
  /// wenn das Profil nicht mitgeladen wurde.
  final String? username;
  final String? name;
  final String? description;
  final int? grade;

  /// Der Charakter laut DIESEM Beitrag, leer = keine Angabe.
  final Set<TrailTrait> traits;
  final TrailVisibility visibility;
  final TrailStatus status;
  final DateTime? statusAt;
  final DateTime? updatedAt;

  factory TrailDetails.fromJson(Map<String, dynamic> json) {
    final contributor = json['contributor'];
    return TrailDetails(
      trailId: json['trail_id'] as String,
      userId: json['user_id'] as String,
      username: contributor is Map ? contributor['username'] as String? : null,
      name: json['name'] as String?,
      description: json['description'] as String?,
      grade: json['grade'] as int?,
      traits: _traitsFromJson(json),
      visibility: TrailVisibility.fromDb(json['visibility'] as String?),
      status: TrailStatus.fromDb(json['status'] as String?),
      statusAt: json['status_at'] == null
          ? null
          : DateTime.parse(json['status_at'] as String).toLocal(),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toRow() => {
        'trail_id': trailId,
        'user_id': userId,
        'name': name,
        'description': description,
        'grade': grade,
        // `kind` schreibt die App nicht mehr; der Server behält den
        // alten Wert, bis Patch-Folge die Spalte entfernt.
        'traits': [for (final t in TrailTrait.values) if (traits.contains(t)) t.db],
        'visibility': visibility.db,
        'status': status.db,
        'status_at': statusAt?.toUtc().toIso8601String(),
      };

  TrailDetails copyWith({
    String? name,
    String? description,
    int? grade,
    bool clearGrade = false,
    Set<TrailTrait>? traits,
    TrailVisibility? visibility,
    TrailStatus? status,
    DateTime? statusAt,
  }) =>
      TrailDetails(
        trailId: trailId,
        userId: userId,
        username: username,
        name: name ?? this.name,
        description: description ?? this.description,
        grade: clearGrade ? null : (grade ?? this.grade),
        traits: traits ?? this.traits,
        visibility: visibility ?? this.visibility,
        status: status ?? this.status,
        statusAt: statusAt ?? this.statusAt,
        updatedAt: updatedAt,
      );
}

/// `traits` aus einer Zeile; fehlt die Spalte (Zwischenspeicher oder
/// Ausgangskorb von vor 0.34.0), zählt die alte Art.
Set<TrailTrait> _traitsFromJson(Map<String, dynamic> json) {
  final raw = json['traits'];
  if (raw is List) {
    return {for (final v in raw) ?TrailTrait.fromDb(v as String?)};
  }
  final legacy = TrailTrait.fromLegacyKind(json['kind'] as String?);
  return {?legacy};
}

/// Ein Hinweis zu einem Trail für Buddys (Issue #7, Patch 004/005):
/// „Baum liegt quer". Schreiben darf jeder, der den Trail sieht; sehen
/// seine direkten Buddys, die den Trail auch sehen. Kein Bearbeiten — das
/// Alter steht dabei.
class TrailNote {
  const TrailNote({
    required this.id,
    required this.trailId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.username,
  });

  final String id;
  final String trailId;
  final String userId;
  final String body;
  final DateTime createdAt;

  /// Aus dem Embed `author:profiles(...)`.
  final String? username;

  factory TrailNote.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    return TrailNote(
      id: json['id'] as String,
      trailId: json['trail_id'] as String,
      userId: json['user_id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      username: author is Map ? author['username'] as String? : null,
    );
  }
}

/// So lange gilt ein Hinweis eines Buddys als neu: Liste und Karte heben
/// den Trail hervor, bis man ihn im Blatt gesehen hat. Danach steht er
/// nur noch dort, mit seinem Alter.
const kFreshNoteDays = 7;

/// Nach so vielen Tagen verschwindet ein Hinweis — außer dem jüngsten
/// (Entscheidung des Betreibers). Der Server räumt je Autor auf
/// (`sweep_old_notes`), das Blatt zeigt von den alten nur den jüngsten.
const kNoteRetentionDays = 90;

/// Ein Trail, wie ICH ihn sehe: die Kennung plus alle sichtbaren Belege
/// und Beiträge. Alles Angezeigte ist daraus GERECHNET (Konzept 3):
/// beste sichtbare Linie, eigener Name vor dem des ältesten Beitrags,
/// jüngster Status.
class Trail {
  Trail({
    required this.id,
    required this.recordings,
    required this.details,
    required this.myId,
    this.notes = const [],
    this.pending = false,
    this.pendingFailure,
    this.pendingDetails = false,
  }) : assert(recordings.isNotEmpty, 'ein Trail ohne sichtbaren Beleg');

  final String id;
  final List<TrailRecording> recordings;
  final List<TrailDetails> details;
  final String myId;

  /// Wartet im Ausgangskorb (#30): Die Aufzeichnung ist noch nicht auf
  /// dem Server, [id] ist die Kennung des Auftrags. Kein Beitrag, kein
  /// Hinweis, keine Einschätzung — dafür fehlt die Server-Kennung.
  final bool pending;

  /// Der Server hat den Auftrag dauerhaft abgelehnt; der Text ist für den
  /// Nutzer. Nur bei [pending].
  final String? pendingFailure;

  /// Der eigene Beitrag zu diesem (übertragenen) Trail wartet noch im
  /// Korb — die eigene Zeile in [details] ist die wartende Fassung.
  final bool pendingDetails;

  /// Die sichtbaren Hinweise, in beliebiger Reihenfolge — angezeigt über
  /// [notesShown].
  final List<TrailNote> notes;

  bool get isOwn => recordings.any((r) => r.userId == myId);

  /// [userId] hat den Trail nur GEPLANT: Jeder sichtbare Beleg von ihm
  /// ist eine Datei ohne Fahrzeiten (`planned`, Konzept 4.6). Ohne Beleg
  /// von ihm false — dann hat er gar nichts belegt.
  bool onlyPlanned(String userId) {
    final own = recordings.where((r) => r.userId == userId);
    return own.isNotEmpty && own.every((r) => r.source == RecordingSource.planned);
  }

  /// Alle sichtbaren Belege sind geplant — gefahren hat ihn hier
  /// nachweislich niemand.
  bool get allPlanned =>
      recordings.every((r) => r.source == RecordingSource.planned);

  /// Die beste sichtbare Aufzeichnung: höchste Qualität, bei Gleichstand
  /// die ältere (sie hat den Trail „angelegt").
  TrailRecording get best {
    final sorted = List.of(recordings)
      ..sort((a, b) {
        final q = b.quality.compareTo(a.quality);
        return q != 0 ? q : a.createdAt.compareTo(b.createdAt);
      });
    return sorted.first;
  }

  List<LatLng> get points => best.points;
  double get lengthM => best.lengthM;

  /// Die beste sichtbare Aufzeichnung MIT Höhen — nicht unbedingt [best]:
  /// Sonst blieben Trails, deren älteste Aufzeichnung vor Patch 002
  /// entstand, für immer ohne Höhenmeter, auch wenn längst jemand sie mit
  /// Höhen nachgeliefert hat.
  TrailRecording? get elevationRecording {
    final withEle = recordings.where((r) => r.ele != null).toList()
      ..sort((a, b) {
        final q = b.quality.compareTo(a.quality);
        return q != 0 ? q : a.createdAt.compareTo(b.createdAt);
      });
    return withEle.firstOrNull;
  }

  /// Höhenprofil in Trail-Richtung, null ohne Höhen.
  late final ElevationProfile? elevation = () {
    final r = elevationRecording;
    return r == null
        ? null
        : ElevationProfile.of(r.points, r.ele, reversed: r.reversed);
  }();

  TrailDetails? get myDetails =>
      details.where((d) => d.userId == myId).firstOrNull;

  /// Beiträge in der Reihenfolge ihres ersten Belegs — der älteste
  /// Beitragende zuerst. Ohne Beleg (nur Beitrag) hinten.
  List<TrailDetails> get contributionsOrdered {
    DateTime firstRecording(String userId) => recordings
        .where((r) => r.userId == userId)
        .map((r) => r.createdAt)
        .fold<DateTime?>(null, (m, t) => m == null || t.isBefore(m) ? t : m) ??
        DateTime.fromMillisecondsSinceEpoch(1 << 52);
    return List.of(details)
      ..sort((a, b) => firstRecording(a.userId).compareTo(firstRecording(b.userId)));
  }

  /// Eigener Name, sonst der Name des ältesten sichtbaren Beitrags; die
  /// anderen als „auch: …" (Konzept 3, Muster Buddy-Alias).
  String get displayName {
    final own = myDetails?.name;
    if (own != null && own.trim().isNotEmpty) return own;
    for (final d in contributionsOrdered) {
      final n = d.name;
      if (n != null && n.trim().isNotEmpty) return n;
    }
    return 'Trail ohne Namen';
  }

  List<String> get otherNames {
    final shown = displayName;
    final names = <String>{};
    for (final d in details) {
      final n = d.name?.trim();
      if (n != null && n.isNotEmpty && n != shown) names.add(n);
    }
    return names.toList();
  }

  /// Die sichtbaren Einschätzungen, älteste Beiträge zuerst — „wer hat
  /// was gesagt" im Blatt.
  List<TrailDetails> get gradeVotes =>
      contributionsOrdered.where((d) => d.grade != null).toList();

  /// Leichteste und schwerste sichtbare Einschätzung (Konzept 3: „Median
  /// … mit Spanne"), null ohne Angabe.
  ({int min, int max})? get gradeRange {
    final grades = details.map((d) => d.grade).whereType<int>();
    if (grades.isEmpty) return null;
    return (
      min: grades.reduce((a, b) => a < b ? a : b),
      max: grades.reduce((a, b) => a > b ? a : b),
    );
  }

  /// Median der sichtbaren S-Grade, null ohne Angabe. Bei gerader Anzahl
  /// der SCHWERERE der beiden mittleren: Im Zweifel gewinnt die Warnung —
  /// wer einen S3 für S2 hält, liegt teurer daneben als umgekehrt.
  int? get grade {
    final grades = details.map((d) => d.grade).whereType<int>().toList()..sort();
    if (grades.isEmpty) return null;
    return grades[grades.length ~/ 2];
  }

  /// Wie viele sichtbare Beiträge welches Merkmal nennen (#72) — wie der
  /// Grad von Buddys vergeben, je Beitrag höchstens einmal.
  Map<TrailTrait, int> get traitCounts {
    final counts = <TrailTrait, int>{};
    for (final d in details) {
      for (final t in d.traits) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Die höchstens [kShownTraits] häufigsten Merkmale — das, was Liste,
  /// Blatt und Filter „der Charakter" nennen. Gleichstand: die
  /// Reihenfolge von [TrailTrait].
  List<TrailTrait> get topTraits {
    final counts = traitCounts;
    final sorted = counts.keys.toList()
      ..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.index.compareTo(b.index);
      });
    return sorted.take(kShownTraits).toList();
  }

  /// Die jüngste Statusmeldung gewinnt (Entscheidung 6); ohne Datum
  /// zählt eine Meldung als älter als jede datierte.
  TrailDetails? get latestStatus {
    TrailDetails? latest;
    for (final d in details) {
      if (latest == null) {
        latest = d;
        continue;
      }
      final a = d.statusAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final b = latest.statusAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (a.isAfter(b)) latest = d;
    }
    return latest;
  }

  TrailStatus get status => latestStatus?.status ?? TrailStatus.open;

  /// Was das Blatt zeigt, neueste zuerst: alles aus den letzten
  /// [kNoteRetentionDays] Tagen, und immer den jüngsten — der bleibt
  /// stehen, bis ihn jemand entfernt.
  List<TrailNote> notesShown({DateTime? now}) {
    final sorted = List.of(notes)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final since = (now ?? DateTime.now())
        .subtract(const Duration(days: kNoteRetentionDays));
    return [
      for (var i = 0; i < sorted.length; i++)
        if (i == 0 || sorted[i].createdAt.isAfter(since)) sorted[i],
    ];
  }

  /// Ein Buddy hat in den letzten [kFreshNoteDays] Tagen etwas dazu
  /// geschrieben, das auf diesem Gerät noch nicht im Blatt zu sehen war
  /// ([seen]). Eigene Hinweise zählen nicht — die sind nichts Neues.
  bool hasFreshNote({DateTime? now, Set<String> seen = const {}}) =>
      notes.any((n) => isFreshNote(n, now: now, seen: seen));

  bool isFreshNote(TrailNote n, {DateTime? now, Set<String> seen = const {}}) {
    final since =
        (now ?? DateTime.now()).subtract(const Duration(days: kFreshNoteDays));
    return n.userId != myId && n.createdAt.isAfter(since) && !seen.contains(n.id);
  }

  /// Wer den Trail belegt hat, ohne mich — für „3 Buddys kennen ihn".
  Set<String> get buddyIds =>
      {for (final r in recordings) if (r.userId != myId) r.userId};
}

/// Gruppiert die beiden Abfragen zu Trails. Beiträge ohne sichtbaren
/// Beleg fallen weg: Sichtbar ist, was jemand GEFAHREN ist (Konzept 6),
/// nicht, worüber jemand etwas gesagt hat.
List<Trail> buildTrails({
  required List<TrailRecording> recordings,
  required List<TrailDetails> details,
  required String myId,
  List<TrailNote> notes = const [],
}) {
  final byTrail = <String, List<TrailRecording>>{};
  for (final r in recordings) {
    byTrail.putIfAbsent(r.trailId, () => []).add(r);
  }
  final detailsByTrail = <String, List<TrailDetails>>{};
  for (final d in details) {
    detailsByTrail.putIfAbsent(d.trailId, () => []).add(d);
  }
  final notesByTrail = <String, List<TrailNote>>{};
  for (final n in notes) {
    notesByTrail.putIfAbsent(n.trailId, () => []).add(n);
  }
  return [
    for (final e in byTrail.entries)
      Trail(
        id: e.key,
        recordings: e.value,
        details: detailsByTrail[e.key] ?? const [],
        myId: myId,
        notes: notesByTrail[e.key] ?? const [],
      ),
  ]..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
}
