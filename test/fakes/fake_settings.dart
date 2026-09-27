import 'package:trailbuddy/core/settings.dart';

/// Einstellungen im Speicher. Ein echter SharedPreferences-Kanal existiert
/// im Widget-Test nicht; ein Test, der den Neustart nachstellt, gibt die
/// Instanz einfach an den zweiten `pumpApp`-Aufruf weiter.
class FakeSettings implements Settings {
  FakeSettings(
      {this.prereleaseUpdatesEnabled = false, this.poiGroups, this.poiHiddenKinds});

  @override
  bool prereleaseUpdatesEnabled;

  @override
  List<String>? poiGroups;

  @override
  List<String>? poiHiddenKinds;

  @override
  Future<void> setPrereleaseUpdatesEnabled(bool value) async {
    prereleaseUpdatesEnabled = value;
  }

  @override
  Future<void> setPoiGroups(List<String> groups) async {
    poiGroups = groups;
  }

  @override
  Future<void> setPoiHiddenKinds(List<String> kinds) async {
    poiHiddenKinds = kinds;
  }
}
