// Startet die komplette App gegen das In-Memory-Backend: alle
// Repository-Provider werden mit Fakes überschrieben, der Karten-Kachel-
// Provider liefert ein transparentes 1×1-PNG (keine OSM-Requests) und der
// Update-Check ist stillgelegt. Damit laufen echte End-to-End-Abläufe
// (Login → Karte → Buddys → Profil) als schnelle Widget-Tests.
import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trailbuddy/app.dart';
import 'package:trailbuddy/core/app_info.dart';
import 'package:trailbuddy/core/connectivity.dart';
import 'package:trailbuddy/core/settings.dart';
import 'package:trailbuddy/core/update_check.dart';
import 'package:trailbuddy/data/providers.dart';
import 'package:trailbuddy/features/map/base_map_providers.dart';
import 'package:trailbuddy/features/map/map_providers.dart';
import 'package:trailbuddy/features/map/map_view/flutter_map_view.dart';
import 'package:trailbuddy/features/map/map_view/map_view.dart';
import 'package:trailbuddy/features/map/poi_source.dart';
import 'package:trailbuddy/features/map/position_provider.dart';
import 'package:trailbuddy/features/official/official_trails_source.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_service.dart';
import 'package:trailbuddy/features/trails/outbox_providers.dart';
import 'package:trailbuddy/features/trails/trail_providers.dart';

import 'fake_backend.dart';
import 'fake_map_view.dart';
import 'fake_official_trails.dart';
import 'fake_outbox.dart';
import 'fake_pois.dart';
import 'fake_rides.dart';
import 'fake_settings.dart';
import 'fake_trail_cache.dart';
import 'fake_trails.dart';

/// 1×1 transparentes PNG als Offline-Kartenkachel.
final Uint8List kTransparentTile = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Test-Position ohne Geolocator-Plugin (alle Pflichtfelder gefüllt).
Position fakePosition(double lat, double lon, {double accuracy = 8}) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2026, 9, 28, 12),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Der EINZELNE Fix hinter „Meine Position" — zählt, wie oft gefragt
/// wurde (nur dort darf nach der Berechtigung gefragt werden).
class FakePositionFix {
  FakePositionFix([this.next]);

  Position? next;
  int calls = 0;

  Future<Position?> call() async {
    calls++;
    return next;
  }
}

class FakeTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(kTransparentTile);
}

