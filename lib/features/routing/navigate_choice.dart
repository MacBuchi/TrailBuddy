// Das Navi-Symbol an einem Trail (#176, Feldbericht 0.73.0: „Jeder Trail
// sollte ein kleines Icon haben, um dahin zu navigieren. Zwei auswählbare
// Optionen: externe Navi-App (Koordinate teilen) oder app-interne
// MTB-Navigation — spaßig oder direkt").
//
// Ein Tipp tut, was als Standard gemerkt ist (`Settings.navDefault`);
// ohne Standard fragt ein kleines Blatt mit drei Zeilen und dem Haken
// „Als Standard merken". Ein langer Druck fragt immer — so kommt man vom
// Standard wieder weg, ohne ins Profil zu müssen.
//
// Der Weg in TrailBuddy ist ein WUNSCH an die Karte
// (`trailHeadRequestProvider`), wie „Zum Trailkopf" im Blatt: Das Symbol
// steht auch in der Liste, die Vorschau gehört aber auf die Karte.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/router_branches.dart';
import '../../core/settings.dart';
import '../../models/trail.dart';
import '../trails/trail_navigation.dart';
import 'trail_head_providers.dart';

enum NavChoice {
  external('external', 'Mit der Navi-App', 'Der Trailkopf geht an Google Maps, OsmAnd & Co.', Icons.directions_outlined),
  direct('direct', 'In TrailBuddy: direkt', 'Der kürzeste Weg über deine gespeicherten Bereiche.', Icons.straight),
  fun('fun', 'In TrailBuddy: spaßig', 'Nimmt Trails auf dem Weg mit — ein Umweg, der sich lohnt.',
      Icons.downhill_skiing);

  const NavChoice(this.db, this.label, this.description, this.icon);
  final String db;
  final String label;
  final String description;
  final IconData icon;

  static NavChoice? parse(String? s) => values.where((c) => c.db == s).firstOrNull;
}

/// Das Symbol. [choose]: immer fragen (der lange Druck).
Future<void> navigateToTrail(BuildContext context, WidgetRef ref, Trail trail, {bool choose = false}) async {
  final remembered = NavChoice.parse(ref.read(settingsProvider).navDefault);
  final choice = !choose && remembered != null ? remembered : await _ask(context, ref, remembered);
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case NavChoice.external:
      await navigateToTrailHead(context, trail);
    case NavChoice.direct || NavChoice.fun:
      // Ein offenes Trail-Blatt zu, dann der Reiter, dann der Wunsch —
      // wie „Zum Trailkopf" im Blatt.
      final request = ref.read(trailHeadRequestProvider.notifier);
      final navigator = Navigator.of(context);
      if (navigator.canPop() && ModalRoute.of(context) is PopupRoute) navigator.pop();
      StatefulNavigationShell.maybeOf(context)?.goBranch(kMapBranchIndex);
      request.state = (trailId: trail.id, mode: choice == NavChoice.fun ? RouteMode.fun : RouteMode.direct);
  }
}

Future<NavChoice?> _ask(BuildContext context, WidgetRef ref, NavChoice? current) async {
  var remember = false;
  final picked = await showModalBottomSheet<NavChoice>(
    context: context,
    showDragHandle: true,
    // Vier Zeilen mit Erklärung sind auf einem kleinen Telefon höher als
    // die Vorgabe (9/16 der Höhe) — der Haken läge sonst unter dem Rand.
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Zum Trail navigieren', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final c in NavChoice.values)
              ListTile(
                key: ValueKey('nav-choice-${c.db}'),
                leading: Icon(c.icon),
                title: Text(c.label),
                subtitle: Text(c.description),
                trailing: c == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(c),
              ),
            CheckboxListTile(
              key: const ValueKey('nav-remember'),
              value: remember,
              onChanged: (v) => setState(() => remember = v ?? false),
              title: const Text('Als Standard merken'),
              subtitle: const Text('Ein langer Druck aufs Symbol fragt wieder.'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    ),
  );
  if (picked != null && remember) {
    try {
      await ref.read(settingsProvider).setNavDefault(picked.db);
    } catch (e, s) {
      logError('Navi-Standard merken', e, s);
    }
  }
  return picked;
}

/// Das kleine Symbol, das an jedem Trail steht (Liste, Schnellkarte).
class TrailNavButton extends ConsumerWidget {
  const TrailNavButton(this.trail, {super.key});

  final Trail trail;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onLongPress: () => navigateToTrail(context, ref, trail, choose: true),
        child: IconButton(
          key: ValueKey('trail-nav-${trail.id}'),
          tooltip: 'Zum Trail navigieren',
          icon: const Icon(Icons.navigation_outlined),
          onPressed: () => navigateToTrail(context, ref, trail),
        ),
      );
}
