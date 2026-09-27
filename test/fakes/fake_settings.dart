import 'package:trailbuddy/core/settings.dart';

/// Einstellungen im Speicher. Ein echter SharedPreferences-Kanal existiert
/// im Widget-Test nicht; ein Test, der den Neustart nachstellt, gibt die
/// Instanz einfach an den zweiten `pumpApp`-Aufruf weiter.
class FakeSettings implements Settings {
  FakeSettings({this.prereleaseUpdatesEnabled = false});

  @override
  bool prereleaseUpdatesEnabled;

  @override
  Future<void> setPrereleaseUpdatesEnabled(bool value) async {
    prereleaseUpdatesEnabled = value;
  }
}
