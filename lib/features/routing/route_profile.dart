// Das Fahrerprofil und die Wegklassen der Routing-Engine
// (docs/konzept-routing.md 2.1–2.4): zwei Profile — Bio-Bike und E-Bike
// — mit je eigenen Steigraten, Geschwindigkeiten, Aufschlägen und
// Budget-Vorgabe; je Wegklasse Aufschlag bergauf/bergab und ob sie als
// Wanderweg zählt; die Zeit einer Kante nach Munter-Muster (Strecke
// plus Höhe) und ihre Kosten (Zeit × Aufschlag).
//
// Zahl für Zahl der Spiegel von `PROFILES`, `CLASSES`, `classify`,
// `edge_time_s`, `edge_factor` und `edge_cost_s` in
// `tool/route_measure.py` — das Werkzeug ist die Referenz, mit der die
// Engine gemessen wurde (docs/routing-messung.md), und
// `test/routing/route_profile_test.dart` hält die Zahlen beider Seiten
// zusammen. Wer hier eine Zahl ändert, ändert sie dort im selben PR.
//
// Rein: keine Widgets, kein Riverpod, keine Platte.

/// Die Zahlen, mit denen das Zeitmodell rechnet — das Profil mit seinen
/// Vorgaben ([RiderProfile]) oder das Profil mit gelernten Werten
/// (`CalibratedRider`, Schritt 6). Die Engine fragt nur diese Schnitt-
/// stelle; welches Profil dahintersteht, sagt [profile].
abstract interface class RiderParams {
  RiderProfile get profile;
  double get climbTrackMPerH;
  double get climbPathMPerH;
  double get pushRateMPerH;
  double get vFlatKmh;
  double get vPathUpKmh;
  double get vPushKmh;
  double get vDownKmh;
  double get pathUpFactor;
  double get pathDownFactor;
  double get budgetClimbM;
}

/// Bio-Bike oder E-Bike (Konzept-Routing 2.1). Das Profil ändert drei
/// Dinge und sonst nichts: Steigraten, Aufschlag Wanderweg bergauf,
/// Budget-Vorgabe. Wegerechte und die Trail-Seite bleiben gleich.
enum RiderProfile implements RiderParams {
  bio(
    label: 'Bio-Bike',
    climbTrackMPerH: 450,
    climbPathMPerH: 350,
    pushRateMPerH: 300,
    vFlatKmh: 15,
    vPathUpKmh: 8,
    vPushKmh: 3,
    vDownKmh: 25,
    pathUpFactor: 1.4,
    pathDownFactor: 2.0,
    budgetClimbM: 800,
  ),
  ebike(
    label: 'E-Bike',
    climbTrackMPerH: 850,
    climbPathMPerH: 650,
    pushRateMPerH: 220,
    vFlatKmh: 20,
    vPathUpKmh: 10,
    vPushKmh: 2.5,
    vDownKmh: 25,
    pathUpFactor: 2.0,
    pathDownFactor: 2.5,
    budgetClimbM: 1400,
  );

  const RiderProfile({
    required this.label,
    required this.climbTrackMPerH,
    required this.climbPathMPerH,
    required this.pushRateMPerH,
    required this.vFlatKmh,
    required this.vPathUpKmh,
    required this.vPushKmh,
    required this.vDownKmh,
    required this.pathUpFactor,
    required this.pathDownFactor,
    required this.budgetClimbM,
  });

  final String label;

  @override
  RiderProfile get profile => this;

  /// Steigrate auf Forstweg und Straße, auf Pfaden (fahrend) und beim
  /// Schieben (Steig, Stufen), in Höhenmetern je Stunde.
  @override
  final double climbTrackMPerH;
  @override
  final double climbPathMPerH;
  @override
  final double pushRateMPerH;

  /// Geschwindigkeiten: flach auf Forstweg/Straße, Pfad bergauf
  /// (fahrend), schiebend, Straße/Forstweg bergab.
  @override
  final double vFlatKmh;
  @override
  final double vPathUpKmh;
  @override
  final double vPushKmh;
  @override
  final double vDownKmh;

  /// Aufschlag Wanderweg bergauf und bergab.
  @override
  final double pathUpFactor;
  @override
  final double pathDownFactor;

  /// Vorgabe „höchstens Höhenmeter bergauf" (Konzept-Routing 2.3).
  @override
  final double budgetClimbM;

  /// Der gespeicherte Name (`Settings.riderProfile`); unbekannt ⇒ Bio.
  static RiderProfile parse(String? name) =>
      values.where((p) => p.name == name).firstOrNull ?? RiderProfile.bio;
}

/// Vorgabe „höchstens Zeit" und „höchstens Wanderweg" (Konzept-Routing
/// 2.3) — für beide Profile gleich.
const kBudgetHours = 3.0;
const kBudgetHikingKm = 2.0;

/// Abfahrt auf einem Trail nach S-Grad (Median, wie das Schild), km/h;
/// ohne Einschätzung 10 km/h. Für beide Profile gleich: Bergab ist ein
/// S2 ein S2.
double trailDownKmh(int? grade) => switch (grade) {
      0 => 16,
      1 => 12,
      2 => 9,
      3 => 6,
      4 || 5 => 4,
      _ => 10,
    };

