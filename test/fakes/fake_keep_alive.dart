import 'package:trailbuddy/features/keep_alive/keep_alive.dart';

/// Der Foreground-Service im Speicher: zählt Starts, merkt Texte, Typen
/// und Takt — damit Tests prüfen können, WANN der Service läuft, ohne
/// Plattform-Kanal.
class FakeKeepAlive implements KeepAlive {
  bool running = false;
  int starts = 0;
  final texts = <String>[];
  final titles = <String>[];
  Set<KeepAliveType> types = const {};
  Duration? repeat;

  @override
  Future<void> start(String title, String text, Set<KeepAliveType> types) async {
    if (!running) {
      starts++;
      this.types = types;
    }
    running = true;
    titles.add(title);
    texts.add(text);
  }

  @override
  Future<void> update(String title, String text) async {
    titles.add(title);
    texts.add(text);
  }

  @override
  Future<void> setRepeat(Duration? every) async => repeat = every;

  @override
  Future<void> stop() async => running = false;
}
