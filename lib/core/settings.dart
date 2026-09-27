import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'errors.dart';

/// Gerätelokale Einstellungen — alles, was auf *diesem* Gerät gilt und
/// nicht ins Konto gehört.
///
/// Bewusst schmal: Was die Nutzerin überallhin begleiten soll (Profil,
/// Freigaben), steht in Supabase und wird dort von RLS geschützt. Hier
/// liegt nur, was ohne Konto und ohne Netz beantwortbar sein muss.
///
/// Als Schnittstelle, damit Tests sie wie die Repositories mit einer Fake
/// belegen können (`test/fakes/fake_settings.dart`) — ein echter
/// SharedPreferences-Kanal existiert im Widget-Test nicht.
abstract interface class Settings {
  /// Bekommt dieses Gerät auch Vorabversionen angeboten?
  ///
  /// Standardmäßig NEIN, und das ist der ganze Sinn der Trennung: JEDER
  /// Versions-Bump baut ein Release, aber als Prerelease — für die Nutzer
  /// unsichtbar, weil `/releases/latest` grundsätzlich keine Prereleases
  /// liefert. Wer den Schalter umlegt, hebt genau diesen Schutz für sich
  /// auf und bekommt Zwischenstände, die niemand abgenommen hat.
  ///
  /// Gerätelokal wie alle Schalter hier: Es ist eine Einstellung dieses
  /// Telefons, keine des Kontos — auf dem Zweitgerät will man denselben
  /// Menschen nicht zwangsweise im Vorab-Kanal haben.
  bool get prereleaseUpdatesEnabled;

  Future<void> setPrereleaseUpdatesEnabled(bool value);

  /// Die eingeschalteten Orte-Gruppen der Karte (`PoiGroup.name`), oder
  /// null, solange nie etwas umgelegt wurde — dann gilt die Vorgabe.
  /// Leer heißt „alles aus", nicht „Vorgabe".
  List<String>? get poiGroups;

  Future<void> setPoiGroups(List<String> groups);

  /// Einzeln abgewählte Arten innerhalb der Gruppen (`PoiKind.name`) —
  /// der Detailfilter. Leer oder null: alle Arten einer Gruppe sichtbar.
  List<String>? get poiHiddenKinds;

  Future<void> setPoiHiddenKinds(List<String> kinds);
}

/// Umsetzung auf SharedPreferences (Android: XML im App-Verzeichnis).
class PrefsSettings implements Settings {
  const PrefsSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _prereleaseUpdatesEnabledKey = 'prerelease_updates_enabled';

  @override
  bool get prereleaseUpdatesEnabled =>
      _prefs.getBool(_prereleaseUpdatesEnabledKey) ?? false;

  @override
  Future<void> setPrereleaseUpdatesEnabled(bool value) =>
      _prefs.setBool(_prereleaseUpdatesEnabledKey, value);

  static const _poiGroupsKey = 'poi_groups';

  @override
  List<String>? get poiGroups => _prefs.getStringList(_poiGroupsKey);

  @override
  Future<void> setPoiGroups(List<String> groups) =>
      _prefs.setStringList(_poiGroupsKey, groups);

  static const _poiHiddenKindsKey = 'poi_hidden_kinds';

  @override
  List<String>? get poiHiddenKinds => _prefs.getStringList(_poiHiddenKindsKey);

  @override
  Future<void> setPoiHiddenKinds(List<String> kinds) =>
      _prefs.setStringList(_poiHiddenKindsKey, kinds);
}

/// Wird in `main()` mit den geladenen Einstellungen überschrieben, in Tests
/// vom Harness (`test/fakes/test_app.dart`).
///
/// Absichtlich synchron statt `FutureProvider`: Ein Schalter, der erst
/// nach dem ersten Frame gilt, ist einen Frame lang falsch — bei einer
/// Kartenquelle sichtbar als Griff nach Kacheln, die es ohne Netz nicht
/// gibt.
final settingsProvider = Provider<Settings>((ref) {
  throw StateError('settingsProvider muss überschrieben werden — '
      'siehe main() und test/fakes/test_app.dart');
});

/// Ein gerätelokal gemerkter An/Aus-Schalter.
///
/// **Warum ein Notifier und kein `StateProvider`.** Ein StateProvider
/// lässt sich von überall mit `.notifier).state = x` setzen, und das
/// Merken wäre dann ein zweiter Schritt, den man vergessen kann — die
/// Sorte Fehler, die erst beim übernächsten App-Start auffällt. Hier
/// gibt es nur [set], und das tut beides.
///
/// Der Zustand springt sofort, das Merken läuft nach, ein Fehler dabei
/// wird nur protokolliert — ein Schalter, der sich nicht merken lässt,
/// soll trotzdem umlegen.
class RememberedFlag extends Notifier<bool> {
  RememberedFlag({
    required this.read,
    required this.write,
    required this.label,
  });

  final bool Function(Settings settings) read;
  final Future<void> Function(Settings settings, bool value) write;

  /// Der Kontext für `logError`, etwa „Vorab-Kanal merken".
  final String label;

  @override
  bool build() => read(ref.read(settingsProvider));

  void set(bool value) {
    state = value;
    unawaited(write(ref.read(settingsProvider), value)
        .catchError((Object e, StackTrace s) => logError(label, e, s)));
  }
}
