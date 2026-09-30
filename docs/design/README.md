# TrailBuddy — Design

*Stand 2026-09-29. Quelle: das Design-Projekt des Betreibers in Claude
Design („TrailBuddy Design", Turns 1–4), abgelegt in diesem Ordner. Hier
steht, was davon gilt und wo es im Code umgesetzt ist.*

Die Reihenfolge der Umsetzung (je ein PR) steht am Ende. Was hier steht,
ist verbindlich wie das Konzept: Wer im Code davon abweicht, ändert diese
Datei im selben PR. **Die Entwurfsdatei ist die Vorlage, diese Datei die
Entscheidung** — wo beide sich widersprechen (etwa Text in `#4F8A10` auf
Hell), gilt diese hier.

## 0. Die Vorlage in diesem Ordner

Das Design-Projekt, so unverändert wie möglich (Stand des letzten Syncs
2026-09-29 06:54 UTC):

| Datei | Was | Herkunft |
|---|---|---|
| `TrailBuddy Design.dc.html` | der Entwurf, alle vier Turns auf einer Leinwand | unverändert aus dem Projekt |
| `support.js` | die Laufzeit von Claude Design, die die Datei rendert | unverändert |
| `github.md` | die Sync-Notiz von Claude Design (welche Repo-Dateien es gelesen hat) | unverändert |
| `web/favicon.png`, `web/icons/Icon-512.png`, `web/icons/Icon-maskable-512.png` | die damaligen App-Symbole, die Claude Design aus dem Repo kopiert hatte (noch das Flutter-Standardsymbol) | byte-gleich aus Commit `8e10007` |
| `notification_icon_512.png`, `notification_icon_96.png` | das Statusleisten-Symbol (1f): weiß, Alpha, 12 % Rand | **neu gerendert** aus dem Logo-Pfad mit `tool/brand_icons.py` — das Original kam nur als Text über die Schnittstelle, byte-genau war es nicht zu übernehmen; dieselbe Form, ohne die Herkunftsdaten (C2PA) des Originals |

Nicht übernommen: `.thumbnail`, das Vorschaubild, das Claude Design selbst
für die Projektübersicht erzeugt.

**Ansehen:** `TrailBuddy Design.dc.html` im Browser öffnen (sie lädt
`support.js` daneben). Die Datei holt Schriften und Symbole von Google
Fonts und React von unpkg.com — das betrifft nur die Vorlage beim Ansehen,
nie die App. Namen, Trails und die Mailadresse darin sind Beispiele.

## 1. Grundidee

Sportlich und kartografisch: ein Signal-Lime als Marke, Mono-Ziffern für
Länge, Höhenmeter und S-Grad, schmale Großbuchstaben für Titel. Hell und
dunkel. **Die Farbe eines Trails sagt seine Schwierigkeit** — in
Pistenfarben, auf der Karte, im Streifen der Liste und im Schild
(Betreiber, 2026-09-29: „nicht nach Buddy / mein Trail, sondern nach den
Schwierigkeitsstufen"). Der Entwurf hatte es umgekehrt (Farbe =
Beziehung, Schwierigkeit nur als Form und als Schalter „Pisten-Brille");
das gilt seit 0.42.0 nicht mehr. Wem ein Trail gehört, sagt nur noch das
Wort („MEIN", „JAN, MIRA", „Du und 2 Buddys") — farblich gar nicht. Der
Charakter bleibt Symbol, nie Farbe: Eine Linie trägt nur eine Farbe, ein
Trail bis zu zwei Merkmale.

## 2. Farben (Turn 1a, 4a) — `lib/core/app_colors.dart`

| Token | Dunkel | Hell |
|---|---|---|
| Grund | `#0E1411` | `#F3F2EC` |
| Fläche | `#161E19` | `#FFFFFF` |
| Fläche 2 | `#1F2923` | `#ECEBE4` (nicht im Entwurf) |
| Linie | `#2A3630` | `#E4E3DB` |
| Text | `#F2F4EF` | `#131A16` |
| gedämpft | `#9AA69D` | `#5E6B62` |
| Knopf | `#B6F04A`, Schrift `#0E1411` | derselbe |
| Marke als Zeichen (Logo) | `#B6F04A` | `#4F8A10` („Marke auf Hell") |
| Marke als Text | `#B6F04A` | `#3D6E0B` ¹ |
| Hinweis als Text | `#FFD23F` | `#7A5C00` ¹ |

¹ Abweichung vom Entwurf, der `#4F8A10` auch für Text zeigt: Als Text
erreicht es auf Weiß nur 4,2:1, verlangt sind 4,5:1. Dasselbe für Warnung
(`#A94510`) und Buddy (`#0A7299`) als Text, und für das Hinweis-Gelb
(`#F2B600`, 1,9:1) als Wort in der Liste („NEUER HINWEIS", seit 0.38.0).
`test/core/app_theme_test.dart` prüft jedes Paar.

**Trail-Farben = Schwierigkeit** (Linie, Streifen, Schild;
`GradePalette`, seit 0.42.0):

| Stufe | Dunkel | Hell (auch Karte) | Form auf der Karte |
|---|---|---|---|
| S0 | `#4CC46E` | `#1F7A3A` | durchgezogen |
| S1 | `#5A9BF0` | `#1F6FD1` | durchgezogen |
| S2 | `#F0605C` | `#C62828` | durchgezogen |
| S3 | `#F2F4EF` | `#131A16` | durchgezogen |
| S4, S5 | `#F2F4EF` | `#131A16` | gestrichelt |
| ohne Einschätzung | `#9AA69D` | `#6B756F` | durchgezogen |
| **Uphill** (schlägt die Stufe) | `#4DB6AC` | `#00796B` | durchgezogen; im Schild ein Pfeil ↗ statt der Form |

**Uphill** (Betreiber, 2026-09-29: „hier macht Symbol und Farbe Sinn"):
Die Pistenfarben beschreiben eine Abfahrt; ein Trail, unter dessen
angezeigten zwei Merkmalen Uphill ist (dieselbe Lesart wie die Filter),
trägt Petrol statt seiner Stufe — auf der Karte, im Streifen und im
Schild. Das Schild behält den Grad („↗ S2"): Er sagt, wie technisch die
Auffahrt ist. EINE Regel für alle drei Stellen: `trailColorOf` in
`grade_shield.dart`. Petrol, weil jede andere Farbe schon etwas heißt.

Die Töne des Entwurfs (S0 `#2E9E4F`, S2 `#D6322F`) sind nachgedunkelt:
Auf ihnen steht im Schild weiße Schrift, verlangt sind 4,5:1. Im Dunklen
hellere Töne mit dunkler Schrift, und „schwarz" ist dort die Textfarbe —
ein schwarzer Streifen auf dunkler Karte verschwände. Jede Stufe hat
≥ 3:1 auf Fläche, Grund und dem Landton der Karte (Test).

**Zustände liegen als Rand UM die Linie, nie auf ihr:**

| Bedeutung | Dunkel | Hell | Form |
|---|---|---|---|
| Gesperrt / Warnung | `#FF8A3D` | `#D9591A` | Leuchtrand (schlägt den Hinweis); als Wort in der Liste |
| Neuer Hinweis | `#FFD23F` | `#F2B600` | Leuchtrand; Kartenrand in der Liste |

**Andere Linien** (keine Trails des Netzes, keine Stufenfarbe):

| Bedeutung | Dunkel | Hell | Form |
|---|---|---|---|
| Mein Trail / Von Buddy | `#B6F04A` / `#5AD0F0` | `#4F8A10` / `#0B84B0` | nur noch Symbole und Vorschau „bekannt" im Zerlege-Blatt, keine Trail-Linie |
| Offiziell | `#B58CFF` | `#7B4FD6` | gestrichelt |
| Kandidat | `#FF6BA8` | `#D1336F` | „eine Frage" |
| Meine Fahrt / Position | `#E8ECE6` | `#2A332E` | |

**Die Karte ist hell** (Turn 4: „Die Karte (Protomaps light) ist hell, und
in praller Sonne liest sich dunkel schlechter"). Turn 1 zeigte noch eine
dunkle „Nacht-Karte"; Turn 4 hat das ersetzt. Deshalb zeichnet die Karte
in BEIDEN App-Modi den hellen Satz mit weißem Saum (Breite + 4):
`AppColors.mapLines`. Der dunkle Satz färbt Symbole und Streifen auf den
dunklen Flächen der App.

## 3. Schriften — `lib/core/app_theme.dart`, `assets/fonts/`

- **Barlow Condensed** 700/800 — Titel, gern in Großbuchstaben
  („TRAILS", „ROSSKOPF SÜD").
- **Barlow** 400–600 — Text.
- **JetBrains Mono** 500 — ALLE Zahlen: km, Hm, S-Grad, Zähler
  (`AppFonts.numbers`).

Als Assets gebündelt (SIL OFL), nie `google_fonts` — die App muss offline
gleich aussehen.

## 4. Logo (Turn 1b) — `lib/core/widgets/trailbuddy_logo.dart`, `tool/brand_icons.py`

Die **Serpentine — zwei Kehren, ein Ziel**, viewBox 100:

```
Pfad   M20 20H62a13 13 0 0 1 0 26H38a13 13 0 0 0 0 26H72
Strich 14, runde Enden und Ecken
Punkt  Kreis (82, 72), r 7
```

- App-Symbol: dunkles Zeichen (`#0E1411`) auf Lime.
- Zweifarbig auf Dunkel (Login 1g): Linie Lime, Punkt hell.
- Statusleiste: weiß, nur Alphakanal, 12 % Rand (`ic_notification`, für
  Push UND die Dauerbenachrichtigung der Fahrt).
- Wortmarke: „TRAIL" in Textfarbe + „BUDDY" in der Marke, Barlow
  Condensed 800.

Das runde Ende der Linie (bis x = 79) berührt den Punkt (ab x = 75) — so
steht es im Entwurf. Einfarbig verschmelzen beide leicht, zweifarbig
trennt die Farbe sie.

Die Richtungen 1c (zwei Spuren), 1d (Monogramm TB) und 1e (Stollen) sind
verworfen; 1e bleibt eine Idee für Hintergründe.

**Alle Symbole kommen aus EINEM Skript**: `python3 tool/brand_icons.py`
(braucht `rsvg-convert`) schreibt Android adaptiv + Altformat, Web,
maskable, Favicon und das Statusleisten-Symbol;
`python3 tool/generated_assets.py --update` danach. In CI:
`brand_icons.py --check` (Vektoren sind Fixpunkt) und die Prüfsummen der
PNGs; `test/brand_icons_test.dart` hält Dart und Skript zusammen.

## 5. Offline-Kacheln (Turn 2) — eine Regel statt neuer Farbe

**Helligkeit = was auf dem Gerät liegt. Schraffur + gestrichelter Rand =
offene Änderung.** Die Schraffur hat immer die Gegenhelligkeit ihres
Grunds, deshalb reicht eine Regel für beide Richtungen. Kein Grün mehr —
Lime bleibt „mein Trail".

| Zustand | Grund | Schraffur | Rand |
|---|---|---|---|
| Nicht offline | abgedunkelt | — | — |
| Offline | hell | — | durchgehend um den ganzen Bestand |
| Kommt dazu | dunkel | hell | gestrichelt |
| Fällt weg | hell | dunkel | gestrichelt |

Variante A (die Leiste bearbeitet den ganzen Bestand) ist gebaut; der
Speichern-Dialog nennt beide Seiten und die betroffenen Bereiche beim
Namen (2c). Schraffur als **gerechnete Linien** je zusammengefasstem
Kachelrechteck über die `MapViewPolyline`-Fassade, Abstand in
Bildschirm-Pixeln (7 px), kein Füllmuster im Stil. Rückfall 2e: halbe
Tönung, nur die Randfarbe unterscheidet (hell = dazu, dunkel = weg) — er
greift, wenn die Schraffur über `kAreaHatchMaxLines` Linien bräuchte; auf
MapLibre selbst tragen die Linien.

Umgesetzt in `area_overlay.dart` (Maske, `offlineCoverage` mit dem Rand
um den Bestand in der Textfarbe des Modus, `tileOutline`) und
`area_draw.dart` (`draftLayers`, `kAreaInkLight`/`kAreaInkDark`). Auch
der Strich beim Zeichnen folgt der Regel.

## 6. Karte mit zwei Leisten (Turn 3, Spezifikation 3e)

- **Rechts unten — immer:** Aufnahme 60 px (Lime; läuft die Fahrt: Orange
  mit Stop-Quadrat), darüber 44 px: Position, Ebenen, Idee. Ein offenes
  Menü markiert seinen Knopf mit Rand in der Marke.
- **Links mittig — nur mit Menü:** 52 px breit, Knöpfe 44 px
  (Handschuh, Mindest-Trefferfläche), Gruppen durch 8 px Luft statt
  Trennlinien. Aktives Werkzeug = helle Fläche. Hauptaktion (Speichern) =
  Lime, der +/−-Zähler in Mono direkt darunter.
- **Oben:** ein Satz, was der nächste Strich tut; verschwindet, sobald kein
  Werkzeug scharf ist.
- **Unten links:** Maßstab + Quelle, rückt neben die linke Leiste.
- **Schließen:** X, Ebenen-Knopf, Zurück — mit Rückfrage bei offenem
  Entwurf.
- Der Filter (Orte, offizielle Trails) klappt aus der Leiste nach rechts
  auf (3c). Dasselbe Muster später für die Fahrt (3d: Folgen, Hinweis
  hier; Foto ist #37).
- **Reiterleiste:** Grund-Farbe, aktiver Reiter als Lime-Pill.

## 7. Schwierigkeit und Charakter (Turn 4)

**S-Grad als Form** — im Entwurf farblos, schwarzes Schild mit weißer
Form und „S3"; seit 0.42.0 in der Stufenfarbe (siehe Abschnitt 2):

| S0 | S1 | S2 | S3 | S4 | S5 |
|---|---|---|---|---|---|
| ○ fester, ebener Weg | ● kleine Wurzeln, Steine | ■ Stufen, lose, enge Kurven | ◆ Blockfelder, Spitzkehren | ◆◆ steil, verblockt, Umsetzen | ◆◆▮ extrem, Sprünge Pflicht |

(Die Beschreibungen in der App bleiben die eigenen aus
`singletrail_scale.dart`.) Auf der Karte am Trailanfang (Entwurf: erst ab
Zoom 13), in Liste und Blatt neben dem Namen.

**Gebaut in 0.42.0 für Liste, Blatt und Erklärblatt** (`grade_shield.dart`:
`GradeShield`, Formen gezeichnet, nicht als Zeichen aus der Schrift —
◆ und ▮ fehlen in Barlow wie der Pfeil). Das Schild trägt die
Stufenfarbe des Modus (`palette.grade`), Form und Zahl in
`GradePalette.ink`. Gezeigt wird der Median (`Trail.grade`), wie in
der Kachel; ohne Einschätzung kein Schild. In der Liste steht es rechts
oben über den Charakter-Symbolen, und „S2" fällt aus der Zahlenzeile —
zweimal dieselbe Angabe. Der Bildschirmleser hört „Schwierigkeit S3:
verblockt, hohe Stufen, enge Kehren".

**Auf der Karte seit 0.43.0** (`trail_badges.dart`, Schritt 6b): ab der
gerechneten Zoomstufe 13 (`kTrailBadgeMinZoom`) ein Schild je Trail am
Anfang in Trail-Richtung (`trailStart`: bei einer gegen die Richtung
aufgenommenen besten Linie deren Ende), mit Grad und den angezeigten
Merkmalen wie im Entwurf 4c, in der Farbe der Linie (`AppColors.mapGrades`,
die Karte ist immer hell). Abweichung vom Entwurf: Das Schild steht auf
der Seite, von der die Linie WEGführt (`trailHeadsNorth`, gemessen an
einem Punkt ~30 m weiter) — über dem Anfang lag es sonst auf der Linie.
Kein Schild ohne Grad und ohne Merkmale, keins für wartende Trails. Ein
Tipp öffnet den Trail (`hitValue`); die Trefferprüfung fragt Linien vor
Markern, am Anfang treffen beide denselben Trail.

**Charakter** — Mehrfachwahl je Beitrag, wie der Grad von Buddys
vergeben; angezeigt die höchstens 2 häufigsten, als Symbol:
Flowig (Wellen, Anlieger, Rhythmus), Jump-Line (Kicker, Drops, Tables),
Verblockt (Steine, Wurzeln, Stufen), Steil (anhaltendes Gefälle), Uphill
(Auffahrt, auch bergauf fahrbar). **Gebaut seit 0.34.0 (#72)** und um
Naturtrail und Verbindung aus der früheren „Art" erweitert (Betreiber,
2026-09-29: der Charakter ERSETZT die Art, sieben Merkmale): Auswahl als
Chips im Beitrag, im Blatt „Flowig · 3", in der Liste als Symbole
(`trail_traits.dart`, Symbole farblos), seit 0.35.0 auch je Kandidat im
Zerlege-Blatt.

**Pisten-Brille** — im Entwurf ein Schalter unter Ebenen, „Farbe nach
Schwierigkeit", mit der Breite als Beziehung (meiner 5, nur Buddy 3,5).
**Entfällt seit 0.42.0:** Die Pistenfarben sind der Normalzustand, und
die Beziehung zeigt die Karte gar nicht mehr (Betreiber, 2026-09-29) —
alle Trails gleich breit.

Liste (4e): Filter-Chips „Alle", „bis S2", „Flowig", „Jumps" (Suche, „Alle/Meine/Von Buddys", „bis S2" und die Sortierung gibt es seit 0.32.0, #66 — `trail_list.dart`; der Filter gilt seit 0.33.0 auch auf der Karte, `TrailFilterChips` im Blatt „Ebenen"; „Flowig"/„Jumps" seit 0.34.0, #72 — sie filtern über die angezeigten zwei Merkmale, nicht über jede einzelne Nennung); Zeile als
Karte mit Farbstreifen links, Zahlen in Mono, Schild und Symbole rechts.
Blatt (4f): Name, „Du und 2 Buddys", Charakter-Chips mit Anzahl, drei
Kacheln Länge / Höhe / S-Grad oder Spanne, „Deine Einschätzung".
**Seit 0.49.0 (#101, Rework E8)** darunter eine zweite Reihe BEWERTUNG
(Sterne in der Marke, Median und Anzahl; verblasst, solange der eigene
Trail nicht bewertet ist) und ZUSTAND (Wort und Alter; eine jüngere
unbestätigte Angabe verblasst mit „zu bestätigen"), je mit Tipp auf die
Einzelstimmen. Eine unbestätigte Meldung steht als verblasster Chip
neben der bestätigten; unten „Hinweis schreiben" (Lime) und „Melden"
nebeneinander, „Karte" darunter. Linienart auf der Karte und die Wörter
in der Liste kommen als eigener Schritt.

## 8. Screens (Turn 1g–1l)

- **Login (1g):** Logo, Wortmarke, „Trails teilen — nur mit deinen
  Buddys.", linksbündig.
- **Trail-Blatt (1i):** Titel in Großbuchstaben, drei Kennzahl-Kacheln,
  Höhenprofil in Trail-Richtung, Hinweis eines Buddys als gelb umrandete
  Karte, unten „Hinweis schreiben" (Lime) + „Karte". **Gebaut seit
  0.39.0** (`trail_sheet.dart`: `_MetricTiles`, `_Panel`;
  `trail_notes.dart`). Unter dem Titel die Beziehung („Du und 2 Buddys
  (Jan, Mira).", 4f). Kacheln LÄNGE / HÖHE (↓ Hm) / S-GRAD (Median in der
  Marke, darunter Spanne und Anzahl „S1–S3 · 4×"); der ganze Satz
  („↓ 420 Hm · ↑ 35 Hm", „S2 · S1–S3 · 4 Einschätzungen") steht als
  Beschriftung für Bildschirmleser an der Kachel, die S-Grad-Kachel
  öffnet wie der frühere Chip die Einschätzungen. Das Ø-Gefälle steht
  im Profil-Untertitel. Charakter und Meldung bleiben Chips über den
  Kacheln. „Mein Beitrag" steht als Textknopf unter „Deine
  Einschätzung" (4f bearbeitet den Beitrag direkt im Blatt; der Dialog
  kann mehr — Name, Status, Sichtbarkeit). Das S-Grad-Schild neben dem
  Titel (4f) steht seit 0.42.0 (Schritt 6a).
- **Trail-Liste (1j):** Karten mit 14 px Radius, Farbstreifen links =
  Beziehung (seit 0.42.0: Schwierigkeit), rechts ein Wort in der Farbe (NEUER HINWEIS, MEIN, GESPERRT,
  AUSGANGSKORB …), Zahlen in Mono. **Gebaut seit 0.38.0**
  (`trails_screen.dart`, Regel `trailRowTags` in `trail_list.dart`), mit
  drei Abweichungen: Das Wort steht unter den Zahlen, nicht rechts —
  rechts stehen seit 4e Schild und Charakter-Symbole, beides zusammen
  liefe auf 360 dp über. Ein Zustand (wartet, gemeldet, neuer Hinweis)
  schlägt die Beziehung; nur ohne Zustand steht „MEIN · 2 BUDDYS" bzw.
  die Namen (höchstens zwei, Alias vor Name). Die Karten sind flach
  (`elevation: 0`) mit Rand in der Linienfarbe; der gelbe Rahmen trägt
  den neuen Hinweis, eine Tönung der Zeile gibt es nicht mehr. Die
  Abschnitte „Meine Trails" / „Von Buddys" bleiben (der Entwurf hat
  keine) — im Stil der Abschnitte aus 1k. Kopf: „TRAILS" groß, rechts
  „Anzahl · Gesamtlänge" in Mono.
- **Buddys (1k):** Nach dem Annehmen eine Karte „Mit Jan verbunden" mit
  drei Zahlen (gemeinsam / neu von / neu für) statt einer Leiste;
  Avatare als abgerundetes Quadrat (12 px).
  Gebaut in 0.40.0 (`friends_screen.dart`) mit vier Abweichungen: Die
  Karte bleibt, bis man sie schließt (eine Leiste war nach acht Sekunden
  weg). „vor 2 Stunden" an der Anfrage fehlt — die App kennt den
  Zeitpunkt einer Anfrage nicht. Statt des Chevrons stehen rechts Alias
  und Entfernen: Eine Seite je Buddy gibt es nicht, ein Pfeil ins Leere
  wäre eine falsche Zusage. Das Einladen, im Entwurf nicht zu sehen,
  steht oben rechts (ohne Buddys zusätzlich als Knopf in der Liste).
  „n gemeinsam" zählt dieselben Trails wie „gemeinsam" in der Karte
  (`sharedTrailCounts`). Die Avatarflächen (`AppColors.avatarFills`:
  Blau, Gelb, Pink, Lila, fest je Nutzer-id) tragen dunkle Schrift in
  beiden Modi; Lime bleibt dem eigenen Avatar, denn Lime heißt „mein".
- **Profil (1l):** Kopf mit Avatar und drei Zahlen, darunter Zeilen mit
  Wert rechts (Benachrichtigungen, Erscheinungsbild …).
  Gebaut in 0.41.0 (`profile_screen.dart`): Die Zeilen sind Karten mit
  Symbol auf eigener Fläche, der Wert steht UNTER dem Titel wie im
  Entwurf. Benachrichtigungen, Erscheinungsbild und Konto sind eigene
  Unterseiten (`/profile/notifications`, `appearance`, `account`); dazu
  kommt eine siebte Zeile „Über TrailBuddy" (`/profile/about`), die der
  Entwurf nicht hat — Datenschutzerklärung, Impressum und Lizenzen
  müssen aus der App erreichbar bleiben. Abmelden steht oben rechts,
  „Konto löschen" am Ende der Seite „Konto". Die drei Zahlen zählen
  eigene Trails (belegt oder wartend), angenommene Buddys und Fahrten
  auf dem Gerät; was nicht geladen ist, fällt weg statt als 0
  dazustehen, im Web gibt es keine Fahrten.

## 9. Bewegung (Turn 1p–1t)

Jede Animation ist aus, wenn das System es will
(`MediaQuery.disableAnimations`).

| | Was | Dauer (Entwurf) |
|---|---|---|
| 1p Splash | Linie zeichnet sich (dashoffset 300 → 0 bis 60 %), Punkt springt (0 → 1,3 → 1 ab 55 %), Wortmarke blendet von 8 px unten ein (50–80 %) | einmal, ~1,2 s |
| 1q Loader | die Serpentine läuft (dashoffset 300 → −300, linear) | 1,6 s, Schleife |
| 1r Fahrt läuft | Ring um den Positionspunkt skaliert 1 → 3,2 und blendet von 0,7 aus; die Spur wächst | 1,6 s, Schleife |
| 1s Buddy verbunden | zwei Spuren laufen zu einer zusammen, dann der Punkt | 3 s |
| 1t Neuer Hinweis | der gelbe Leuchtrand atmet (2 → 6/14 px Schein) | 1,8 s, nur solange ungesehen |

Gebaut in 0.45.0 (`lib/core/widgets/motion.dart`, `start_splash.dart`;
die Keyframes stehen je als pure Funktion daneben — `splashAt`,
`loaderSegments`, `ridePulseAt`, `connectMergeAt`, `glowAt` — und sind
ohne Pixel geprüft, `test/core/motion_test.dart`). Bei reduzierter
Bewegung steht überall das Endbild, kein Takt läuft. Fünf Abweichungen:

- **1p liegt ÜBER der App, nicht vor ihr**: Anmeldung, Karte und Trails
  laden darunter schon, der Splash kostet also keine eigene Wartezeit
  (1,2 s, dann 0,25 s Ausblenden, einmal je Start). Ein Tipp überspringt
  ihn; bei reduzierter Bewegung gibt es ihn gar nicht — ein stehendes
  Logo vor der App wäre nur eine Pause. Grund ist der des Modus, nicht
  immer das Dunkel des Entwurfs. Der Test-Harness schaltet ihn ab
  (`startSplashEnabledProvider`).
- **1q ersetzt nur die ganzseitigen Kreisel.** In Knöpfen und Zeilen
  bleibt der kleine Kreisel: Eine Serpentine in 16 px liest niemand.
- **1r**: Der Ring hat die Farbe des Positionspunkts; die Markerfläche
  wächst während der Fahrt auf das 3,2-Fache, sonst würde er
  beschnitten. „Die Spur wächst" tat sie schon — mit jedem Punkt.
- **1s läuft einmal**, 3 s, wenn die Karte „Mit … verbunden" erscheint:
  erst auseinander, dann eine Spur, dann der Punkt. Die Vorschau im
  Entwurf läuft hin und her, das wäre auf einer Karte, die man liest,
  Unruhe. Zusammen trägt die Spur die Marke (Lime heißt „mein").
- **1t atmet nur in der Liste**, auf der Karte steht der Rand still:
  Eine atmende Linie hieße in MapLibre, die Linien in jedem Bild neu zu
  übertragen — genau die Last, die 0.44.0 abgeschafft hat.

## 10. Nicht bauen

Nachrichten (1m, #34 Rest), Fahrt-Zusammenfassung mit Airtime (1n, #36)
und Routing zum Trailkopf (1o, #35) sind Entwürfe für später.

## 11. Umsetzung

| PR | Inhalt | Version |
|---|---|---|
| #74 | Tokens, Theme hell/dunkel, Schriften, „Erscheinungsbild" | 0.28.0 |
| 2 | Logo, App-Symbole, Statusleisten-Symbol, Login | 0.29.0 |
| 3 | Hülle und Karte (Turn 3) | 0.30.0 |
| 4 | Offline-Kacheln: eine Regel (Turn 2) | 0.31.0 |
| 5a | Trail-Liste (1j, 4e ohne Schild) | 0.38.0 |
| 5b | Trail-Blatt (1i, 4f ohne Schild) | 0.39.0 |
| 5c | Buddys (1k) | 0.40.0 |
| 5d | Profil (1l) | 0.41.0 |
| 6 | S-Grad als Form, Charakter, Pisten-Brille (Turn 4, Schema) | Charakter 0.34.0 (#72) |
| 6a | S-Grad-Schild, Farbe = Schwierigkeit (Karte, Liste, Schild) | 0.42.0 |
| 6b | Schild mit Charakter am Trailanfang auf der Karte | 0.43.0 |
| 6c | Glatte Linien, Name entlang der Linie (Betreiber-Wunsch) | 0.44.0 |
| 7 | Animationen (Turn 1p–1t) | 0.45.0 |
