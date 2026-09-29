import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_colors.dart';
import 'core/app_theme.dart';
import 'core/router.dart';
import 'core/widgets/preview_ribbon.dart';
import 'core/widgets/push_listener.dart';
import 'core/widgets/update_gate.dart';

class TrailBuddyApp extends ConsumerWidget {
  const TrailBuddyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'TrailBuddy',
      routerConfig: router,
      // UpdateGate innen: ist die App zu alt, ersetzt er den Router-Inhalt
      // komplett. PushListener darüber: Eine Meldung kann eintreffen,
      // während jemand im Profil oder in der Buddy-Liste steht, nicht nur
      // auf der Karte — und im Vordergrund zeigt Android sie nicht selbst
      // an (#34). PreviewRibbon ganz außen: Der Hinweis, dass dies ein
      // Entwicklungsstand ist, gilt auch über der Update-Sperre — gerade
      // dort, wo sonst nichts von der App zu sehen ist. Im normalen Build
      // reicht er nur durch.
      builder: (context, child) => PreviewRibbon(
        child: PushListener(
          child: UpdateGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
      theme: buildAppTheme(AppColors.light),
      darkTheme: buildAppTheme(AppColors.dark),
      themeMode: ref.watch(appearanceProvider),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