List<Override> overridesFor(FakeBackend backend,
        {FakeAppConfigRepository? appConfig,
        String appVersion = '1.0.0',
        Settings? settings,
        FakeTrailRepository? trails,
        FakePoiSource? pois,
        FakeOfficialTrailsSource? official,
        MemoryOfficialTrailsCache? officialCache,
        Position? position,
        FakePositionFix? positionFix,
        FakeRideStore? rideStore,
        FakeRideFix? rideFix,
        FakeRideServiceBridge? rideBridge,
        FakeRideService? rideService,
        FakeOutbox? outbox,
        FakeTrailCache? trailCache,
        Stream<List<ConnectivityResult>>? connectivity,
        bool useRealMap = false,
        List<Override> extra = const []}) =>
    [
      // Die Karten-Engine ist standardmäßig die Fake (Marker in einem
      // Wrap, Kamera synchron simuliert, Tipps über die Trefferprüfung
      // der Fassade) — die Flow-Suiten beweisen Verhalten, nicht
      // Rendering. Tests, die flutter_map-Interna prüfen, pumpen mit
      // `useRealMap: true`; die MapLibre-Platform-View ist im Widget-Test
      // nicht renderbar, ihr Gate ist das Gerät.
      mapViewBuilderProvider.overrideWithValue(useRealMap
          ? (config, controller, layers) =>
              FlutterMapView(config: config, controller: controller, layers: layers)
          : (config, controller, layers) =>
              FakeMapView(config: config, controller: controller, layers: layers)),
      // Die Übersichtskarte kommt aus einem Asset, das der Test-Runner
      // nicht liefert — und ohne Empfang würde die echte Karte sie öffnen.
      overviewOpenerProvider.overrideWithValue(() async => null),
      settingsProvider.overrideWithValue(settings ?? FakeSettings()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
      profileRepositoryProvider
          .overrideWithValue(FakeProfileRepository(backend)),
      friendRepositoryProvider.overrideWithValue(FakeFriendRepository(backend)),
      feedbackRepositoryProvider
          .overrideWithValue(FakeFeedbackRepository(backend)),
      // Die Karte beobachtet die Trails, und die kämen sonst aus
      // `Supabase.instance` — das gibt es im Widget-Test nicht. Vorgabe
      // ist ein leeres Trail-Netz mit den Buddy-Regeln dieses Backends;
      // Tests mit Trails reichen ihr eigenes Fake herein.
      trailRepositoryProvider.overrideWithValue(trails ??
          FakeTrailRepository(
              myId: () => backend.currentUserId ?? '',
              areFriends: backend.areFriends)),
      // Kein Netz in Tests: Die Kacheln sind transparente 1×1-PNGs.
      mapTileProviderProvider.overrideWithValue(FakeTileProvider()),
      // Und keine Overpass-Abfragen: Eine Karte, die auf einen Trail
      // zoomt, liegt über Zoom 12 und fragte sonst wirklich an.
      poiSourceProvider.overrideWithValue(pois ?? FakePoiSource()),
      // Ebenso die offiziellen Trails: Vorgabe ist ein Index ohne
      // Regionen, gemerkt wird im Speicher statt im App-Verzeichnis.
      officialTrailsSourceProvider
          .overrideWithValue(official ?? FakeOfficialTrailsSource()),
      officialTrailsCacheProvider
          .overrideWithValue(officialCache ?? MemoryOfficialTrailsCache()),
      // Kein Plattform-Kanal für den Standort: Die Position kommt aus dem
      // Test (Vorgabe: keine, wie ohne Berechtigung).
      positionStreamProvider.overrideWith((ref) => Stream.value(position)),
      positionFixProvider
          .overrideWithValue((positionFix ?? FakePositionFix(position)).call),
      // Die Fahrt (#28): im Speicher statt auf der Platte, ohne
      // Foreground-Service und ohne Berechtigungsdialog. Ohne diese
      // Zeilen ginge jeder Kartentest beim ersten Frame (`restore`) an
      // `path_provider`.
      rideStoreProvider.overrideWithValue(rideStore ?? FakeRideStore()),
      rideFixProvider.overrideWithValue((rideFix ?? FakeRideFix()).call),
      rideServiceBridgeProvider.overrideWithValue(rideBridge ?? FakeRideServiceBridge()),
      rideServiceProvider.overrideWithValue(rideService ?? FakeRideService()),
      ridePermissionProvider.overrideWithValue(() async => null),
      // Der Ausgangskorb (#30) im Speicher; der Netzwechsel kommt aus dem
      // Test (Vorgabe: WLAN, ohne Wechsel).
      outboxProvider.overrideWithValue(outbox ?? FakeOutbox()),
      // Die Kopie des Netzes (#32) im Speicher — ohne Override ginge
      // jeder Abruf an `path_provider`.
      trailCacheProvider.overrideWithValue(trailCache ?? FakeTrailCache()),
      connectivityProvider.overrideWith(
          (ref) => connectivity ?? Stream.value(const [ConnectivityResult.wifi])),
      updateInfoProvider.overrideWith((ref) => Future.value(null)),
      // Mindestversion: ohne Angabe sperrt nichts. PackageInfo gibt es im
      // Test nicht, deshalb kommt die eigene Version aus dem Harness.
      appConfigRepositoryProvider
          .overrideWithValue(appConfig ?? FakeAppConfigRepository()),
      appVersionProvider.overrideWith((ref) => Future.value(appVersion)),
      // Zuletzt, damit ein Test gezielt etwas aus der Liste oben ersetzen
      // kann — bei Riverpod gewinnt der spätere Eintrag.
      ...extra,
    ];

/// App starten und den ersten Aufbau abwarten.
Future<void> pumpApp(WidgetTester tester, FakeBackend backend,
    {FakeAppConfigRepository? appConfig,
    String appVersion = '1.0.0',
    Settings? settings,
    FakeTrailRepository? trails,
    FakePoiSource? pois,
    FakeOfficialTrailsSource? official,
    MemoryOfficialTrailsCache? officialCache,
    Position? position,
    FakePositionFix? positionFix,
    FakeRideStore? rideStore,
    FakeRideFix? rideFix,
    FakeRideServiceBridge? rideBridge,
    FakeRideService? rideService,
    FakeOutbox? outbox,
    FakeTrailCache? trailCache,
    Stream<List<ConnectivityResult>>? connectivity,
    bool useRealMap = false,
    List<Override> extraOverrides = const []}) async {
  addTearDown(backend.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: overridesFor(backend,
        appConfig: appConfig,
        appVersion: appVersion,
        settings: settings,
        trails: trails,
        pois: pois,
        official: official,
        officialCache: officialCache,
        position: position,
        positionFix: positionFix,
        rideStore: rideStore,
        rideFix: rideFix,
        rideBridge: rideBridge,
        rideService: rideService,
        outbox: outbox,
        trailCache: trailCache,
        connectivity: connectivity,
        useRealMap: useRealMap,
        extra: extraOverrides),
    child: const TrailBuddyApp(),
  ));
  await tester.pump();
  await settle(tester);
}

/// Auf einen Reiter wechseln — über die Leiste und nicht über den
/// nackten Text: „Trails" und „Profil" stehen auch im Inhalt (AppBar-
/// Titel, Überschriften), `find.text` träfe dann zwei Widgets.
Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label)));
  await settle(tester);
}

/// Feste Frames statt pumpAndSettle — die Karte animiert (Attribution,
/// Kamera), pumpAndSettle käme dort nicht zuverlässig zurück.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lässt die Wartezeit des „Erneut senden"-Knopfes ablaufen (ResendButton
/// startet gesperrt, weil gerade eine Mail rausging). Sekundenweise pumpen,
/// damit der Timer wirklich jede Sekunde feuert — ein Sprung um 60 s würde
/// nur einen Tick auslösen und den Countdown bei 59 stehen lassen.
Future<void> passResendCooldown(WidgetTester tester, {int seconds = 61}) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// SnackBar-Timer auslaufen lassen, damit am Testende nichts mehr tickt.
Future<void> drainSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Scrollt die erste Liste des Bildschirms, bis [finder] etwas trifft —
/// eine `ListView` baut nur, was im Bild ist, ein Eintrag weiter unten
/// existiert also erst nach dem Heranscrollen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 8 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester, frames: 4);
  }
  await tester.ensureVisible(finder);
  await settle(tester);
}
