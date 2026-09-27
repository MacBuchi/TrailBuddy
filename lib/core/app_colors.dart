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
}
