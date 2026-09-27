import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/errors.dart';
import '../../core/settings.dart';
import 'poi.dart';

/// Woher die Orte kommen. Eine Schnittstelle, damit Tests ein Fake
/// einhängen — kein Netz in Tests.
abstract interface class PoiSource {
  Future<List<Poi>> fetch(
      ({double s, double w, double n, double e}) box, Set<PoiGroup> groups);
}

/// Die öffentliche Overpass-Instanz des FOSSGIS e.V. — neues Netzziel,
/// steht in der Datenschutzerklärung. Übertragen werden nur Rahmen und
/// Kategorien, nie Trails, Fahrten oder das Konto.
class OverpassPoiSource implements PoiSource {
  OverpassPoiSource([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;

  static final _endpoint = Uri.parse('https://overpass-api.de/api/interpreter');

  @override
  Future<List<Poi>> fetch(({double s, double w, double n, double e}) box,
      Set<PoiGroup> groups) async {
    final res = await _client.post(
      _endpoint,
      // Formular statt JSON: Im Web bleibt das eine „einfache" Anfrage
      // ohne CORS-Vorabprüfung. Aus demselben Grund im Web kein eigener
      // User-Agent — den setzt dort ohnehin der Browser.
      headers: kIsWeb ? null : const {'User-Agent': 'TrailBuddy (de.mcbuchi.trailbuddy)'},
      body: {'data': overpassQuery(box, groups)},
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw PoiUnavailable(res.statusCode);
    return parseOverpass(res.body);
  }
}

/// Overpass hat gerade keine Antwort (429 bei zu vielen Anfragen, 504 bei
/// Überlast). Kein Fehler der App — die Karte sagt es und fragt beim
/// nächsten Verschieben wieder.
class PoiUnavailable implements Exception {
  const PoiUnavailable(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Overpass antwortet mit $statusCode';
}

final poiSourceProvider = Provider<PoiSource>((ref) => OverpassPoiSource());

/// Die eingeschalteten Gruppen — gerätelokal gemerkt, wie
/// [RememberedFlag]: Der Zustand springt sofort, das Merken läuft nach.
class PoiGroupsNotifier extends Notifier<Set<PoiGroup>> {
  @override
  Set<PoiGroup> build() {
    final saved = ref.read(settingsProvider).poiGroups;
    if (saved == null) return PoiGroup.initial;
    return {
      for (final name in saved)
        ...PoiGroup.values.where((g) => g.name == name),
    };
  }

  void toggle(PoiGroup group) {
    final next = {...state};
    if (!next.remove(group)) next.add(group);
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setPoiGroups([for (final g in PoiGroup.values) if (next.contains(g)) g.name])
        .catchError((Object e, StackTrace s) => logError('Orte-Filter merken', e, s)));
  }
}

final poiGroupsProvider =
    NotifierProvider<PoiGroupsNotifier, Set<PoiGroup>>(PoiGroupsNotifier.new);

/// Was geladen ist, je Rasterzelle und Gruppe.
@immutable
class PoiState {
  const PoiState({this.byCell = const {}, this.unavailable = false});

  final Map<PoiCell, Map<PoiGroup, List<Poi>>> byCell;

  /// Die letzte Abfrage kam nicht durch.
  final bool unavailable;

  /// Die Orte der [groups] in den [cells].
  List<Poi> inCells(Iterable<PoiCell> cells, Set<PoiGroup> groups) => [
        for (final c in cells)
          for (final g in groups) ...?byCell[c]?[g],
      ];
}

/// Lädt fehlende Zellen nach und merkt sich, was schon da ist — für die
/// Laufzeit der App, nicht auf dem Gerät. Eine Zelle je Gruppe wird genau
/// einmal gefragt; wer zurückschwenkt, fragt nicht erneut.
class PoiController extends Notifier<PoiState> {
  bool _busy = false;
  ({List<PoiCell> cells, Set<PoiGroup> groups})? _queued;

  /// Merkt sich so viele Zellen, danach wird vergessen, was nicht gerade
  /// gebraucht wird (ein langer Tag Kartenschieben quer durch die Alpen).
  static const _maxCells = 400;

  @override
  PoiState build() => const PoiState();

  /// Sorgt dafür, dass [cells] für [groups] geladen sind. Läuft schon
  /// eine Abfrage, wird nur der jüngste Wunsch vorgemerkt.
  Future<void> ensure(List<PoiCell> cells, Set<PoiGroup> groups) async {
    if (_busy) {
      _queued = (cells: cells, groups: groups);
      return;
    }
    _busy = true;
    try {
      await _load(cells, groups);
      while (_queued != null) {
        final q = _queued!;
        _queued = null;
        await _load(q.cells, q.groups);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _load(List<PoiCell> cells, Set<PoiGroup> groups) async {
    if (cells.isEmpty || cells.length > kPoiMaxCells) return;
    final missingCells = <PoiCell>{};
    final missingGroups = <PoiGroup>{};
    for (final c in cells) {
      for (final g in groups) {
        if (state.byCell[c]?[g] == null) {
          missingCells.add(c);
          missingGroups.add(g);
        }
      }
    }
    if (missingCells.isEmpty) return;
    final List<Poi> pois;
    try {
      pois = await ref
          .read(poiSourceProvider)
          .fetch(poiCellsBounds(missingCells), missingGroups);
    } on PoiUnavailable {
      state = PoiState(byCell: state.byCell, unavailable: true);
      return;
    } catch (e, s) {
      // Ein Funkloch ist auf dem Trail der Normalfall und kein Bericht
      // wert; alles andere (kaputte Antwort) wird gemeldet. Angezeigt
      // wird beides gleich, und beim nächsten Verschieben geht's weiter.
      if (!looksOffline(e)) logError('Orte laden', e, s);
      state = PoiState(byCell: state.byCell, unavailable: true);
      return;
    }
    var byCell = {
      for (final e in state.byCell.entries) e.key: {...e.value},
    };
    if (byCell.length > _maxCells) {
      byCell = {
        for (final e in byCell.entries)
          if (cells.contains(e.key)) e.key: e.value,
      };
    }
    // Der Rahmen umfasst auch Zellen, die gar nicht fehlten — für die
    // gilt nur, was sie noch nicht hatten; Vorhandenes bleibt, wie es war.
    final fresh = <PoiCell, Map<PoiGroup, List<Poi>>>{
      for (final c in missingCells)
        c: {
          for (final g in missingGroups)
            if (byCell[c]?[g] == null) g: <Poi>[],
        },
    };
    for (final p in pois) {
      fresh[poiCellOf(p.position)]?[p.group]?.add(p);
    }
    for (final e in fresh.entries) {
      (byCell[e.key] ??= {}).addAll(e.value);
    }
    state = PoiState(byCell: byCell);
  }
}

final poiControllerProvider =
    NotifierProvider<PoiController, PoiState>(PoiController.new);
