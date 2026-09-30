# TrailBuddy Logo C3 – Handoff für Claude Code

Neues Zeichen „Serpentine C3“: zwei Kehren (r 13 / r 16), verbunden über eine gemeinsame Tangente. Die Anlieger werden nur nach außen breiter, die Strecke wird schmaler (11 → 8), am Ende auslaufende Striche. Es gibt drei optische Größen:

| Größe | Einsatz | Endstriche |
| --- | --- | --- |
| **L** ≥ 32 px | App-Icons, Login, Splash, Loader | 2 (Breite 6 / 4) |
| **M** 20–28 px | Statusleiste, Benachrichtigungs-Icon, Knopf, Kopfzeile | 1 (Breite 8) |
| **S** ≤ 18 px | Favicon, Header der Benachrichtigung | keine, längerer Auslauf |

Das Zeichen ist eine **gefüllte Fläche** (keine Linie mit Strichstärke). Die Referenz im Design-Projekt ist `TrailBuddy Logo C3.dc.html`.

## Farben
- Lime `#B6F04A` (Akzent, Icon-Hintergrund) · Ink `#0E1411` (Zeichen auf Lime) · Moos `#4F8A10` (Light Mode) · Loader-Spur dunkel `#2A3630`, hell `#E4E3DB`

## Dateien → Zielorte im Repo `MacBuchi/trailbuddy`

| Datei | Ziel |
| --- | --- |
| `flutter/trailbuddy_logo.dart` | `lib/core/widgets/trailbuddy_logo.dart` |
| `app_icon/icon_ios_1024.png` | `assets/branding/` → Quelle für flutter_launcher_icons (iOS) |
| `app_icon/icon_android_legacy_1024.png` | `assets/branding/` (Android < 8, Zeichen auf 80 %) |
| `app_icon/adaptive_foreground_432.png` | `assets/branding/` (Adaptive-Vordergrund, Schutzzone 66/108) |
| `app_icon/adaptive_monochrome_432.png` | `assets/branding/` (Android 13 Themed Icon) |
| `app_icon/play_store_512.png` | Play Console, nicht im Repo |
| `android_notification/drawable-*/ic_stat_trailbuddy.png` | `android/app/src/main/res/drawable-*/` |
| `splash/splash_android12_1152.png` | `assets/branding/` (flutter_native_splash, Android 12+) |
| `splash/splash_logo_lime_512.png` | `assets/branding/` (Splash < Android 12, iOS) |
| `web/Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png` | `web/icons/` (ersetzt die alten) |
| `web/favicon.png`, `web/favicon.svg` | `web/` |
| `svg/*.svg` | `assets/branding/svg/` (Druck, Store-Grafiken, Doku) |

## pubspec.yaml

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.0
  flutter_native_splash: ^2.4.0

flutter_launcher_icons:
  ios: true
  android: true
  image_path_ios: assets/branding/icon_ios_1024.png
  image_path_android: assets/branding/icon_android_legacy_1024.png
  adaptive_icon_background: "#B6F04A"
  adaptive_icon_foreground: assets/branding/adaptive_foreground_432.png
  adaptive_icon_monochrome: assets/branding/adaptive_monochrome_432.png
  remove_alpha_ios: true

flutter_native_splash:
  color: "#0E1411"
  image: assets/branding/splash_logo_lime_512.png
  android_12:
    color: "#0E1411"
    image: assets/branding/splash_android12_1152.png
```

Danach: `dart run flutter_launcher_icons` und `dart run flutter_native_splash:create`.

## Benachrichtigungen

`AndroidManifest.xml` (innerhalb von `<application>`), falls FCM genutzt wird:

```xml
<meta-data android:name="com.google.firebase.messaging.default_notification_icon"
           android:resource="@drawable/ic_stat_trailbuddy" />
<meta-data android:name="com.google.firebase.messaging.default_notification_color"
           android:resource="@color/trailbuddy_lime" />
```

`android/app/src/main/res/values/colors.xml`: `<color name="trailbuddy_lime">#B6F04A</color>`