/// Die Wegklassen (Konzept-Routing 2.4): Aufschlag bergauf/bergab, ob
/// die Klasse als Wanderweg zählt (Regler „höchstens Wanderweg"), und
/// welche Geschwindigkeit und Steigrate des Profils sie nimmt. Ein
/// Aufschlag `null` heißt: der des Profils (`pathUpFactor`/`pathDownFactor`).
enum WayClass {
  forstweg('Forstweg', up: 1.0, down: 1.0),
  radweg('Radweg', up: 1.0, down: 1.0),
  nebenstrasse('Nebenstraße', up: 1.2, down: 1.2),
  zufahrt('Zufahrt', up: 1.2, down: 1.2),
  wanderweg('Wanderweg', up: null, down: null, hiking: true, pathSpeed: true, pathRate: true),
  fussweg('Fußweg', up: 2.0, down: 2.5, hiking: true, pathSpeed: true, pathRate: true),
  stufen('Stufen', up: 3.0, down: 3.0, hiking: true, pushing: true),
  landstrasse('Landstraße', up: 1.6, down: 1.6),
  hauptstrasse('Hauptstraße', up: 2.5, down: 2.5),
  bundesstrasse('Bundesstraße', up: 4.0, down: 4.0);

  const WayClass(this.label,
      {required this.up,
      required this.down,
      this.hiking = false,
      this.pathSpeed = false,
      this.pathRate = false,
      this.pushing = false});

  final String label;
  final double? up;
  final double? down;

  /// Zählt gegen „höchstens Wanderweg", in beide Richtungen.
  final bool hiking;

  /// Nimmt bergauf die Pfad-Geschwindigkeit und -Steigrate.
  final bool pathSpeed;
  final bool pathRate;

  /// Wird geschoben (Steig, Stufen): Schiebe-Tempo und -Rate.
  final bool pushing;

  /// Straßenklassen: Nur hier gilt `oneway` — Forstwege und Pfade sind
  /// in beide Richtungen befahrbar.
  bool get isRoad => switch (this) {
        nebenstrasse || zufahrt || landstrasse || hauptstrasse || bundesstrasse => true,
        _ => false,
      };

  double upFactor(RiderParams p) => up ?? p.pathUpFactor;
  double downFactor(RiderParams p) => down ?? p.pathDownFactor;
}

/// Die Klasse eines `roads`-Features der Kacheln, oder null, wenn die
/// Engine es nicht benutzen darf: Autobahn und Schnellstraße (`highway`),
/// Schienen, Fähren, `other` (Rennstrecken, Pisten), Privatzufahrten,
/// `access` private/no. `primary_link` zählt als Bundesstraße.
WayClass? classifyWay({
  required String? kind,
  required String? kindDetail,
  String? access,
  String? service,
}) {
  if (access == 'private' || access == 'no') return null;
  switch (kind) {
    case 'major_road':
      return (kindDetail ?? '').startsWith('primary') ? WayClass.bundesstrasse : WayClass.hauptstrasse;
    case 'medium_road':
      return WayClass.landstrasse;
    case 'minor_road':
      if (kindDetail == 'service') {
        return service == 'driveway' || service == 'parking_aisle' ? null : WayClass.zufahrt;
      }
      return WayClass.nebenstrasse;
    case 'path':
      return switch (kindDetail) {
        'track' => WayClass.forstweg,
        'cycleway' => WayClass.radweg,
        'path' || 'bridleway' => WayClass.wanderweg,
        'footway' || 'pedestrian' => WayClass.fussweg,
        'steps' => WayClass.stufen,
        _ => null,
      };
    default:
      return null;
  }
}

/// Die Zeit einer Wegekante in Sekunden (Konzept-Routing 2.2):
/// Strecke / v(Klasse, Richtung) + Anstieg / Steigrate(Profil, Klasse).
/// Bergab (mehr Verlust als Gewinn) zählt nur die Strecke — mit der
/// Abfahrtsgeschwindigkeit, auf einem Wanderweg wie auf einem Trail ohne
/// Einschätzung, auf Stufen schiebend.
double edgeTimeS(RiderParams p, WayClass cls,
    {required double lengthM, required double gainM, required double lossM}) {
  final downhill = lossM > gainM;
  final double vKmh;
  if (cls.pushing) {
    vKmh = p.vPushKmh;
  } else if (downhill) {
    vKmh = cls == WayClass.wanderweg
        ? trailDownKmh(null)
        : cls.hiking
            ? p.vPathUpKmh
            : p.vDownKmh;
  } else {
    vKmh = cls.pathSpeed ? p.vPathUpKmh : p.vFlatKmh;
  }
  final rate = cls.pushing
      ? p.pushRateMPerH
      : cls.pathRate
          ? p.climbPathMPerH
          : p.climbTrackMPerH;
  return lengthM / (vKmh / 3.6) + gainM / (rate / 3600.0);
}

/// Die Zeit auf einem Trail bergab, nach S-Grad.
double trailTimeS({required double lengthM, required int? grade}) =>
    lengthM / (trailDownKmh(grade) / 3.6);

/// Der Aufschlag der Kante — bergab der Abstiegs-, sonst der
/// Anstiegsaufschlag.
double edgeFactor(RiderParams p, WayClass cls, {required double gainM, required double lossM}) =>
    lossM > gainM ? cls.downFactor(p) : cls.upFactor(p);

/// Kosten = Zeit × Aufschlag (Konzept-Routing 2.4): Der Aufschlag sagt,
/// was die Zeit nicht sagt — eine Bundesstraße ist nicht langsam, sie
/// ist falsch.
double edgeCostS(RiderParams p, WayClass cls,
        {required double lengthM, required double gainM, required double lossM}) =>
    edgeTimeS(p, cls, lengthM: lengthM, gainM: gainM, lossM: lossM) *
    edgeFactor(p, cls, gainM: gainM, lossM: lossM);
