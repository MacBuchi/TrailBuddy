import 'package:flutter/material.dart';

/// Design-Tokens der TrailBuddy-Palette — DIE eine Quelle für die
/// wiederkehrenden Marken-Töne. Neue Farben gehören hierher, nicht als
/// Hex-Literal in ein Widget (bekannte Schuld aus PilzBuddy, dort nie
/// ganz aufgeräumt — hier von Anfang an so).
abstract final class AppColors {
  /// Primärton: Theme-Seed, eigene Trails, Akzente. Ein dunkles
  /// Waldgrün mit Blaustich, das sich von der OSM-Karte abhebt.
  static const trailGreen = Color(0xFF1F6F5F);

  /// Blau für alles, was von Buddys kommt (fremde Trails, Anfragen).
  static const friendBlue = Color(0xFF1565C0);

  /// Warnungen und „bitte nachsehen"-Abzeichen: ein Orange, das auf der
  /// Karte weder Grün noch Blau ist.
  static const warningAmber = Color(0xFFEF6C00);

  /// „Hier gibt es etwas Neues von einem Buddy" (#7): Leuchtrand um die
  /// Linie auf der Karte, Tönung der Zeile in der Liste. Ein Gelb, das
  /// neben Grün, Blau und dem Warn-Orange als eigene Aussage lesbar
  /// bleibt — es färbt nie die Linie selbst, die bleibt bei ihrer Farbe.
  static const noteYellow = Color(0xFFFFC400);

  /// Offizielle Trails (#13): gestrichelt in Violett — keine der
  /// Trail-Farben, die sagen, was ICH mit einem Trail zu tun habe.
  /// Gesperrte Teile grau, nicht orange: Orange ist die Meldung eines
  /// Buddys, die Sperre kommt von der Quelle.
  static const officialViolet = Color(0xFF7B1FA2);

  /// Die eigene Position: ein dunkler Punkt mit weißem Ring. Nicht das
  /// übliche Blau — Blau heißt hier „von einem Buddy".
  static const positionDot = Color(0xFF263238);

  /// Die eigene Fahrt (#28): die laufende Spur und eine gespeicherte
  /// Fahrt auf der Karte. Derselbe dunkle Ton wie der Positionspunkt —
  /// „das bin ich, gerade jetzt" —, nicht Grün: Grün heißt „mein Trail",
  /// und eine Fahrt ist noch keiner.
  static const rideTrack = Color(0xFF455A64);

  /// Ein Kandidat für einen neuen Trail im Zerlege-Blatt (#29): ein
  /// Stück der Fahrt, das noch kein Trail ist — weder Grün (meiner) noch
  /// Blau (Buddy) noch Orange (Warnung), sondern eine Frage. Das
  /// bekannte, wieder gefahrene Stück trägt Grün.
  static const candidate = Color(0xFFC2185B);

  /// Der Landton der Karte, wo (noch) keine Kachel liegt — derselbe Wert
  /// wie die `earth`-Fläche des erzeugten Kartenstils, damit die Fläche
  /// nach „Karte lädt" aussieht und nicht nach „kaputt". Beide Engines
  /// lesen ihn (flutter_map als `backgroundColor`, MapLibre als
  /// background-Ebene im Style).
  static const mapBackground = Color(0xFFE2DFDA);
}
