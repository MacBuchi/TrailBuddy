import 'package:trailbuddy/core/settings.dart';

/// Einstellungen im Speicher. Ein echter SharedPreferences-Kanal existiert
/// im Widget-Test nicht; ein Test, der den Neustart nachstellt, gibt die
/// Instanz einfach an den zweiten `pumpApp`-Aufruf weiter.
class FakeSettings implements Settings {
  FakeSettings(
      {this.prereleaseUpdatesEnabled = false,
      this.poiGroups,
      this.poiHiddenKinds,
      this.seenNoteIds,
      this.officialTrailsEnabled = true});

  @override
  bool prereleaseUpdatesEnabled;

  @override
  List<String>? poiGroups;

  @override
  List<String>? poiHiddenKinds;

  @override
  List<String>? seenNoteIds;

  @override
  bool officialTrailsEnabled;

  @override
  Future<void> setOfficialTrailsEnabled(bool value) async {
    officialTrailsEnabled = value;
  }

  @override
  Future<void> setSeenNoteIds(List<String> ids) async {
    seenNoteIds = ids;
  }

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