flutter_local_notifications: `AndroidInitializationSettings('ic_stat_trailbuddy')` bzw. `icon: 'ic_stat_trailbuddy'` in den `AndroidNotificationDetails`.

Die PNGs sind weiß mit Alpha und haben 12 % Rand. Sie werden aus der **M**-Fassung erzeugt und ersetzen `notification_icon_*.png`.

## Web-Manifest

In `web/manifest.json`: `"background_color": "#0E1411"`, `"theme_color": "#B6F04A"`. Die Icons bleiben unter denselben Namen (`purpose: "maskable"` für die Maskable-Varianten). In `web/index.html` zusätzlich:

```html
<link rel="icon" type="image/svg+xml" href="favicon.svg">
<link rel="icon" type="image/png" href="favicon.png">
```

## Flutter-Widgets (`trailbuddy_logo.dart`)

Die Datei hat keine Abhängigkeiten und nutzt nur `CustomPainter`. Die optische Größe (L/M/S) wird automatisch nach der Pixelgröße gewählt.

```dart
TrailBuddyMark(size: 64)                                   // Login, Lime
TrailBuddyMark(size: 64, color: AppColors.moss)            // Light Mode
TrailBuddyMark(size: 20, color: Colors.white)              // Kopfzeile → M
TrailBuddyLoader(size: 56)                                 // dunkel
TrailBuddyLoader(size: 56, runner: Color(0xFF4F8A10), track: Color(0xFFE4E3DB)) // hell
TrailBuddyLoader(size: 24, runner: ink, track: ink.withOpacity(.25))           // im Knopf → M
TrailBuddySplash(onDone: () => context.go('/map'))         // Splash B, dunkel
TrailBuddySplash.light()                                   // Splash B, hell
TrailBuddyDrawIn(progress: p, size: 72)                    // nur das Zeichnen, für eigene Abläufe
```

**Splash B:** Das Zeichen wird in 1,3 s linear gezeichnet. Ab 1,26 s baut sich die Wortmarke mit weicher Kante (14 % der Textbreite) von links nach rechts auf, in 0,52 s mit `easeOutQuad`. Insgesamt dauert der Splash 1,78 s. Er folgt auf den nativen Splash (dunkel, `#0E1411`), damit es keinen Sprung gibt: Der native Splash zeigt nur die Hintergrundfarbe oder das fertige Zeichen, dann übernimmt `TrailBuddySplash`.

**Loader-Verhalten:** Der Läufer ist 40 Einheiten lang und genau so breit wie die Strecke an seiner Position. Seine runden Kappen haben den Radius der halben Streckenbreite. Über die Lücken springt er in die Endstriche. Ein Durchlauf dauert 1,5 s, danach 0,5 s Pause.

**Geometrie:** Für jede Größe enthält die Datei 241 Stichproben der Mittellinie `[x, y, nx, ny, halbeBreiteLinks, halbeBreiteRechts]` im 100er-Raster, dazu die Endstriche. `range(a, b)` liefert die Fläche des Streckenabschnitts a…b. Das ganze Logo ist `range(0, total)`.

## Vorschlag für die Umsetzung (Aufgaben für Claude Code)

1. Dateien an die Zielorte kopieren. Alte `notification_icon_*.png` und `web/icons/*` ersetzen.
2. `trailbuddy_logo.dart` einbinden. Alle bisherigen Logo-Widgets bzw. SVGs in Login, Splash, AppBar und Ladezuständen durch `TrailBuddyMark`, `TrailBuddyLoader` und `TrailBuddyDrawIn` ersetzen.
3. pubspec-Konfiguration ergänzen, Launcher-Icons und Splash generieren.
4. Benachrichtigungs-Icon im Manifest bzw. in flutter_local_notifications setzen.
5. `web/manifest.json` und `index.html` anpassen.
6. Sichtprüfung: Homescreen (rund und Themed Icon), Statusleiste, Benachrichtigung, Browser-Tab hell und dunkel, Loader hell und dunkel.
