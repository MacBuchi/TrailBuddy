import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_distribution.dart';
import '../app_info.dart';
import '../update_check.dart';
import 'trailbuddy_logo.dart';

/// Sperrt die App, solange die installierte Version unter der
/// server-seitigen Mindestversion liegt.
///
/// Bewusst eine Vollbild-Sperre und kein Dialog: sie ersetzt den kompletten
/// Router-Inhalt und lässt sich damit weder wegtippen noch mit der
/// Zurück-Taste umgehen — ein Dialog bräuchte dafür `PopScope` und
/// `barrierDismissible: false` und wäre trotzdem angreifbarer.
///
/// Solange geladen wird oder die Prüfung fehlschlägt, läuft die App normal:
/// [updateRequiredProvider] sperrt nur bei einer eindeutigen Antwort.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(updateRequiredProvider).valueOrNull ?? false;
    if (!blocked) return child;
    return const _UpdateRequiredScreen();
  }
}

class _UpdateRequiredScreen extends ConsumerWidget {
  const _UpdateRequiredScreen();

  /// Beschriftung und Ziel hängen am Auslieferungskanal: ein Play-Build darf
  /// nicht auf APK-Downloads verweisen („Device and Network Abuse"), und im
  /// Web gibt es nichts zu installieren — dort genügt ein Neuladen.
  static (String, String) get _action {
    if (kIsWeb) return ('Seite neu laden', AppInfo.webAppUrl);
    if (AppDistribution.isPlayBuild) {
      return ('Im Play Store aktualisieren', AppInfo.playStoreUrl);
    }
    return ('Update herunterladen', AppInfo.apkDownloadUrl);
  }

  Future<void> _openAction() {
    final (_, url) = _action;
    return launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      // Im Web dieselbe Seite ersetzen statt einen zweiten Tab öffnen —
      // das ist hier das Neuladen.
      webOnlyWindowName: '_self',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appVersionProvider).valueOrNull;
    final minimum = ref.watch(minimumSupportedVersionProvider).valueOrNull;
    final (label, _) = _action;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TrailBuddyMark(size: 88),
                  const SizedBox(height: 24),
                  Text('Update erforderlich',
                      style: textTheme.headlineSmall
                          ?.copyWith(color: scheme.onSurface),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(
                    'Diese Version von TrailBuddy ist zu alt und kann nicht '
                    'mehr mit dem Server arbeiten. Deine Trails sind sicher '
                    'gespeichert und nach dem Update wieder da.',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Zwei Zeilen statt einer mit Trenner: als Paar
                  // untereinander bleibt der Vergleich auch auf schmalen
                  // Geräten lesbar, statt mitten im Satz umzubrechen.
                  if (current != null && minimum != null)
                    Text(
                      'Installiert: $current\nBenötigt ab: $minimum',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _openAction,
                    icon: const Icon(
                        kIsWeb ? Icons.refresh : Icons.open_in_browser,
                        size: 18),
                    label: Text(label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
