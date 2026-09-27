import 'package:flutter/material.dart';

/// Ein runder Avatar mit dem ersten Buchstaben des Namens.
///
/// Bewusst schlicht: TrailBuddy hat (noch) keinen Avatar-Katalog, und ein
/// Bild, das jeder gleich hätte, sagte weniger als der Buchstabe. Das Feld
/// `avatar` am Profil bleibt dafür frei — kommt ein Katalog, tauscht man
/// dieses Widget an EINER Stelle, nicht in jeder Liste.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(letter,
          style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w600)),
    );
  }
}
