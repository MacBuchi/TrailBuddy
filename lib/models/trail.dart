import 'dart:convert';

import 'package:latlong2/latlong.dart';

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
    );
  }
}

/// Singletrail-Skala S0–S5, die in DACH übliche Schwierigkeitsangabe.
String gradeLabel(int grade) => 'S$grade';

enum TrailKind {
  natural('natural', 'Naturtrail'),
  flow('flow', 'Flowtrail'),
  tech('tech', 'Technisch'),
  jump('jump', 'Sprungstrecke'),
  connection('connection', 'Verbindung');

  const TrailKind(this.db, this.label);
  final String db;
  final String label;

  static TrailKind? fromDb(String? s) =>
      s == null ? null : values.where((k) => k.db == s).firstOrNull;
}

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
    this.kind,
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
  final TrailKind? kind;
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
      kind: TrailKind.fromDb(json['kind'] as String?),
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
        'kind': kind?.db,
        'visibility': visibility.db,
        'status': status.db,
        'status_at': statusAt?.toUtc().toIso8601String(),
      };

  TrailDetails copyWith({
    String? name,
    String? description,
    int? grade,
    bool clearGrade = false,
    TrailKind? kind,
    bool clearKind = false,
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
        kind: clearKind ? null : (kind ?? this.kind),
        visibility: visibility ?? this.visibility,
        status: status ?? this.status,
        statusAt: statusAt ?? this.statusAt,
        updatedAt: updatedAt,
      );
}

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
  }) : assert(recordings.isNotEmpty, 'ein Trail ohne sichtbaren Beleg');

  final String id;
  final List<TrailRecording> recordings;
  final List<TrailDetails> details;
  final String myId;

  bool get isOwn => recordings.any((r) => r.userId == myId);

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

  /// Median der sichtbaren S-Grade, null ohne Angabe.
  int? get grade {
    final grades = details.map((d) => d.grade).whereType<int>().toList()..sort();
    if (grades.isEmpty) return null;
    return grades[grades.length ~/ 2];
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
}) {
  final byTrail = <String, List<TrailRecording>>{};
  for (final r in recordings) {
    byTrail.putIfAbsent(r.trailId, () => []).add(r);
  }
  final detailsByTrail = <String, List<TrailDetails>>{};
  for (final d in details) {
    detailsByTrail.putIfAbsent(d.trailId, () => []).add(d);
  }
  return [
    for (final e in byTrail.entries)
      Trail(
        id: e.key,
        recordings: e.value,
        details: detailsByTrail[e.key] ?? const [],
        myId: myId,
      ),
  ]..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
}
