# TrailBuddy — Arbeitsregeln

Flutter-App (Android + Web): Mountainbike-Trails, die man mit seinen Buddys
teilt. Supabase-Backend (Auth + PostgreSQL mit PostGIS, Freigabe-Regeln
komplett über RLS in `supabase/schema.sql`), Riverpod ohne Codegen,
go_router, deutsche UI-Strings direkt im Code. Schwesterprojekt von
PilzBuddy (`MacBuchi/pilzbuddy`): Stack, CI-Muster und viele Bausteine sind
von dort kopiert (Stand 1.213.0), bewusst kopiert und NICHT als gemeinsames
Paket herausgezogen — erst wenn TrailBuddy steht, sieht man, was wirklich
gleich geblieben ist.

**Das Konzept ist maßgeblich:** `docs/konzept-trails.md` (Trail ≠ Fahrt ≠
Aufzeichnung, besitzerlose Trail-Kennung, Sichtbarkeit nur aus eigenen und
Buddy-Beiträgen, stiller globaler Abgleich, das Community-Tor, die
Entscheidungen des Betreibers in Abschnitt 10, die Regel für den
dezentralen Weg in Abschnitt 12). Die Schwellen des Abgleichs sind gemessen
(`docs/trail-abgleich-messung.md`), nicht geraten. Wer Code ändert, der dem
Konzept widerspricht, ändert das Konzept im selben PR — oder den Code.
Das Rework vom 2026-09-30 (`docs/konzept-rework.md`, #109) plant die
nächsten Schritte am Modell; gebaut wird es Schritt für Schritt, und
jeder zieht `konzept-trails.md` nach. Die Einführung (Tour, Kurzanleitung,
„Entdecken“; `docs/konzept-onboarding.md`, #137) übernimmt PilzBuddys
Mechanik aus #350/#596 und schneidet den Inhalt für Trails neu — sechs
gestapelte PRs, die Regeln für Anker, Merker und Beispiele stehen dort.
Offizielle Trails (#13) sind eine getrennte Ebene mit eigenem Konzept:
`docs/konzept-offizielle-trails.md`. Gebaut von `official-trails.yml`
(`tool/official_trails.py`, Quellen in `tool/official/sources.json`)
auf den Branch `official-trails-data` — nie als Release (die
Update-Prüfung nähme es im Vorab-Kanal für eine App-Version). Dort
liegen nur öffentliche Daten Dritter, keine Nutzerdaten.

**Das Aussehen steht in `docs/design/README.md`** (Farben hell/dunkel,
Schriften, Logo, Offline-Kachel-Regel, Kartenleisten, S-Grad als Form,
Bewegung, Reihenfolge der Umsetzung). Wie beim Konzept: Wer im Code davon
abweicht, ändert die Datei im selben PR. Alle App-Symbole erzeugt
`tool/brand_icons.py` aus EINEM Pfad (Logo „Serpentine"); nie ein Symbol
von Hand tauschen.

**Nichts Privates in dieses Repo — es ist öffentlich.** Keine absoluten
Pfade des Betreiber-Rechners, keine privaten Mailadressen, keine GPX- oder
Zip-Dateien (eine Fahrt beginnt an der Haustür), keine Koordinaten in
Berichten. `tool/private_info_check.py` prüft das in CI. Ausnahme ist nur,
was öffentlich sein MUSS (Impressum, Datenschutzerklärung).

`AGENTS.md` ist ein Symlink auf diese Datei (CI prüft das). Was für Claude in
`CLAUDE.local.md` steht, gehört für Codex in die persönliche
`~/.codex/AGENTS.md`, nie ins Repo.

## Workflow

- Kein direkter Push auf `main`: Feature-Branch → PR → CI grün → Squash-Merge.
  (Branch-Schutz und Squash-Vorgabe: Repo-Einstellungen, vom Betreiber.)
- **Conventional Commits** für Commit- und PR-Titel:
  `<typ>(<bereich>): <was>`, Typen `feat`, `fix`, `perf`, `refactor`,
  `docs`, `test`, `ci`, `build`, `chore`; der Bereich ist optional
  (`import`, `trails`, `map`, `auth`, `web`, `db` …). Der PR-Titel IST der
  Commit auf `main` (Squash-Merge, Vorgabe „Pull request title"), also
  zählt er, nicht die Commits auf dem Branch. Auf GitHub Englisch
  (Commits, PRs, Issues); Deutsch für UI-Strings, Nutzer-Doku und die
  Kommunikation mit dem Betreiber.
- **Semantic Versioning** in `pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`),
  abgeleitet aus dem Typ des PRs — dieselbe Praxis wie PilzBuddy:
  - `feat` ⇒ MINOR (`0.1.1 → 0.2.0`), `fix`/`perf` ⇒ PATCH
    (`0.1.0 → 0.1.1`). Andere Typen bumpen nur, wenn sie ins Binary
    gehen (Version Guard), dann als PATCH.
  - `BUILD` steigt bei JEDEM Bump um eins und nie zurück — Android
    lehnt eine APK mit kleinerem `versionCode` ab.
  - **Vor 1.0.0** ist MAJOR 0 und ein Bruch trotzdem nur MINOR. 1.0.0
    kommt mit dem Play-Store-Eintrag (Konzept 10, Punkt 7), nicht mit
    einer Schemaänderung: Ältere Clients schützt
    `minimum_supported_version`, nicht die Versionsnummer.
  - Mehrere Themen in einem PR: der höchste Typ entscheidet.
- **Version Guard** (ci.yml): Code-Änderung ohne Bump in `pubspec.yaml`
  blockiert den Merge, sobald es einen Release-Tag gibt. Ausgenommen sind
  `*.md` (außer `CHANGELOG.md`, die liegt als Asset im Binary), `.github/`,
  `tool/`, `supabase/`, `docs/`. Er prüft, DASS gebumpt wurde; WELCHE Stelle
  nach den Regeln oben, ist Sache des PRs.
- **Changelog**: `CHANGELOG.md` wird in der App unter „Was ist neu" gezeigt.
  `test/changelog_test.dart` verlangt die pubspec-Version darin. Erlaubte
  Auszeichnung wie in PilzBuddy: `##`, kursive Metazeile, Absätze,
  `-`-Listen, `**fett**`, nackte URLs.
- **Release-Kanäle** (release.yml): Ein Bump auf `main` taggt `v<version>`
  und baut die signierte APK als **Prerelease**. **Kein Keystore, kein
  Tag**: Fehlen die Secrets `ANDROID_KEYSTORE_*`, tut der Workflow sichtbar
  nichts (Run-Summary) — und zwar VOR dem Taggen, damit kein Tag ohne
  Release entsteht. **`promote.yml`** (von Hand) macht ein Prerelease
  zu „latest" (erst dann meldet sich die App) und baut aus DEMSELBEN Tag
  die Web-App samt Rechtsseiten auf `gh-pages` (Pages: Branch
  `gh-pages`, Wurzel). Ohne Beförderung gibt es kein Web — und keine
  erreichbare Datenschutzerklärung. **Pages unterscheidet Groß- und
  Kleinschreibung**: Das Repo heißt deshalb `trailbuddy` (klein), passend
  zu `--base-href /trailbuddy/` und den Links in `AppInfo`; GitHub, API
  und raw.githubusercontent.com sind davon nicht betroffen.
  **`preview.yml`** deployt jeden Merge auf `main` als Web-Vorschau nach
  `MacBuchi/trailbuddy-preview` (→ https://macbuchi.github.io/trailbuddy-preview/,
  der Link „Entwicklungsversion öffnen" im Profil). Eigenes Repo, weil
  `promote.yml` den Pages-Branch je Beförderung neu anlegt und weil ein
  eigener Origin einen eigenen `localStorage` hat (Sitzung, Einstellungen)
  — deshalb dort neu anmelden. `--dart-define=PREVIEW_BUILD=true`
  schaltet den Streifen „Entwicklungsstand" und dreht den
  Profil-Verweis um; `--base-href /trailbuddy-preview/` muss zum Link
  passen (falsch ⇒ weiße Seite ohne Fehler). Zugang ist ein Deploy Key
  (`PREVIEW_DEPLOY_KEY`, öffentlicher Teil im Vorschau-Repo mit
  Schreibrecht), kein PAT; fehlt er, sagt es die Run-Summary mit den
  Schritten. `test/release_workflow_test.dart` wacht über Flag, base-href
  und Ziel-Repo.
- **Schema Dry Run** (ci.yml, Pflicht-Check): lokaler Supabase-Stack auf
  dem Runner (`supabase/config.toml`, Portblock **5452x**), beide Wege —
  Bestand (Basis-Schema + neue Patches) und Frischinstallation (leere
  Datenbank, `db_migrate.sh` spielt `schema.sql` ein — derselbe Zweig wie
  beim ersten Lauf gegen das leere Live-Projekt) —, danach
  `tool/schema_check.sh` (App-Queries gegen das Schema),
  `tool/matcher_check.sql` (der Abgleich mit echten Linien) und
  `tool/auth_reset_check.sh` (Auth-Flows gegen echtes GoTrue).
  Ohne Docker lokal: `tool/schema_local_test.sh` (Postgres + PostGIS,
  Frischinstallation; mit `TB_BASE_SCHEMA=<schema.sql von main>` und
  `TB_PATCHES` der Bestandsweg, `TB_SEED`/`TB_AFTER` für Daten vor und
  Prüfungen nach dem Patch, `TB_DUMP` für den Schema-Vergleich beider
  Wege). PostgREST und GoTrue sieht erst der Dry Run in CI.
  `auto_expose_new_tables = false`: Ein vergessener Grant fällt im Dry Run
  auf, statt still von der Vorgabe ersetzt zu werden.
- **Schema Check** (ci.yml, `needs: schema-dry-run`): erst danach wird die
  Live-Datenbank angefasst — `db_migrate.sh` spielt neue Patches ein (auf
  einem LEEREN Projekt vorher `schema.sql`; halb eingerichtet ⇒ Abbruch
  statt Raten), dann `schema_check.sh` gegen das Live-Schema. Braucht das
  Secret `SUPABASE_DB_URL` (Session-Pooler-URI inkl. Passwort). Der
  Release-Workflow wiederholt beides vor dem Bauen. **Nie Schema von Hand
  im Dashboard ändern** — der Weg ist immer ein `patch_NNN`.
- **Live-Projekt wach halten** (`keepalive.yml`, Mo + Do): Der Free-Plan
  pausiert nach ~1 Woche ohne Zugriff. Der Lauf fährt `schema_check.sh`
  gegen live und ist damit zugleich Drift-Wächter. Wer ihn abschaltet,
  riskiert eine tote App. Das Projekt liegt im Zweitkonto des Betreibers
  (Konzept, Punkt 9; wem Konto und Mails gehören: DocuHub).
- **Patches**: `supabase/patch_NNN_*.sql` + Struktur in `schema.sql` + Eintrag
  in der Saat-Liste, alles im selben PR; ein eingespielter Patch wird nie
  wieder angefasst (`tool/patch_guard.sh`). Baseline ist 0: Es gibt keine
  von Hand eingespielten Patches.
- **Supabase-Konfiguration der App**: `lib/core/supabase_config.dart` liest
  `SUPABASE_URL`/`SUPABASE_KEY` aus `--dart-define`, Vorgabe ist das
  Live-Projekt (Publishable Key ist öffentlich; niemals den
  service_role-Key). Gegen den lokalen Stack per `--dart-define` bauen.

## Technik-Notizen

- **Der Abgleich läuft in der Datenbank** (`contribute_recording`,
  Security Definer): Korridor 15 m, beidseitige Deckung ≥ 0,8, Fréchet auf
  den Punkten IM Korridor ≤ 2·d, Mindestlänge 150 m, Abtastung 5 m —
  gemessen an 584 Tracks. Nur „gleich" verschmilzt; Teil und Gabel werden
  neuer Trail plus unsichtbare Kante (`app_internal.trail_overlaps`). Die
  RPC gibt nur die Trail-Kennung zurück, nie ob sie neu ist. Tageslimit
  500 Aufzeichnungen je Nutzer in 24 h (Patch 006, gemessen mit
  `tool/limit_measure.sql`); `attach_elevation` zählt nicht mit. Das
  Python-Werkzeug `tool/trail_match.py` ist die Referenz und läuft mit
  `--self-test` in CI; Werkzeug und SQL kommen bei Schwellenänderungen im
  SELBEN PR.
- **`trails` hat keinen Client-Grant.** Alles Sichtbare kommt aus
  `recordings_visible` (Sicht mit `security_invoker`) und `trail_details`,
  gruppiert im Client (`buildTrails`). Eine Aggregation über alle Nutzer
  darf es nicht geben (Konzept 12).
- **Importregel**: < 8 km und Verlust > 2 × Gewinn ⇒ Trail, sonst Fahrt.
  Eine Fahrt geht über die Schere im Import auf die Karte ins
  Zerlege-Blatt (#29, seit 0.20.0). Ohne Zeiten oder mit > 60 km/h
  Median ⇒ `planned`. **Fahrdatum** (#120, Patch 015, seit 0.58.0): Für
  eine geplante Datei trägt man im Import „Gefahren am …" ein (12 Uhr
  Ortszeit, höchstens heute; auch für die Schere, `SplitRequest.rodeAt`).
  Sie bleibt `planned` (Qualität 0,1, die Linie ist gezeichnet), aber
  `recorded_at` trägt das Datum — und „`planned` MIT Datum" IST
  „gefahren": `has_ridden` und Schritt 8 von `contribute_recording`
  zählen sie, auf dem Gerät `TrailRecording.ridden` (Spiegel für
  `hasRidden`, `onlyPlanned`, `allPlanned` und den Fake). Keine neue
  Quelle — ältere Clients kennen keinen neuen Wert; Patch 015 leert
  vorsorglich jedes Datum an bestehenden `planned`-Zeilen.
  `matcher_check.sql` Block 24.
- **Höhen** (Patch 002, #14): `trail_recordings.ele` trägt eine Höhe je
  Punkt der Linie oder ist leer — ganz oder gar nicht, der Check
  `trail_recordings_ele_check` hält Anzahl und Bereich fest. Vier Dinge,
  die man wissen muss:
  - **Die RPC entfernt doppelte Punkte SAMT Höhe** (Fensterfunktion statt
    `st_removerepeatedpoints`, das nur die Linie kürzte und die Höhen
    danach versetzt neben ihr herlaufen ließe). `matcher_check.sql`
    Block 16 prüft genau das.
  - **Die Vereinfachung vor dem Hochladen rechnet dreidimensional**
    (`simplify`, senkrechte Toleranz `kSimplifyVerticalM` = 2 m,
    gemessen): Ein gerades,
    welliges Stück verlöre sonst seine Wellen. Das Import-Blatt rechnet
    deshalb auf der VEREINFACHTEN Spur, damit es dieselbe Zahl sagt wie
    danach das Trail-Blatt.
  - **Hysterese `kElevationThresholdM` = 3 m**, gemessen an 578 Tracks
    (`docs/trail-abgleich-messung.md`, Abschnitt Höhen), Spiegel in
    `tool/elevation_measure.py` mit denselben Testvektoren; Werkzeug und
    Dart im selben PR ändern. Die Importregel „Abstieg > 2 × Anstieg"
    rechnet bewusst ROH — so ist sie gemessen.
  - **Angezeigt wird in Trail-Richtung, aus der besten Aufzeichnung MIT
    Höhen** (`Trail.elevation`), nicht zwingend aus der besten Linie.
    Ohne Höhen sagt das Blatt „Keine Höhenangaben", nie „0 Hm".
    Aufzeichnungen vor 0.3.0 haben keine.
  - **Nachtragen** (#16, Patch 003): Dieselbe Datei noch einmal
    importiert legt keine zweite Aufzeichnung an. Der Import sucht die
    gespeicherten Punkte der Reihe nach in der Datei (sie SIND
    Originalpunkte; neu vereinfachen ergäbe seit 0.3.0 eine andere
    Linie), Anfang und Ende müssen die der Datei sein
    (`elevation_backfill.dart`). `attach_elevation` prüft auf dem Server
    Punkt für Punkt ≤ 5 cm, nur eigene Aufzeichnungen ohne Höhen,
    überschreibt nie, zählt nicht ins Tageslimit. Schon mit Höhen
    Beigesteuertes steht im Import gesperrt da.
- **Schwierigkeit** (#14, Teil 2): Singletrail-Skala S0–S5 je Beitrag,
  angezeigt als Median (bei Gleichstand der SCHWERERE — im Zweifel die
  Warnung), Spanne und Anzahl. Die Beschreibungen stehen an EINER Stelle
  (`singletrail_scale.dart`, eigene Kurzfassungen, keine Zitate) und sind
  überall aufrufbar, wo man einen Grad angibt: Auswahl im Beitrag und
  Chips im Blatt. Die Einschätzung im Blatt gibt es nur für selbst
  belegte Trails (Konzept 3: ohne Beleg kein Beitrag).
- **Charakter** (#72, Patch 009, seit 0.34.0): Mehrfachwahl je Beitrag
  (`trail_details.traits`, sieben Merkmale: Flowig, Jump-Line, Verblockt,
  Steil, Uphill, Naturtrail, Verbindung), ersetzt die Einzelwahl „Art".
  Angezeigt die höchstens zwei häufigsten über alle sichtbaren Beiträge
  (`Trail.topTraits`, Gleichstand nach Reihenfolge von `TrailTrait`);
  Beschreibung und Symbol an EINER Stelle (`trail_traits.dart`, Symbole
  farblos — die Farbe gehört der Schwierigkeit). Die Filter „Flowig"/„Jumps"
  prüfen die ANGEZEIGTEN zwei, nicht jede Nennung. Vier Dinge, die man
  wissen muss:
  - **`kind` bleibt vorerst stehen** (erweitern → ausliefern →
    entfernen): Clients bis 0.33.0 lesen und schreiben weiter nur sie,
    ihre Änderungen erreichen `traits` nicht. Die App schreibt `kind` nicht
    mehr (`toRow`), sonst überschriebe sie, was ein alter Client liest.
    Entfernt wird die Spalte in einem eigenen Patch, wenn
    `minimum_supported_version` über 0.33.0 steht.
  - **Patch 009 übernimmt die alte Art** (flow → flowy, jump → jumps,
    tech → rocky, natural, connection) und `fromJson` fällt auf dieselbe
    Zuordnung zurück, wenn `traits` fehlt (Zwischenspeicher, Ausgangskorb
    von vor 0.34.0).
  - **Unbekannte Merkmale fallen beim Lesen weg**, statt zu werfen — ein
    neueres Merkmal darf eine ältere App nicht umwerfen. Der Check in der
    Datenbank lässt nur die sieben zu.
  - **Im Zerlege-Blatt seit 0.35.0**, dieselben Chips je Kandidat
    (`TrailTraitChip`). Die Merkmale KOMMEN DAZU (`adoptDetails`), nichts
    wird weggenommen: Das Blatt zeigt den bisherigen eigenen Charakter
    nicht, und verschmilzt der Server die Spur mit einem Trail, den ich
    schon beschrieben habe, soll eine Abfahrt meine Angabe nicht still
    ersetzen. Der Grad dagegen wird gesetzt (ein Wert, gerade gefahren).
- **Orte auf der Karte** (#12, `lib/features/map/poi*.dart`): seit
  0.18.0 als fertige Dateien vom EIGENEN Kartenhost (Konzept
  `docs/konzept-offline-karten.md` 3.4, Weg 3 — Betreiber, 2026-09-28),
  vorher live von `overpass-api.de`. `poi-data.yml` (monatlich am 2.,
  von Hand mit `plan`/`publish`) liest die Geofabrik-Extrakte aller
  Länder im Kartenrahmen (seit #73: DACH, Liechtenstein, Norditalien,
  Ostfrankreich, Benelux, Dänemark, Südschweden, Tschechien, Polen,
  Slowakei, Ungarn, Slowenien, Kroatien) mit `osmium`, filtert jedes
  gleich nach dem Download vor (eins nach dem anderen, sonst reicht die
  Platte nicht), `tool/poi_extract.py` behält die 15 Arten IM RAHMEN
  (`--bbox`, `POI_BBOX` = `DACH_BBOX` der Karte = Rahmen der Übersicht,
  ein Test hält alle drei zusammen) und schreibt je Rasterzelle und Gruppe EINE Datei
  (`pois-<build>/<zeile>_<spalte>.<gruppe>.json`) plus das Manifest
  `pois.json`, das den Bau und die Zellen mit Inhalt nennt; Upload nach
  R2 neben das Archiv, dann Rücklesen der öffentlichen Kopie mit
  Origin-Header und Byte-Vergleich je Gruppe. Fünf Dinge, die man wissen
  muss:
  - **Warum nicht aus den Kacheln:** Protomaps schreibt Hütte,
    Gasthaus, Trinkwasser & Co. erst ab Zoom 15 in die Kacheln (in der
    Quelle nachgelesen, 2026-09-28), unser Archiv endet bei 13, und der
    Stil zeigte sie ohnehin erst ab 16 und nur als Text. Ein
    Zoom-15-Archiv wäre ein Vielfaches je gespeichertem Bereich.
  - **Die Arten stehen ZWEIMAL** — `PoiKind` in `poi.dart` und
    `tool/pois/kinds.json` für das Werkzeug; `test/map/poi_test.dart`
    hält Reihenfolge, Regeln und Gruppen zusammen. Die ERSTE passende
    Art gewinnt (Biergarten vor Gasthaus: `biergarten=yes`); Parkplätze
    ohne `access=private/no`; Ladesäulen nur mit `bicycle=yes`.
  - **Das Manifest gilt je App-Lauf, eine Zelle je Gruppe wird einmal
    gefragt**, und nur, wenn das Manifest sie nennt — eine leere Zelle
    kostet keine Anfrage. Erst ab Zoom 12, Raster 0,1° × 0,15° (dasselbe
    `floor()` auf denselben Doubles in Dart und Python); der Filter ist
    gerätelokal (`Settings.poiGroups`, Vorgabe nur „Wasser"). Ist alles
    aus, geht KEINE Anfrage raus. Die kleinen Dateien liegen im
    Edge-Cache (anders als das Archiv, #55); kein neues Netzziel, der
    Host steht schon in der Datenschutzerklärung.
  - **Ohne veröffentlichten Bau gibt es keine Orte**: 404 auf das
    Manifest heißt „Orte gerade nicht erreichbar", bis `poi-data.yml`
    einmal auf `main` gelaufen ist. Ein Bau mit unter 100 000 Orten
    wird nicht veröffentlicht (kaputter Extrakt); der vorige Bau bleibt
    einen Lauf lang liegen.
  - Der Test-Harness hängt `FakePoiSource` ein, weil die Karte beim
    Einpassen auf einen Trail über Zoom 12 liegt. Die Nadeln liegen über
    den Trail-Linien (Fassade) und tragen nie eine der Trail-Farben; das
    Kuchenstück ist gezeichnet (`PoiGlyph`). Der Detailfilter
    (`Settings.poiHiddenKinds`) blendet nur aus, geladen wird je Gruppe.
- **Farbe = Schwierigkeit** (seit 0.42.0, Betreiber 2026-09-29): Linie
  auf der Karte, Streifen in der Liste und S-Grad-Schild tragen die
  Pistenfarbe des Medians (`GradePalette`: S0 grün, S1 blau, S2 rot, ab
  S3 schwarz — im Dunklen hell —, ohne Einschätzung grau; ab S4 der
  SAUM gestrichelt, seit 0.51.0 — die Linie selbst trägt den bestätigten
  Zustand: durchgezogen, bröckelig, gestrichelt, gestrichelt und
  verblasst, `trailLineStyleOf`; `MapViewPolyline.borderDash` ist das
  eigene Muster des Saums, in flutter_map eine eigene Linie darunter). **Uphill schlägt die Stufe**: Steht Uphill
  unter den angezeigten zwei Merkmalen, trägt der Trail Petrol und das
  Schild einen Pfeil statt der Form (`trailColorOf`/`isUphill` in
  `grade_shield.dart`, eine Regel für Karte, Streifen, Schild). Wem ein Trail gehört, zeigt KEINE Farbe
  mehr, nur das Wort. Gemeldet und neuer Hinweis liegen als Leuchtrand
  um die Linie (gemeldet schlägt Hinweis), die Linie behält ihre Stufe.
  Die Karte nimmt immer `AppColors.mapGrades` (hell), die App
  `palette.grade`. `docs/design/README.md` Abschnitt 1–2 und 7.
- **Glatte Linien und Namen am Trail** (seit 0.44.0, Betreiber
  2026-09-29): Die Trail-Linien werden fürs BILD mit Chaikin geglättet
  (`line_smoothing.dart`, drei Durchgänge, NUR an Ecken ab 12° und
  Abschnitten ab 2 m, Anfang und Ende fest, einmal je Trail im
  Karten-Screen gemerkt); Abgleich, Länge, Höhen, Deckung und
  Zerlegung rechnen weiter mit den Originalpunkten, die Trefferprüfung
  mit der geglätteten Linie. MapLibre zeichnet Linien mit runden Ecken
  (`RoundPolylineLayer` — das Paket setzt kein `line-join`, spitz auf
  Gehrung sah jede Kehre wie ein Knick aus). Der Name steht ab Zoom 14
  (`kLineLabelMinZoom`, 256er) an der Linie: MapLibre als Symbol-Ebene
  `symbol-placement: line` über allen Linien (`LineLabelLayer`, Kollision
  und Wiederholung macht MapLibre), **Schrift `noto-sans-medium`** — der
  Glyphen-Ordner, nicht „Noto Sans Medium" (der Stil wird umgeschrieben,
  diese Ebene nicht; der falsche Name lässt den Text still weg, ein Test
  prüft den Ordner). flutter_map kann keinen Text auf einem Pfad: einmal
  in der Mitte, gedreht, nie kopfüber (`lineLabelAnchor`).
  **Flüssig bleibt es, weil nichts unnötig übertragen wird** (gemessen
  2026-09-29, 200 Trails à 2 km): Das Glätten sind wenige ms einmal je
  Laden; teuer war die Übertragung an MapLibre (GeoJSON-Text, 30–60 ms auf
  dem Rechner), und die lief bei JEDEM Neuaufbau des Karten-Screens —
  jede Positionsmeldung, jeder Kamera-Stillstand. `MapLibreLineCache`
  gibt für eine unveränderte Gruppe (Stil, DIESELBEN Punktlisten, Namen)
  die alten Ebenen-Objekte zurück, das Paket überträgt dann nichts
  (0,2 ms). Die Glättung nur an Ecken hält die Punkte beim 2,5-Fachen
  statt beim 7,7-Fachen. Wer die Punktlisten je Aufbau neu anlegt, hebt
  den Cache aus — der Test in `trail_line_look_test.dart` hält es fest.
- **Bewegung** (Design 1p–1t, seit 0.45.0, `lib/core/widgets/motion.dart`,
  `start_splash.dart`): Splash, Loader, Ring um den Punkt während der
  Fahrt, „zwei Spuren werden eine" beim Verbinden, atmender Rand bei
  neuem Hinweis (nur in der Liste — auf der Karte hieße Atmen, die
  Linien je Bild neu an MapLibre zu übertragen). Jede Animation liest
  `reduceMotion(context)` und zeigt dann das Endbild ohne Takt; die
  Keyframes stehen als pure Funktionen daneben und sind ohne Pixel
  geprüft. **Kurveneingänge klemmen**: `(1 − 0,7) / 0,3` ist in
  Gleitkomma 1,0000000000000002, und `Curve.transform` wirft darauf
  (im Test gefunden). Der Splash liegt ÜBER der App, immer im selben
  `Stack` — fiele der nach dem Splash weg, hinge die App um; der Test
  prüft das an einem Kind OHNE GlobalKey (mit einem wäre die Gegenprobe
  grün geblieben). Der Harness schaltet ihn ab
  (`startSplashEnabledProvider`), sonst schluckte er die ersten Tipps
  jedes Flow-Tests.
- **Link zur Quelle** (#103, seit 0.48.0, Patch 012,
  `trail_link.dart`): `trail_details.link`, nur https ohne Query und
  Fragment — `sanitizeLink` in der App, `trail_details_link_check` in der
  Datenbank, der Fake spiegelt beides. Der Import nimmt `<link href>` der
  Spur, sonst aus `<metadata>`, über `linkFromFile` (ohne Gerätehersteller
  und Tourenportale, `kLinkIgnoredHosts`) und übernimmt ihn wie den Namen
  nur in einen Beitrag ohne Link (`adoptDetails`, `ContributeJob.link`).
  Das Blatt zeigt den Host (`linkHost`), geöffnet wird extern; die App
  ruft ihn nie ab. **Jeder, der `TrailDetails` neu baut** (Dialog, Fake),
  muss den Link mitgeben — sonst löscht Speichern ihn still.
  `matcher_check.sql` Block 22.
- **Beitrag löschen** (seit 0.46.0, Patch 010, `withdrawContribution`
  im Trail-Blatt): `withdraw_contribution(trail_id)` löscht eigene
  Aufzeichnungen, eigene Hinweise und den eigenen Beitrag in EINER
  Transaktion, Security INVOKER (die RLS erlaubt jede der drei Löschungen
  ohnehin). Einzeln aus der App ginge es nicht: Fällt der Beitrag zuerst,
  sagt `contributor_shares` ohne Zeile „teilt", und ein privater Beitrag
  läge kurz offen. Den leeren Trail holt `sweep_orphan_trails`
  (nächtlich). Kein Ausgangskorb — ohne Netz scheitert es sichtbar; und
  kein Knopf, solange ein eigener Beitrag im Korb wartet (der legte die
  Zeile beim Nachholen wieder an). `matcher_check.sql` Block 21.
- **Hinweise für Buddys** (#7, Patch 004 + 005, `trail_notes.dart`):
  freier Text zu einem Trail („Baum liegt quer"). Schreiben darf, wer
  den Trail SIEHT (`app_internal.can_see_trail`, dieselbe Regel wie
  `recordings_select`); sehen der Autor und seine direkten Buddys, die
  den Trail sehen, nicht bei „privat" (`contributor_shares`); entfernen
  jeder, der den Hinweis sieht („erledigt"); KEIN Bearbeiten (das Alter
  soll stimmen). Aufbewahrung 90 Tage (`sweep_old_notes`, pg_cron), der
  jüngste je AUTOR und Trail bleibt — je Autor, weil „der jüngste über
  alle Netze" eine Rechnung über Netzgrenzen wäre (Konzept 12); das
  Blatt zeigt von den alten nur den jüngsten (`Trail.notesShown`). Ein
  Hinweis eines Buddys jünger als `kFreshNoteDays` (7), der auf diesem
  Gerät noch nicht im Blatt zu sehen war (`Settings.seenNoteIds`), hebt
  den Trail hervor — gelber Rand auf der Karte, gelb umrandete Karte mit „neuer
  Hinweis" in der Liste; eigene zählen nie. Beim Melden bietet der
  Dialog einen Hinweis an. Entscheidungen des Betreibers
  vom 2026-09-28; `matcher_check.sql` Block 20 prüft RLS und Aufräumen.
- **Bewertung, Meldung, Zustand** (#101, Patch 013, seit 0.49.0;
  `trail_report.dart`, `trail_condition.dart`, Rework Abschnitt 9).
  Die Bewertung (1–5 Sterne) steht im Beitrag (`trail_details.rating`),
  angezeigt als Median (bei Gleichstand der höhere) mit Anzahl; ein
  eigener Trail ohne eigene Bewertung zeigt verblasste Sterne
  (`Trail.ratingOpen`). Meldung (bis 0.48.0 „Status") und Zustand
  (1–5) sind ein VERLAUF in `trail_reports`. Sieben Dinge, die man
  wissen muss:
  - **Melden darf, wer den Trail SIEHT** (`can_see_trail`), nicht nur,
    wer ihn belegt hat — Abweichung von Konzept 3, vom Betreiber
    entschieden. Geschrieben wird NUR über `report_trail` (Definer, kein
    insert-Grant): **`confirmed` legt der Server fest** — gefahren
    (`has_ridden`: nicht `planned`, oder `planned` mit Fahrdatum) oder
    `on_site`. `grants_check.sql`
    wacht darüber, dass kein Client-Grant `confirmed` frei wählbar macht.
  - **„Vor Ort" prüft nur das Gerät**: ≤ `kOnSiteMaxM` (200 m) zur
    angezeigten Linie, mit EINEM Fix nach Tipp auf „Ich bin vor Ort"
    (`positionFixProvider` — nie beim Öffnen). An den Server geht das
    Ja/Nein, gespeichert wird dort nur `confirmed`, nie die Position.
  - **Angezeigt** (`shownReportsOf`): die jüngste bestätigte, dazu
    verblasst die jüngste unbestätigte, wenn sie jünger ist. Karte,
    Liste und Filter „Gemeldet" folgen NUR der bestätigten
    (`Trail.status`). Der Zustand gilt dauerhaft (keine 90-Tage-Grenze
    für die Anzeige). Push nur für bestätigte Meldungen, nie für den
    Zustand (`push_on_report` ersetzt `push_on_status`).
  - **90 Tage Verlauf** (`sweep_old_reports`, pg_cron), die jüngste je
    Person, Trail, Art und Bestätigung bleibt länger — die angezeigte
    muss auch nach einem Jahr da sein. Das Blatt zeigt den Verlauf mit
    Name bzw. Alias (`BuddyNames.of`).
  - **Eine Fahrt setzt die eigene Meldung zum FAHRDATUM auf „offen"**
    (`contribute_recording` Schritt 8, `recorded_at`, gekappt auf jetzt),
    nur wenn es eine eigene Meldung gibt, sie älter ist und kein
    bestätigtes „offen" ist; nie bei `planned`. `report_trail` kappt
    `reported_at` ebenfalls auf jetzt — eine Zeit in der Zukunft gewönne
    sonst jeden Vergleich.
  - **Alte Clients (bis 0.48.0)** lesen und schreiben weiter
    `trail_details.status`/`status_at`: `reports_from_details` macht
    daraus eine Meldung, `reports_to_details` schreibt eine BESTÄTIGTE
    Meldung an den Beitrag zurück; `pg_trigger_depth()` hält die beiden
    auseinander. Die App schreibt `status` nicht mehr (`toRow`), liest
    es nicht mehr. Entfernt wird es in einem eigenen Patch, wenn
    `minimum_supported_version` über 0.48.0 steht.
  - **Liste** (seit 0.50.0): Sterne in der Zeile, `TrailSort.rating`;
    Wörter aus `trailRowTags` — eine abweichende jüngere unbestätigte
    Meldung als „GESPERRT?" (gedämpft), der BESTÄTIGTE Zustand ab
    `kConditionWordMax` (2) als Wort hinter Meldung und Hinweis.
    `trail_condition.dart` bleibt ohne Widgets (die Liste rechnet damit),
    die Sterne stehen in `rating_stars.dart`.
  - **Ausgangskorb**: `ReportJob` trägt die Zeit des Meldens
    (`createdAt` → `reported_at`) und die `client_id` (eindeutig je
    Nutzer, Kennung und Art). Ein `DetailsJob` von vor 0.49.0 bringt
    seinen Status als `legacyStatus` mit und geht beim Nachholen als
    Meldung raus. `matcher_check.sql` Block 23, `push_flush_check.sh`
    Fall 3b.
  - **Noch gültig?** (#119, seit 0.58.0, `still_valid.dart` pur,
    `still_valid_screen.dart`, Profil-Zeile mit Zähler, Filter
    `stillValidOnly` — Zeile und Chip nur, wenn es etwas zu prüfen gibt
    bzw. der Filter an ist; sonst kostete der Chip eine Zeile): gefragt wird nach MEINER jüngsten Angabe je Art,
    wenn sie noch angezeigt wird (`shownStatus`/`shownCondition` — eine
    jüngere bestätigte eines Buddys überholt sie), bei einer Meldung nur,
    wenn sie warnt, und erst ab `kStillValidAfter` (30 Tage). Ja =
    derselbe Wert neu, Nein = „offen" bzw. die Skala, beides über
    `report` (bestätigt wie immer, ohne Netz in den Korb). „Weiß nicht"
    ruht `kStillValidSnooze` (14 Tage, Betreiber) und liegt NUR auf dem
    Gerät (`Settings.stillValidSnoozes`, `<Kennung>|<bis>`, Abgelaufenes
    fällt beim Schreiben weg) — eine Tabelle wäre eine Lesequittung.
    Liste und Karte reichen die ruhenden Angaben an `passesTrailFilter`
    (`snoozed`), damit Filter und Seite dasselbe sagen.
- **Suche, Filter, Sortierung der Trail-Liste** (#66, seit 0.32.0,
  `trail_list.dart` pur, `lib/core/search_text.dart`): fehlertolerant wie
  PilzBuddy #395 — `foldSearchText` (klein, ä/ae → a, ohne Leer- und
  Satzzeichen), erst Teiltreffer, NUR wenn der leer ausgeht der
  Tippfehler-Ausgleich (`nearContainsDistance`, nur der beste Abstand),
  und die Liste sagt dann „Meintest du …?". Gesucht wird über Namen und
  Buddy-Namen, nie über Hinweistexte. „bis S2" lässt Trails OHNE
  Einschätzung weg (im Zweifel die Warnung) und zählt sie. Filter und
  Sortierung gelten für die Sitzung. **Der Filter gilt seit 0.33.0 für
  Liste UND Karte** (Betreiber, 2026-09-29): EIN Provider
  (`trailListFilterProvider`), EINE Regel (`passesTrailFilter`), EIN
  Chip-Widget (`TrailFilterChips`, in der Liste und im Blatt „Ebenen").
  Suche und Sortierung bleiben in der Liste. Auf der Karte wirkt er NUR
  auf Zeichnen und Treffen — „Entlang meiner Trails", Einpassen, Fokus
  und das Zerlege-Blatt rechnen mit allen. Ein aktiver Filter meldet sich
  oben auf der Karte mit X (PilzBuddy #154: still ausblenden sieht aus
  wie fehlende Trails); ein Fokus-Sprung auf einen ausgeblendeten Trail
  (Push) setzt ihn zurück und sagt es. Die Banner oben stehen seither
  untereinander in EINER Spalte (Update, Ausgangskorb, Filter).
- **Offizielle Trails in der App** (#13, `lib/features/official/`):
  Index und Regionen von `raw.githubusercontent.com` (Daten-Branch),
  erst ab Zoom 8 (`kOfficialMinZoom`) und nur für Regionen, deren Rahmen
  den Ausschnitt berührt; der Index je App-Lauf einmal, eine Region nur
  bei neuem `updated`. Gemerkt in `official_trails/` im App-Verzeichnis
  (vom Backup ausgenommen); ohne Netz gilt der gemerkte, auch ältere
  Stand. Im Web nur für die Laufzeit (den Rest macht der HTTP-Cache).
  Dateinamen aus dem Index werden geprüft (werden zu Pfaden), eine
  fremde Formatversion lässt die Ebene leer. Gestrichelt in
  `officialViolet`, gesperrte Teile grau (Orange ist die Meldung eines
  Buddys), zwischen Orten und Netz; ein Tipp auf das Netz gewinnt. Das
  Blatt nennt Status und Schwierigkeit IMMER mit der Quelle, kein
  S-Grad. Schalter im Blatt „Ebenen und Orte"
  (`Settings.officialTrailsEnabled`, Vorgabe an); aus heißt: keine
  Anfrage. Der Test-Harness hängt `FakeOfficialTrailsSource` und
  einen Speicher-Cache ein. „Auch ausgeschildert als …" im Trail-Blatt
  (`official_match.dart`, `OfficialSignposts`): Deckung wie im Abgleich
  (15 m, 0,8, Abtastung 5 m) — **dritter Spiegel der Schwellen**
  neben SQL und `tool/trail_match.py`, im selben PR mitändern; seit
  0.20.0 stehen sie als `kMatch*` in `lib/core/line_geometry.dart`,
  zusammen mit Projektion, Abtastung und Gitter, geteilt mit dem
  Zerlege-Blatt. Ohne Fréchet (nichts wird verschmolzen); Varianten
  zählen nicht gegen „derselbe". Das Blatt lädt die Region des Trails
  selbst nach.
- **Nach dem Annehmen einer Buddy-Anfrage** (#33 Teil 1, seit 0.22.0,
  `connect_summary.dart` pur): `FriendshipsNotifier.accept` merkt sich
  den Trail-Stand VOR dem Annehmen, lädt Freundschaften und Trails neu
  und rechnet „gemeinsam / neu von / neu für" aus den zwei sichtbaren
  Ständen — auf dem Gerät, nie auf dem Server (Konzept 12). Privat
  zählt nicht als „neu für", wartend (Ausgangskorb) gar nicht.
  Scheitert das Neuladen, gibt es keine Zahlen, aber die Annahme steht.
  Teil 2 (Overlap-Vorschläge, RPC über `trail_overlaps`) wartet auf die
  Regel fürs Zusammenführen im Konzept.
- **Eigene Position** (`lib/features/map/position_provider.dart`,
  PilzBuddy-Muster): Der Strom (`positionStreamProvider`) fragt NIE nach
  der Berechtigung, nur der Knopf „Meine Position" über
  `positionFixProvider` — kein Systemdialog beim Start (Play: Prominent
  Disclosure). Nur Vordergrund (`ACCESS_FINE/COARSE_LOCATION`, kein
  Background); die Position verlässt das Gerät nicht. Punkt in
  `MapPalette.ride` (nicht Blau — Blau heißt S1), Punkt und
  Kreis fangen keine Tipps ab. Die Karte dreht sich nicht
  (`InteractiveFlag.rotate` aus). Der Harness hängt `fakePosition` /
  `FakePositionFix` ein.
- **Fahrt aufzeichnen** (#28, `lib/features/rides/`, seit 0.13.0): die
  Pilztour aus PilzBuddy (#338/#342/#465 dort) ohne Leergang-Logik.
  Foreground-Service vom Typ `location` (`flutter_foreground_task`),
  **gemessen wird im Service-Isolate** (`ride_task_handler.dart`,
  `recordRideTick`), nicht im Main-Isolate — der stirbt beim Wegwischen,
  der Service nicht. JSON Lines unter `rides/` (Backup-Ausschluss),
  angehängt je Takt (5 s); Beenden benennt `active.jsonl` in
  `<id>.jsonl` um — die Fahrt bleibt als Ganzes auf dem Gerät, gelöscht
  wird nur auf Wunsch („Meine Fahrten" im Profil). Fünf Dinge, die man
  wissen muss:
  - **`initRideCommunication()` in `main()` ist die Rückrichtung.** Ohne
    sie meldet der Service jeden Punkt ins Leere, still, und die Karte
    kennt nur den ersten Fix — PilzBuddy #465, vier Wochen unbemerkt.
    `test/rides/ride_live_bridge_test.dart` prüft Rundlauf, Gegenprobe
    UND die Zeile.
  - **Die Brücke ist SharedPreferences** (`ride_dir`, `ride_uid`,
    `ride_active`): flache Werte, in beiden Isolaten lesbar. Der Pfad
    wird einmal drüben aufgelöst; im Service-Isolate gibt es kein
    Riverpod und keinen `ErrorSink`, `recordRideTick` fängt deshalb
    alles.
  - **Seit 0.19.0 ein Verbraucher von zweien** (`lib/features/keep_alive/`,
    PilzBuddys Koordinator #264/#338): Die Fahrt (`location`, mit Takt)
    und der Bereichs-Download (`dataSync`, ohne Takt) teilen sich den
    EINEN Service über den `KeepAliveCoordinator` — zwei `stop()` auf
    einem Service waren die Falle. Ändert sich die Typmenge, startet er
    den Service neu (`updateService` kann Typen nicht ändern); der Takt
    gehört dem Service-Isolate und hat genau einen Verbraucher. Das
    Manifest deklariert `dataSync|location` als Obermenge, genannt wird
    je Start nur, was der Lauf braucht. `test/keep_alive_test.dart`.
  - **Die GPS-Höhe wird ROH mitgeschrieben** (`RidePoint.altM`) und
    nirgends angezeigt: Ob sie als Höhenquelle taugt, wird gemessen,
    bevor eine Zahl daraus wird; Dateihöhen bleiben die Quelle.
  - **Kein Web.** `rideRecordingAvailableProvider` (= `!kIsWeb`)
    versteckt den Knopf; ein Tab im Hintergrund bekommt keine
    Positionen. Der Service-Import ist bedingt (`keep_alive_stub`).
  Manifest: `FOREGROUND_SERVICE(_LOCATION|_DATA_SYNC)`,
  `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` entfernt, Service-Typ
  `dataSync|location`, Symbol `ic_notification.xml` (nur Alphakanal,
  PilzBuddy #331) über den Meta-Data-Namen
  `keepAliveNotificationIconMetaData` — der Manifest-Test hält alles
  zusammen. Ausdrücklich kein `ACCESS_BACKGROUND_LOCATION`:
  die Dauerbenachrichtigung ist die Offenlegung. Der Harness hängt
  `FakeRideStore`, `FakeRideFix`, `FakeRideServiceBridge` und
  `FakeRideService` ein, sonst ginge jeder Kartentest über `restore()`
  an `path_provider`.
- **Bestätigen durch Fahren** (#116, seit 0.52.0, `ride_confirm.dart`
  pur, `ride_confirm_notify.dart`, Wächter in `ride_task_handler.dart`):
  Wer aufzeichnet und AUF einen Trail mit unbestätigter Meldung oder
  unbestätigtem Zustand kommt, bekommt sofort eine lokale
  Benachrichtigung — Trailname, was gemeldet ist, Knöpfe „Stimmt",
  „Trail ist frei" (nur bei einer warnenden Meldung), „Ändern…". Kein
  Schema (Betreiber, 2026-09-30): Die Antwort IST eine bestätigte
  Meldung des Fahrers mit demselben Wert, über `report_trail` mit
  `on_site` — der Dienst hat ihn auf der Linie gesehen. Sechs Dinge,
  die man wissen muss:
  - **Eine Fahrt ohne Antwort bestätigt nichts** fremdes; Schritt 8 von
    `contribute_recording` (die EIGENE Meldung auf „offen") bleibt.
  - **Die App legt die Ziele ab, der Dienst liest sie**
    (`rides/confirm_targets.json`, mit Konto, per `.part` + `rename`):
    `confirmTargetsOf` nimmt dieselbe Regel wie die Anzeige
    (`shownReportsOf`, auch eigene), geschrieben beim Start, bei jedem
    Laden der Trails (Karte) und leer beim Beenden. Der Dienst liest nur
    neu, wenn sich die Datei ändert — nie die ganze `network.json` je
    Takt.
  - **Gefragt wird auf der Linie, nicht daneben** (`confirmPromptFor`):
    zwei aufeinanderfolgende Fixe ≤ 30 m Genauigkeit, beide ≤ 20 m von
    der Linie, ≥ 25 m auseinander — wer quert oder steht, wird nicht
    gefragt. Enger als „vor Ort" (200 m) mit Absicht.
  - **Fragen und Antworten stehen als Zeilen IN der Fahrt**
    (`ConfirmAsked` mit dem Wert von damals, `ConfirmAnswered`;
    `RidePoint.fromJson` lässt sie liegen). Je Trail und Fahrt einmal —
    auch über einen Neustart des Isolates, der Wächter liest die
    gestellten Fragen aus der Datei. Eine Antwort trägt den Beginn der
    Fahrt im Payload und landet nie in einer anderen.
  - **Zwei Wege für eine Antwort**: Knöpfe ohne Oberfläche laufen im
    Hintergrund-Isolate des Pakets (`rideConfirmBackgroundResponse`,
    `vm:entry-point`), „Ändern…" und der Tipp auf die Benachrichtigung
    im Main-Isolate (`rideConfirmTapsProvider`, `PushListener` öffnet
    `/trail/<id>`). Beide schreiben über `handleConfirmResponse` in die
    Datei. Gesendet wird beim Beenden (`RideNotifier.stop`, vor dem
    Blatt), je Trail die letzte Antwort, mit ihrer Zeit — ohne Netz in
    den Ausgangskorb. „Ändern…" und Unbeantwortetes schreiben nichts —
    die fragt das Zerlege-Blatt (seit 0.53.0, `splitQuestionFor`,
    `split_confirm_row.dart`): an der Zeile des wieder gefahrenen
    Trails, nur was VOR der Fahrt gemeldet war, nur mit Zeitstempeln,
    gesendet SOFORT beim Tipp mit der Zeit der Fahrt am Trail (nicht
    mit „Speichern" — die Antwort hängt nicht am Beisteuern). Wer
    unterwegs geantwortet hat, wird nicht noch einmal gefragt: Seine
    Meldung ist die jüngste bestätigte (auch wartend im Korb), die
    unbestätigte damit überholt.
  - **Kanal `trailbuddy_meldungen`** (IMPORTANCE_HIGH, derselbe wie
    Push) — die Dauerbenachrichtigung der Fahrt ist leise und zeigte
    kein Banner. `flutter_local_notifications` braucht Desugaring
    (`build.gradle.kts`), den `ActionBroadcastReceiver` im Manifest
    (ohne tut ein Knopf nichts, still) und bringt `VIBRATE` mit; der
    Manifest-Test hält alles zusammen. Der Harness überschreibt
    `rideConfirmTapsProvider`.
- **Übernehmen beim ersten Befahren** (#102, seit 0.55.0,
  `trail_takeover.dart` pur, Rework Abschnitt 1 und 9, E1/E2): Eine
  bekannte Zeile im Zerlege-Blatt OHNE eigenen Beitrag
  (`needsTakeOver`: `myDetails == null`, nicht wartend) klappt auf:
  Name, S-Grad, Charakter, Sterne, Zustand — vorbelegt mit der Anzeige
  (`takeOverOf`: `displayName`, Median-Grad, `topTraits`, Median-Sterne;
  Zustand nur der jüngste BESTÄTIGTE der letzten 90 Tage), sichtbar als
  „Vorschlag aus dem Netz". Drei Dinge, die man wissen muss:
  - **Pflicht mit Sternen (E2)**: Unbestätigt zählt die Zeile nicht
    (`_knownCounts`), bestätigen geht erst mit Sternen; „Alle
    übernehmen" bestätigt jede Zeile, die schon Sterne hat. Wer den
    Trail schon beschrieben hat, wird nie gefragt.
  - **EINE Schreibstelle**: `adoptDetails` übernimmt den fremden Namen,
    weil der eigene leer ist, und schreibt die Sterne nur in einen
    Beitrag ohne eigene (`ContributeJob.rating`, Auftrag von vor 0.55.0
    liest sich ohne). Der Zustand geht als Meldung an den bekannten
    Trail (`report`, `on_site`, Zeit der Fahrt dort) — nur mit
    Zeitstempeln.
  - **Kein Rückfüllen auf dem Server** — es kopierte Namen von außerhalb
    des Netzes (Konzept 12). Für den Bestand (seit 0.56.0): „Übernehmen"
    im Blatt, solange der eigene Beitrag keinen Namen hat
    (`offersTakeOver`; `showTrailDetailsDialog(takeOver: true)`, leere
    Felder aus `takeOverDetails`, Speichern erst mit Sternen), dieselbe
    Zeile im Import-Ergebnis für Kennungen, die vorher nur über Buddys
    sichtbar waren (erst NACH der RPC bekannt), und der Filter
    „Bewertung offen" (`ratingOpenOnly` = `Trail.ratingOpen`, dieselbe
    Regel wie die verblassten Sterne).
- **Das Zerlege-Blatt** (#29, Konzept 5.1, `ride_split.dart` pur,
  `road_index.dart`, `ride_split_sheet.dart`, seit 0.20.0): nach der
  Aufzeichnung, aus „Meine Fahrten" (Schere) und aus dem GPX-Import für
  Fahrten — EIN Blatt, EIN `SplitRequest`. Acht Dinge, die man wissen
  muss:
  - **Bekannt heißt: mit den Schwellen des Abgleichs gedeckt** (15 m,
    0,8, beidseitig, `kMatch*`), das Stück der Fahrt im Korridor wird
    als Aufzeichnung beigesteuert („wieder gefahren"), ohne Namen und
    ohne Beitrag — der Trail hat schon einen. Kein Fréchet auf dem
    Gerät: Verschmelzen tut der Server; was das Blatt „bekannt" nennt,
    soll er auch verschmelzen, sonst legte er still einen Trail daneben.
  - **Kandidaten brauchen die Wege, und die kommen NUR aus gespeicherten
    Bereichen** (`loadRoads`: z13-Kacheln der Fahrt, Ebene `roads`,
    Straße = `highway`/`major_road`/`medium_road`/`minor_road`/`other`
    plus `path`+`track`; Pfade, Fußwege, Schienen nicht). Jede Kachel
    muss in einem Bereich liegen — `partial` heißt unbekannt, kein halber
    Kandidat. Ohne Wege keine Kandidaten (Betreiber, 2026-09-28: keine
    Gefälle-allein-Regel), das Blatt sagt es und nennt den Weg.
    `vector_tile` ist dafür direkte Abhängigkeit (es steckt ohnehin in
    `vector_map_tiles`).
  - **Das Gefälle kommt aus der GPS-Höhe** (Median über 7 Punkte,
    Abfahrt von Gipfel bis Talsohle, Ende bei 15 m Gegenanstieg,
    mindestens 30 Hm und 150 m; > 70 % der 5-m-Abtastpunkte abseits;
    Enden auf die Straße gestutzt). Beigesteuert wird die GPS-Höhe
    NICHT (`SplitRequest.stripElevation`, #28-Regel); Dateihöhen einer
    GPX-Fahrt schon. Ein Höhengitter gibt es in TrailBuddy nicht — das
    Konzept sagt „Höhengitter, offline", gebaut ist die Höhe der Spur.
  - **Unscharfe Fixe (> 30 m) fallen vor allem weg** und werden gezählt;
    ein 15-m-Korridor gegen einen ±40-m-Fix ist Rauschen.
  - **Die Karte zeichnet die Vorschau** (`rideSplitPreviewProvider`,
    Fahrt blass, bekannt grün, Kandidat `MapPalette.candidate`, abgewählt
    gestrichelt); die Griffe sind ein `RangeSlider` je Kandidat, die
    Linie folgt. Aufgeräumt wird NACH dem `await` des Blatts, nicht im
    `dispose` (dort ist `ref` tot). Die Knöpfe stehen fest unter der
    faulen Liste — im Test muss man das Blatt hochziehen, bevor ein
    Kandidat gebaut ist (`sheetScrollTo`).
  - **Name, S-Grad und Charakter gehen in EINEM Schreibvorgang** in den
    eigenen Beitrag (`adoptDetails`, auch im Ausgangskorb:
    `ContributeJob.grade`/`.traits`; ein Auftrag von vor 0.35.0 hat
    keine `traits` und liest sich leer).
    Heimzone (300 m) ist ein Hinweis am Kandidaten, kein Riegel — und er
    folgt den Griffen (`homeZoneOf`), nicht dem gefundenen Stück.
  - **„Stück selbst wählen"** (#104, seit 0.47.0, `manualSection`): ein
    Kandidat über die ganze Fahrt, ohne Wege und ohne Höhen, für alles,
    was die Abfahrts-Suche nicht findet. Vorgewählt ohne die ersten und
    letzten 300 m (Heimzone); ist die Fahrt dafür zu kurz, die ganze.
    Kein Merkmal „neu" oder „selbst gebaut" (Konzept 7).
  - **Marken während der Aufnahme** (#105, seit 0.57.0, `RideMark`,
    `markedRanges`): ein 44-dp-Knopf über der Aufnahme, nur während der
    Fahrt (Fahne, dann Zielflagge mit Rand — `markedTrailOpen`, EINE
    Regel für Knopf und Blatt). Vier Dinge, die man wissen muss:
    - **Die Marke trägt NUR die Zeit**; das Blatt nimmt den zeitlich
      nächsten Punkt. Kein eigener Fix beim Tippen — den Ort misst der
      Takt ohnehin.
    - **Geschrieben aus dem Main-Isolate** (`appendMark`), nicht über
      den Service wie der Punkt (Abweichung von Rework 5.2): Getippt
      wird dort, und die Datei nimmt schon die Antworten aus #116 von
      dort an; ein Umweg über den Service könnte still verloren gehen.
      Der Zustand trägt die Marke erst, wenn die Datei sie genommen hat
      — sonst zeigte der Knopf eine Marke, die das Blatt nie sieht.
    - **Paare in zeitlicher Reihenfolge**: Beginn öffnet, Ende schließt,
      ein zweiter Beginn schließt den offenen dort, ein Ende ohne Beginn
      zählt nicht, offen gilt bis zum letzten Punkt. Ohne Zeiten keine.
    - **Die Marke schlägt die Heuristik**, wo sie sich überschneiden,
      und weicht nur einem bekannten Trail, der ≥ 0,8 des Stücks deckt
      (sonst ginge dieselbe Strecke zweimal hinaus). Kandidat mit
      `marked`, vorangehakt, Griffe über die ganze Fahrt (`spansRide`),
      ohne Wege und ohne Höhen.
- **Ausgangskorb** (#30, `lib/data/outbox*.dart` +
  `lib/features/trails/outbox_providers.dart`, seit 0.14.0; PilzBuddy
  #267 als Vorlage): Genau DREI Aufträge — Aufzeichnung beisteuern
  (`ContributeJob`, die Linie so, wie sie an die RPC ging, plus Name),
  eigenen Beitrag speichern (`DetailsJob`) und melden (`ReportJob`, seit
  0.49.0, samt Hinweis — „gesperrt" meldet man am Trail). Alles
  andere (Höhen nachtragen, Hinweise allein, Löschen) scheitert weiter
  sichtbar. Sechs Dinge, die man wissen muss:
  - **Nur `looksOffline` führt in den Korb** (`_queueIfOffline`). Ein
    Serverfehler muss sichtbar scheitern — sonst sammelte der Korb still
    Aufträge, die nie durchgehen, und ein kaputtes Deployment bliebe
    unbemerkt. Ein Flow-Test hält es fest.
  - **Der Korb wirft beim Schreiben** (`.part` + `rename`, nichts
    geschluckt): Er trägt das Original. Landet der Auftrag nicht auf der
    Platte, meldet die App den ursprünglichen Netzfehler weiter.
  - **Der Auftrag entsteht VOR dem ersten Sendeversuch**, mit der
    `client_id` — so trägt schon der erste Versuch die Kennung, und ein
    Abriss nach dem Insert legt beim Nachholen keine zweite Aufzeichnung
    an (`contribute_recording` antwortet auf eine bekannte Kennung mit
    der Trail-Kennung von damals).
  - **Wartende Trails stehen auf Karte und Liste** (`withPendingJobs`,
    `Trail.pending`): gestrichelt, Uhr statt Route, „Wartet auf
    Übertragung" — sonst steuert man dieselbe Datei zweimal bei. Ohne
    Server-Kennung gibt es dort keinen Beitrag, keinen Hinweis, keine
    Einschätzung; das Blatt sagt es. Ein wartender Beitrag überlagert
    die eigene Zeile (`Trail.pendingDetails`). Ein Korb-Wechsel lädt NICHT
    neu vom Server (`_applyPending` legt den Korb auf den letzten
    Stand) — der Auftrag entsteht ja gerade, weil es kein Netz gibt.
  - **Die Wiedervorlage** (`OutboxRunner`, Riverpod-frei) schreibt den
    Korb am Ende EINMAL neu. Kein Netz, keine Sitzung und das Tageslimit
    brechen den Lauf ab, ohne den Zähler anzufassen; eine Ablehnung des
    Servers (`PostgrestException`, `WriteRejectedException`) ist sofort
    endgültig, alles andere nach fünf Anläufen. Abgelehnte bleiben
    stehen, bis jemand entscheidet („Erneut versuchen" / „Aus dem
    Ausgangskorb entfernen"). Angestoßen beim Kartenstart, bei der
    Rückkehr der Verbindung (`noConnectivityProvider`,
    `connectivity_plus`) und auf Tippen im Banner — NICHT am App-Resume.
  - **Kein Korb im Web, ausdrücklich** (`NoOutbox`, `append` wirft): Dort
    kommt der Netzfehler wie bisher. IndexedDB (PilzBuddy #386) ist ein
    eigener Schritt. `outbox/` steht in beiden Backup-Ausschlüssen; beim
    Abmelden bleibt der Korb liegen — er ist an das Konto gebunden
    (`uid` im Kopf), ein fremdes sieht nichts. Der Harness hängt
    `FakeOutbox` und einen `connectivityProvider` ohne Wechsel ein.
- **Zwischenspeicher des Netzes** (#32, `lib/data/trail_cache.dart`, seit
  0.15.0; PilzBuddy `spot_cache.dart` als Vorlage): Beim erfolgreichen
  Abruf schreibt `fetchWithCache` die drei Tabellen als EINE JSON-Datei
  (`trail_cache/network.json`, Zeilenform wie vom Netz, gelesen von
  denselben `fromJson`; die Encoder stehen daneben, ein Test prüft den
  Rundlauf Feld für Feld). Vier Dinge, die man wissen muss:
  - **Nur `looksOffline` liest die Kopie** (PilzBuddy #80). Ein
    Serverfehler bleibt sichtbar — sonst zeigte die App bei kaputtem
    Deployment wochenlang einen alten Stand als aktuellen.
  - **Eine Kopie wirft nie.** `write` schluckt volle Platte und fehlende
    Rechte, `read` Unlesbares — anders als der Ausgangskorb, der das
    Original trägt.
  - **Der Stand sagt sein Alter** (`trailsCachedAtProvider`): Karte
    („Kein Empfang — Trails vom …") und Liste. `null` heißt frisch.
  - **Abmelden und Kontolöschung räumen die Kopie ab** (Profil), der
    Ausgangskorb bleibt. Kein Korb/keine Kopie im Web, bewusst; IndexedDB
    (PilzBuddy #385) ist ein eigener Schritt. Der Harness hängt
    `FakeTrailCache` ein.
- **Karten-Engine und Fassade** (#31 Schritt 1, `lib/features/map/map_view/`,
  seit 0.16.0; PilzBuddy als Vorlage): `MapScreen` beschreibt nur noch,
  WAS die Karte zeigt (`MapViewLayers`: Kreise < Linien < Marker), und
  greift über `MapViewController` auf die Kamera zu. WIE gerendert wird,
  entscheidet `mapViewBuilderProvider`: **Android MapLibre** (nativer
  GPU-Renderer, `maplibre` 0.3.5 exakt gepinnt), **Web flutter_map** —
  ohne Schalter, `kIsWeb` ist eine Kompilierzeit-Konstante. Web sieht
  `package:maplibre` nie (bedingter Import, ein Test hält es fest).
  `flutter_map_view.dart` bleibt im Android-Build: Baut der
  MapLibre-Style nicht, fällt die Ansicht darauf zurück — ohne Style
  lieber die alte Karte als gar keine. Sechs Dinge, die man wissen muss:
  - **Tipps löst die FASSADE auf, nicht die Engine**
    (`map_hit_test.dart`, pur). TrailBuddys Inhalt sind Linien, und die
    beiden Engines treffen Linien verschieden. EINE Rechnung in Dart
    (Web-Mercator ohne Drehung, 12 px plus halbe Strichbreite) gibt auf
    beiden dieselbe Antwort: Linien zuerst (oberste gewinnt: Netz über
    offiziellen Trails), dann Marker. Die Nadeln tragen deshalb KEINEN
    `GestureDetector` mehr; `hitValue` ist ein `Trail`, `OfficialTrail`
    oder `Poi`, die Fahrt und der Positionspunkt haben keinen.
  - **Marker liegen immer ÜBER den Linien** — MapLibre kann Widgets nur
    über Style-Ebenen zeichnen, flutter_map folgt, damit beide Engines
    dasselbe Bild zeigen. Was ein Tipp trifft, entscheidet trotzdem die
    Prüfung, nicht die Zeichenreihenfolge (Abweichung von „Nadeln unter
    den Linien" aus #12).
  - **Die Kamera setzt MapLibre nur über `moveCamera`** (#68, seit
    0.26.1): `fitBounds` und `animateCamera` des Pakets laufen auf
    Android über `MapLibreMap.animateCamera`, und das WIRFT bei einer
    Dauer ≤ 0 ms („Null duration passed into animateCamera") — so kam
    jedes Einpassen von 0.17 bis 0.26 als Fehlerbericht an. Eingepasst
    wird mit `cameraToFit` (pur, `map_hit_test.dart`, Mitte in Mercator,
    Obergrenze in EINEM Schritt), dieselbe Rechnung fährt der Fake.
    `test/map/maplibre_camera_test.dart` hält am Quelltext fest, dass
    die Engine weder `fitBounds` noch `animateCamera` noch
    `Duration.zero` benutzt. Wer eine Animation will: Dauer > 0.
  - **Die Zoomstufe wird GERECHNET, nie gemeldet** (`MapViewCamera.zoom`
    aus Fenster und Pixelbreite, 256er-Web-Mercator). MapLibre zählt in
    512er-Kacheln, flutter_map in 256ern; dieselbe Zahl hieße zwei
    Maßstäbe (PilzBuddy 1.98.0). Orte (ab 12) und offizielle Trails
    (ab 8) hängen an der gerechneten. Die MapLibre-Seite rechnet an
    `initZoom`/`minZoom`/`maxZoom` und in `zoom` je eins um.
  - **Orte und offizielle Trails laden bei Kamera-STILLSTAND**
    (`onCameraIdle` → `_camera` im Screen → `poiCellsFor` /
    `officialViewFor`, pur), kurz verzögert, je Ausschnitt EIN Versuch.
    Sie sind keine Ebenen innerhalb der Engine mehr (`MapCamera.of` gibt
    es in MapLibre nicht).
  - **MapLibre trägt Farbe, Breite und Strich am LAYER**, deshalb
    gruppiert `polylineLayers` nach Stil (ein Netz kann hunderte Trails
    haben; PilzBuddy legt eine Ebene je Linie an, das trägt hier nicht);
    ein Rand wird zu einer breiteren Ebene darunter, ein Strichmuster in
    Bildpunkten zu Vielfachen der Breite. Der Genauigkeitskreis ist ein
    Polygon in Metern — `circle-radius` wäre ein Pixelmaß. `alignment`
    wird gespiegelt (PilzBuddy #409: bei `topCenter` hängt die Nadel
    sonst 40 px unter ihrem Ort). Marker werden bei Idle auf das
    Sichtfenster plus 25 % gefiltert (`visibleMarkers`), weil
    `WidgetLayer` jeden Marker in jedem Frame positioniert.
  - **Die Onlinekarte ist EIN Archiv auf dem eigenen Host** (#31
    Schritt 2, seit 0.17.0; `online_map.dart`, `map_providers.dart`):
    DACH als Protomaps-Basiskarte bis Zoom 13 auf Cloudflare R2 hinter
    `tiles.mcbuchi.de/trailbuddy/`, geschnitten, geprüft und
    hochgeladen von `map-data.yml` (monatlich und von Hand;
    `tool/map_tiles.py` prüft den Auszug gegen die Quelle UND die
    öffentliche Kopie über Range-Anfragen wie die App). Die App holt
    erst `dach.json` (den Zeiger auf `dach-<build>.pmtiles`) und liest
    dann kachelweise per Range — im Web `PmTilesArchive.fromUri`, in
    MapLibre `pmtiles://https://…`. Dateien mit Datum sind unveränderlich,
    nur der Zeiger wechselt: Eine Sitzung merkt sich Verzeichnisse, und
    ein überschriebenes Archiv ließe die Versätze in eine andere Datei
    zeigen; der vorige Stand bleibt einen Lauf lang liegen. Kein
    OSM-Raster mehr, auf keiner Plattform. Ohne Empfang wird das Manifest
    gar nicht erst geholt; ohne Manifest (Host weg, Datei kaputt) ist die
    Übersicht die Karte — still, und nur ein Fehler, der nicht nach
    Funkloch aussieht, wird gemeldet. Die Adresse ist eine KONSTANTE, keine
    Konfiguration: `test/release_workflow_test.dart` hält
    `kMapTilesBase` und `PUBLIC_BASE` im Workflow zusammen,
    `test/privacy_policy_test.dart` die Erklärung. R2-Zugang: die drei
    Secrets `R2_*` (API-Token, Object Read & Write auf den Bucket);
    fehlen sie, sagt es die Run-Summary. Bucket `buddy-tiles` mit
    Präfix je App — PilzBuddy kann später denselben Host nutzen. **Der
    Bucket hat EU-Jurisdiktion, und sein S3-Endpunkt heißt deshalb
    `<account>.eu.r2.cloudflarestorage.com`** — ohne `.eu` findet der
    Upload den Bucket nicht (Betreiber, 2026-09-28). **Bot Fight Mode
    ist für die Zone `mcbuchi.de` AUS** (#55): Im Free-Plan gilt er
    zonenweit ohne Ausnahme je Hostname und stellte dem Runner eine
    Managed Challenge (`403`, `cf-mitigated: challenge`), die kein
    Client der App lösen kann; der Verify-Schritt nennt sie seither mit
    Ray-ID. DDoS-Schutz ist davon unberührt. Was bleibt, ist ein
    Kostenrisiko (das Archiv ist zu groß für den Edge-Cache, jede
    Range-Anfrage ist eine R2-Class-B-Operation) — die Rate-Limiting-
    Regel und die Nutzungsbenachrichtigung stehen in #55, die Zahlen in
    `docs/konzept-offline-karten.md` Abschnitt 7.
  - **Gespeicherte Bereiche** (Konzept-Schritt 3, seit 0.19.0,
    `lib/features/offline_areas/`): Ein Bereich ist EIN PMTiles-Archiv
    (Zoom 8 bis zum Zoom des Hosts), geschrieben auf dem Gerät von
    `pmtiles_writer.dart` aus Kacheln, die die App per Range aus dem
    Host-Archiv geholt hat (Bytes unverändert, dieselbe Kompression) —
    der eigene Schreiber ist hier erlaubt, weil kein `pmtiles extract`
    auf dem Gerät läuft und der Download jedes Archiv sofort mit dem
    Leser beider Engines zurückliest (Zählung und Stichprobe). Ablage
    je Plattform (`AreaStore`): Dateien unter `offline_maps/areas/`
    (Android, Backup-Ausschluss), IndexedDB über `idb_shim` im Browser
    (Besitzer von Name und Version: `lib/data/browser_db.dart`), der
    Speicher im Test. Sechs Dinge, die man wissen muss:
    - **Die Größe ist gemessen, nicht geschätzt**: `plan()` schlägt jede
      Kachel im Verzeichnis nach und summiert die Längen; Obergrenze
      `kAreaMaxTiles` (40 000) je Bereich.
    - **Ein Bereich hat eine FORM, kein Rechteck** (`AreaShape`, seit
      0.24.0): `RectShape` für den Ausschnitt, `TileSetShape` für
      „Entlang meiner Trails" — die Kacheln bei `kAreaShapeZoom` (13),
      denen ein Trail näher als `kAreaTrailsCorridorKm` (1 km) kommt
      (`AreaShape.alongLines`, abgetastet je halben Korridor, Quadrat
      statt Kreis), andere Zooms als Eltern/Kinder daraus. Anlass: Das
      Rechteck um alle Trails lief beim Betreiber auf 40 779 Kacheln.
      Die Form steht im Index (`shape`; Einträge davor: der Rahmen IST
      die Form), „Aktualisieren" plant sie neu; `bounds` ist nur die
      Hülle — innerhalb kann eine Kachel FEHLEN, der Wege-Index fragt
      deshalb das Archiv (`ProviderException` ⇒ nicht gedeckt). Die
      Orte-Zellen kommen aus der Form, nicht aus der Hülle.
    - **Die Werkzeugleiste „Ebenen" zeigt, was liegt** (Stufe B seit
      0.25.0, seit 0.27.0 als Leiste; `offline_tool_rail.dart`,
      `area_overlay.dart` pur). Der Ebenen-Knopf (rechts, wie alle
      Kartenknöpfe) öffnet links eine schmale Leiste — das halbhohe Blatt
      davor deckte die Karte zu (Betreiber, 2026-09-29). Fünf Dinge, die
      man wissen muss:
      - **Solange sie offen ist** (`offlineOverlayProvider`), liegt EIN
        Polygon unter allem (`MapViewPolygon`, Löcher auf beiden
        Engines): Ausschnitt plus eine Fensterbreite Rand abgedunkelt,
        die gespeicherten Kacheln als Löcher, aus den FORMEN im Index.
        Ohne Bereiche ist alles dunkel — das IST die Aussage. Um den
        ganzen Bestand läuft seit 0.31.0 ein durchgehender Rand in der
        Textfarbe des App-Modus (`offlineCoverage`, `tileOutline`: der
        Umriss der Kachelmenge, Läufe je Gitterlinie, keine Nähte
        zwischen den Rechtecken; kein Rand am Bildrand, wo der Nachbar
        nicht gefragt wurde).
      - **Immer die Kacheln des Bereichs, nie abhängig vom Kamera-Zoom**
        (`offlineOverlayZoomOf` = min(Zoom des Bereichs, 13)). Bis 0.26.x
        waren es zwei Stufen über der Kamera, und die Hervorhebung sprang
        beim Zoomen. Damit weit draußen nicht tausende Löcher entstehen,
        fasst `mergeTileRects` Kacheln zu Rechtecken zusammen (Läufe je
        Zeile, gleiche Läufe übereinander); über `kOfflineOverlayMaxHoles`
        fällt nur der Rand weg, nie die Stufe.
      - **Schließen ist EIN Weg** (`_closeTools`): X, Ebenen-Knopf und
        Zurück-Taste (`PopScope`, `canPop` nur bei geschlossener Leiste);
        mit Änderungen im Entwurf fragt `confirmDiscardDraft`.
      - **Die Leiste steht mittig links** zwischen den Bannern (oben
        56 dp) und Maßstab/Quellenhinweis (unten 64 dp), seit 0.30.0 im
        Look aus Design 3e: 52 dp breit (`kRailWidth`), Knöpfe 44 dp
        (`kMapButtonSize`, Handschuh) mit `MaterialTapTargetSize.shrinkWrap`
        — sonst polstert Material auf 48 dp —, Gruppen durch 8 dp Luft,
        aktives Werkzeug in Gegenhelligkeit, Speichern Lime, der Zähler in
        Mono darunter. Auf einem kleinen Telefon hochkant (360 × 740)
        passt sie ganz, darunter scrollt sie (der Layout-Test misst auf
        Telefonmaß, `tapRail` scrollt auf 800 × 600). Solange sie offen
        ist, rücken Maßstab und Quellenhinweis neben sie
        (`MapViewConfig.bottomLeftInset`); flutter_map zeigt seinen
        Hinweis deshalb links wie MapLibre. Rechts stehen die runden
        Kartenknöpfe (`map_buttons.dart`): Idee, Ebenen, Position (44 dp),
        unten die Aufnahme (60 dp, Lime; läuft die Fahrt Orange mit
        Stop). Ein offenes Menü markiert seinen Knopf mit Rand in der
        Marke. `test/map/map_shell_test.dart` hält es hell und dunkel fest.
      - **Speichern ist ein Dialog** (`showSaveDraftDialog`): misst
        Kacheln, Bytes UND Orte (`AreaPlan.poiFiles`, die Zellendateien
        kommen schon beim Messen — das Manifest nennt keine Anzahl — und
        der Download holt sie nicht noch einmal), fragt nach dem Namen,
        lädt mit Fortschritt und Abbruch. Orte und offizielle Trails
        filtert der erste Knopf der Leiste (das bekannte Blatt).
    - **Bereiche zeichnen und bearbeiten** (Stufe C, #67, seit 0.26.0;
      seit 0.27.0 gegen den ganzen Bestand; `area_draw.dart` pur +
      Notifier, `area_draw_overlay.dart`, `area_trim.dart`): Die Leiste
      füllt einen ENTWURF aus ZWEI Mengen bei `kAreaShapeZoom` — was
      dazukommt (`adds`, nie eine gespeicherte Kachel) und was wegfällt
      (`removes`, nur gespeicherte), gerechnet gegen
      `storedTileKeysProvider` (Vereinigung aller Formen,
      `AreaShape.keysAt`). Stift/Ausschnitt/Trails fügen hinzu und nehmen
      ein Wegfallen zurück, der Radierer umgekehrt. Sechs Dinge, die man
      wissen muss:
      - **Die Darstellung hat EINE Regel** (Design Turn 2, seit 0.31.0;
        davor grün dazu, rot weg): Helligkeit = gespeichert, Schraffur +
        gestrichelter Rand = offene Änderung, und die Schraffur hat
        immer die Gegenhelligkeit ihres Grunds — „kommt dazu" hell `/`
        auf dunkel (`kAreaInkLight`), „fällt weg" dunkel gespiegelt `\`
        auf hell (`kAreaInkDark`); den Grund liefert die Maske, eine
        Tönung gibt es nicht (`draftLayers`). Keine neue Farbe: Grün
        heißt „mein Trail". Die Schraffur sind LINIEN (`hatchLines`),
        kein Füllmuster: Ein Muster bräuchte in MapLibre ein Bild im
        Stil. Sie hängen am Weltraster der Kamera-Zoomstufe
        (x ± y = k · 7 px), bleiben beim Verschieben stehen und werden
        bei Stillstand neu gerechnet; über `kAreaHatchMaxLines` gilt der
        Rückfall 2e — halbe Tönung, nur der Rand unterscheidet. Der
        Strich beim Zeichnen folgt derselben Regel (hell dazu, dunkel
        weg, mit Saum in der Gegenhelligkeit). Die Linien tragen keine
        Kennung und liegen unter allen Trails — ein Tipp geht hindurch.
      - **Entfernen braucht kein Netz** (`AreaTrimmer`): Das eigene
        Archiv wird ohne die Kacheln neu geschrieben (derselbe
        Schreiber, gegengelesen, bevor es das alte ersetzt), eine
        gröbere Kachel bleibt, solange darunter noch etwas liegt; die
        Form wird zur `TileSetShape`, Orte-Dateien leerer Zellen fallen
        aus dem Index (die Datei bleibt liegen, gelesen wird nur, was
        der Index nennt). Leer ⇒ der Bereich wird gelöscht. Gespeichert
        wird ERST das Entfernen (lokal), DANN das Laden; scheitert das
        Laden, bleibt im Entwurf nur „kommt dazu" (`dropRemoves`).
      - **Ein Strich ist eine Fläche**: geschlossen (Ende zum Anfang),
        dazu jede Kachel, die der Rand berührt oder die innen liegt
        (`tilesTouchedByRing`: Rand in Zehntelkachel-Schritten
        abgetastet, Inneres je Zeile gerade-ungerade). Ein offener
        Zickzack ist damit eine dünne Fläche; der Radierer nimmt genau
        weg, worüber er läuft. Rahmen über `kAreaDrawMaxSpanTiles` ⇒
        null und ein Satz, keine hängende Rechnung.
      - **Die Zeichenfläche ist ein Flutter-Widget ÜBER der Karte, keine
        Geste der Engine**: Sie liegt nur, solange ein Werkzeug auf
        seinen EINEN Strich wartet, fängt dann jede Berührung ab (die
        Karte steht still, die Kamera vom letzten Stillstand stimmt
        also) und rechnet mit `unprojectFromScreen` — der Umkehrung der
        Trefferprüfung, auf beiden Engines dieselbe Antwort. Nach dem
        Strich ist das Werkzeug weg und die Karte frei; die Fassade
        brauchte dafür keine Gesten-Schnittstelle.
      - **Der Entwurf lebt mit der Leiste**: Schließen verwirft ihn (mit
        Rückfrage), damit auch ein armiertes Werkzeug — sonst stünde die
        Karte fest. Gezeigt wird er nur mit Leiste.
      - **Schraffur je Rechteck, Rand je Umriss** (`mergeTileRects`,
        `tileOutline`), IMMER bei Zoom 13 wie die Maske — ein Rand je
        Rechteck sähe aus wie ein Gitter. MapLibre gruppiert Flächen und
        Linien nach Stil in je EINE Ebene (`polygonLayers`,
        `polylineLayers`).
      - **Gespeichert wird über den Dialog**: „Lädt … · Kacheln · Orte"
        (Netz) und „Gibt … frei · Kacheln" (lokal gemessen); ein Name nur,
        wenn etwas dazukommt. Danach leert der Karten-Screen den Entwurf
        (`clear`), die Leiste bleibt offen.
    - **Die Orte kommen mit**: die Zellendateien aller Gruppen, die das
      Orte-Manifest für den Rahmen nennt; `HostPoiSource` liest sie
      ZUERST (`readLocal`), was lokal liegt, braucht weder Manifest noch
      Netz.
    - **Die Bereiche liegen IMMER auf der Karte, zuoberst** (#82, seit
      0.36.1), mit und ohne Empfang, in beiden Engines (MapLibre: eine
      `file://`-Quelle je Bereich NACH der Online-Quelle; flutter_map:
      `MultiAreaTileProvider` als letzte Kachelschicht, ohne
      Ersatzkachel). Bis 0.36.0 waren sie nur die Karte ohne Empfang oder
      ohne Manifest — im Wald heißt das meist „ein Balken, über den nichts
      kommt": Das Telefon meldete Netz, die Online-Kacheln kamen nie, die
      gespeicherten wurden nicht gefragt, und die Leiste zeigte sie
      trotzdem als gespeichert. Das ist der lokale Vorrang aus Konzept
      3.2, ohne Kachel-Lieferanten: Jede Bereichskachel trägt die
      deckende `earth`-Fläche (Test: `area_layer_order_test.dart`) und
      verdeckt die Online-Karte darunter; wo der Bereich keine Kachel
      hat, liefert sein Archiv nichts. Doppelt gezeichnet wird nichts
      Sichtbares, nur die Online-Kachel darunter umsonst geladen. Das
      Archiv-Format war NICHT die Ursache: MapLibre 13.0 entpackt
      Verzeichnis und Kacheln nur bei gzip und liest „none" roh
      (nachgesehen im nativen Code).
    - **Der Download läuft im Main-Isolate**, auf Android unter dem
      KeepAlive-Koordinator (`dataSync`); Abbruch zwischen den Blöcken,
      geschrieben wird erst am Ende — ein Abbruch hinterlässt nichts.
    - **Bereiche werden nie verdrängt**, nur in „Meine Bereiche"
      gelöscht; ein neuerer Kartenstand wird dort angeboten (Knopf,
      derselbe Rahmen unter derselben Id), nicht aufgezwungen und nicht
      an „freies Netz" gebunden — wer tippt, entscheidet.
    - **„Gesehenes bleibt liegen" (Konzept 3.2) gibt es noch nicht**:
      kein Kachel-Zwischenspeicher der Online-Karte. Ein eigener Schritt.
    Der Einstieg ist der Ebenen-Knopf (kein eigener Knopf: die
    Knopfspalte lief auf einem kleinen Telefon quer über). Der Harness
    hängt `MemoryAreaStore` und `FakeKeepAlive` ein; die Test-Karte
    fordert nach `move`/`fit` einen Frame an (sonst kam der Stillstand
    erst beim nächsten zufälligen Neuzeichnen, und ein Test prüfte den
    alten Ausschnitt). `test/flows/offline_areas_flow_test.dart` fährt
    Leiste, Download, Liste, Löschen und Aktualisieren gegen ein
    Quellarchiv aus dem
    eigenen Schreiber.
  - **Der Stil ist ERZEUGT, die Übersicht auch** (`assets/map_style/`,
    `assets/offline_maps/overview_dach.pmtiles`, Zoom 0–7, ~9 MB;
    Glyphs `assets/map_glyphs/`, SIL OFL). `tool/transform_map_style.py`
    (u. a. `emphasize_paths`: Forstwege und Pfade als eigene Ebenen —
    Trails SIND die Wege) muss ein Fixpunkt bleiben;
    `tool/generated_assets.py --check` prüft Prüfsummen und Fixpunkt in
    CI, nach echtem Neu-Erzeugen `--update` im selben Commit. Die
    Übersicht liegt unter der Onlinekarte, sobald kein Empfang besteht
    ODER es keine Onlinekarte gibt (beide Engines dieselbe Regel); seit
    Schritt 2 ist das derselbe Stil aus demselben Format, PilzBuddys
    #137 (zwei Kartenstile nebeneinander) gilt hier nicht mehr. Auf dem
    Telefon aus einer materialisierten Datei, im Browser aus dem
    Speicher (`fromBytes`). `latlong2` 0.9 und `archive` 3.x, weil
    `pmtiles` 1.x daran hängt.
  Widget-Tests fahren `FakeMapView` (`test/fakes/fake_map_view.dart`):
  Marker-Kinder in einem `Wrap`, Kamera synchron simuliert, Tipps über
  DIESELBE Trefferprüfung (`tapMapAt`, `fakeMapLayers`);
  `useRealMap: true` pumpt die flutter_map-Engine für deren Interna. Die
  MapLibre-Platform-View ist im Widget-Test nicht renderbar — ihr Gate
  ist das Gerät, geprüft sind Composer, Style-Provider, Trefferprüfung
  und die Textzusagen (`test/map/`).
- **Kein Netzziel ohne Datenschutzerklärung**: `test/privacy_policy_test.dart`
  prüft jeden Host in `lib/` und `web/` gegen seine Einordnung.
- **Web**: `web/flutter_bootstrap.js` + `web/sw.js` sind PilzBuddys
  Service Worker (netzwerkzuerst, Cache als Rückfall); die Platzhalter
  dürfen in keinem Kommentar stehen. **`sw.js` ist seit Phase 1 KEINE
  Kopie mehr**, zwei Korrekturen, die PilzBuddy noch nicht hat: (1) der
  frühere Cache wird über den Vollständig-Merker erkannt, nicht über die
  Reihenfolge von `caches.keys()` — Chromium listet den neuen Cache oft
  vor dem alten, dann hielt sich der neue für vollständig und der alte
  blieb für immer; (2) `caches.match(…, {cacheName})` statt `open` zum
  Nachschlagen, Schreibzugriffe nur, solange der eigene Cache existiert,
  und ein Zombie-Sweep (leerer Cache ohne Merker und Hülle) — ein
  abgelöster Worker legte seinen gelöschten Cache sonst leer neu an.
  Gemessen: Prüfer vorher in einem von drei Läufen rot, danach 4/4 grün. `--no-web-resources-cdn` in jedem
  Web-Build, `--base-href /trailbuddy/`. Geprüft im echten Chrome
  (`tool/check_service_worker.mjs`, Job „Build Web").
- **Android**: Flavors `github` (mit `REQUEST_INSTALL_PACKAGES` für den
  In-App-Update-Weg) und `play` (ohne), gleiche `applicationId`
  `de.mcbuchi.trailbuddy`. Jeder Build braucht `--flavor`. Backup-Ausschlüsse
  in `res/xml/`: Session-Token, `offline_maps/`, `outbox/`, `trail_cache/`,
  `rides/`, `updates/`, `official_trails/`.
- **Feedback (die Glühbirne)**: `lib/features/feedback/feedback_dialog.dart`
  (Karte unten links und Profil) schreibt in `public.feedback`;
  `tool/feedback_bot.py` (`feedback.yml`, alle 2 h) macht daraus
  ÖFFENTLICHE Issues mit Label `enhancement`/`bug` und löscht
  `error_reports` nach 90 Tagen (Datenschutzerklärung). Auf demselben
  Tick der **Fehlerbericht-Digest** (#40, seit 0.21.0): ein Issue je
  ISO-Woche (Label `ops`, Titel `Error reports JJJJ-Wnn`), bei jedem
  Lauf neu geschrieben statt kommentiert; keine Fehler ⇒ kein Issue.
  Jede Gruppe zeigt den obersten Frame im EIGENEN Code (`top_frame`,
  `package:trailbuddy/`), sonst den obersten überhaupt (ANR-Dump). Eine
  vergangene Woche rendert `--digest-week 2026-W40` (liest nur), im
  Workflow über die Eingabe `digest_week` in die Run-Summary.
  `--test-digest` läuft in CI mit. Vier Dinge, die man wissen muss:
  - **Kein Benutzername im Issue**, anders als PilzBuddy: Das Issue ist
    öffentlich, wer schrieb, steht nur in der Datenbank. `@`-Erwähnungen
    werden entschärft. Der Dialog bittet ausdrücklich um keine
    Trailnamen oder Orte — ein Trail gehört nie in ein Issue (Konzept 4).
    Was an einem einzelnen Trail los ist, gehört in einen Hinweis an
    Buddys (#7), nie in ein Issue.
  - **Rechte des Service-Schlüssels stehen ausdrücklich im Schema**
    (patch_001): `service_role` umgeht RLS, aber keine fehlenden Grants,
    und das Live-Projekt gibt ohne automatische Freigabe keine von
    selbst. `tool/grants_check.sql` prüft sie im Dry Run — der
    API-Wächter sieht sie nicht, er fragt mit dem Publishable Key.
  - **Kein Schlüssel, kein Lauf — sichtbar**: Fehlt
    `SUPABASE_SERVICE_ROLE_KEY`, sagt es die Run-Summary, der Job bleibt
    grün. Die Projekt-URL liest der Bot aus `supabase_config.dart`.
  - **Auch der Digest nennt niemanden**: Kontext, Typ, Meldung, Frame —
    keine `user_id`, kein Name; Meldungen werden wie Feedback entschärft
    (`defuse`). Der Selbsttest hält es fest.
- **Beendigungsgründe** (#40, seit 0.21.0; PilzBuddy #147/#394 als
  Vorlage): Beim Start liest die App über den MethodChannel
  `de.mcbuchi.trailbuddy/exit_info` (`kExitInfoChannel`) Androids eigene
  Historie (`getHistoricalProcessExitReasons`, ab Android 11, keine
  Berechtigung) und meldet ANR, Absturz, nativen Absturz, Speicher-Kill
  nach `error_reports` — Kontext `App-Ende`, `created_at` ist der
  TODESzeitpunkt. Beim ANR mit dem Haupt-Thread-Abschnitt des Dumps, beim
  nativen Absturz mit dem Tombstone (ab API 31), das **in Dart gelesen
  wird** (`lib/data/tombstone.dart`, wirft nie), nicht in Kotlin:
  `MainActivity.kt` ist die einzige Datei ohne Test-Netz und reicht die
  Bytes nur durch; der Manifest-Test verbietet dort ein
  `Tombstone.parseFrom`. Normale Beendigungen (`USER_REQUESTED`,
  `EXIT_SELF` …) werden NICHT gemeldet, sonst füllt jedes Wegwischen den
  Digest. Ein Merker im App-Verzeichnis (`last_exit_report`) verhindert
  Doppelmeldungen; sein Verlust kostet eine doppelte Zeile.
  `getRss()`/`getPss()` liefern kB, `AppExit.summary` rechnet EINMAL in
  MB um, und 0 heißt „nicht gemessen", nicht „0 MB". Web und Android < 11
  liefern nichts. Tests: `test/exit_reporting_test.dart`,
  `test/tombstone_test.dart`.
- **Push** (#34, seit 0.23.0, Patch 008 und 014; PilzBuddy #277/#564 als
  Vorlage): eine Meldung, wenn ein Buddy einen Trail meldet (nur
  BESTÄTIGTE Meldungen, seit Patch 013) oder einen Hinweis schreibt —
  an die direkten Buddys des Autors, die
  den Trail und seinen Beitrag sehen (`app_internal.push_recipients`,
  Spiegel von `td_friend_select`/`notes_select`; je Buddy-Beziehung
  eine Zeile im Korb, keine Rechnung über alle, Konzept 12). Acht Dinge,
  die man wissen muss:
  - **Die Meldung trägt Inhalt, aber nie einen Ort** (seit 0.54.0,
    Patch 014, Betreiber 2026-09-30: „anonym genug"): Trailname, Name
    des Buddys, Statuswort und beim Hinweis dessen Text (140 Zeichen) —
    jeweils so, wie der EMPFÄNGER es sieht: `trail_name_for` spiegelt
    `Trail.displayName` (eigener Name, sonst der des ältesten sichtbaren
    Beitrags), `push_name_for` nimmt den Alias des Empfängers
    (`friend_aliases`, Besitzer = Empfänger), sonst den Benutzernamen.
    Nie eine Koordinate, nie der Zustand. Einzelner Anlass: „Anni meldet
    „Hang" als gesperrt" / „Anni zu „Hang"" + Text; mehrere an einem
    Trail: „„Hang": 1 Meldung und 1 Hinweis" / „von Anni und Ben";
    mehrere Trails: Anzahlen, „An 2 Trails · von …". Der Korb merkt sich
    dafür `sender_ids`, `events` und den jüngsten `note_id` (ein
    zurückgezogener Hinweis nimmt seine Zeile mit). Ziel bleibt die
    opake Kennung als `route` (`/trail/<uuid>`, bei mehreren
    `/trails`). Der Text steht an EINER Stelle, in `push_flush`;
    `tool/push_flush_check.sh` prüft ihn Wort für Wort, dazu dass kein
    fremder Alias und keine Koordinate in der Nutzlast steht.
    Datenschutzerklärung und Profil-Schalter sagen dasselbe.
  - **Entprellt**: (Empfänger, Art, Trail) ist der Schlüssel in
    `app_internal.push_outbox`, fünf Minuten Ruhe, gedeckelt auf 30
    Minuten; je Empfänger EINE Meldung je Lauf. Ein erneutes Melden
    desselben Status (nur `status_at`) löst nichts aus; zurück auf
    „offen" schon (die gute Nachricht). Privat heißt: niemand.
  - **Ohne Vault-Geheimnisse räumt `push_flush` nur ab** — die drei
    Geheimnisse (`push_functions_url`, `push_job_secret`,
    `push_service_key`) legt der Betreiber im SQL-Editor an (Anleitung in
    patch_008); die Function braucht `FCM_SERVICE_ACCOUNT` (base64) und
    `PUSH_JOB_SECRET` per `supabase secrets set`. `send-push` deployt
    NUR `deploy-functions.yml` (Repo-Secret `SUPABASE_ACCESS_TOKEN`,
    sonst sichtbar übersprungen) — der Schema Check spielt keine
    Functions ein. `tool/push_flush_check.sh` ruft den Versand im Dry
    Run WIRKLICH auf (zurückgerollt): PL/pgSQL prüft den Rumpf erst beim
    Aufruf, und live läuft er jede Minute.
  - **Firebase ist eingerichtet** (seit 0.37.0, Projekt
    `trailbuddy-6207b`, nur Cloud Messaging, ohne Analytics).
    `android/app/google-services.json` liegt im Repo — ihr Inhalt ist
    öffentlich (steckt in jeder APK), sie wird aus der Konsole GEHOLT,
    nie editiert; der Manifest-Test prüft den Paketnamen darin. Das
    Gradle-Plugin wird nur mit der Datei angewendet, ein Build ohne sie
    läuft weiter. Das Web liest Web-App und VAPID-Schlüssel aus
    `lib/core/push_config.dart` (öffentlich wie der Publishable Key;
    beide gehören zusammen gesetzt, Test). Fehlende Konfiguration ist
    kein Fehlerbericht (`isMissingFirebaseConfig`: `[core/…]` UND die
    native `PlatformException` „Failed to load FirebaseOptions" — die
    zweite kam bis 0.36.x in den Wochendigest). Der Versand braucht
    zusätzlich die Vault- und Function-Geheimnisse oben und ein deploytes
    `send-push`; ohne sie meldet der Testknopf einen Fehler, und der Job
    räumt nur ab. **Live eingerichtet seit 2026-09-29** (Testnachricht
    auf Android und im Web angekommen): Function-Secrets und Vault über
    die Management-API gesetzt, dasselbe Job-Geheimnis an beiden Stellen
    (liegt beim Betreiber, nie im Repo). Das Repo-Secret
    `SUPABASE_ACCESS_TOKEN` ist ein Token des Zweitkontos mit 7 Tagen
    Laufzeit — danach überspringt `deploy-functions.yml` sichtbar; ein
    neues Token braucht es erst, wenn sich `supabase/functions/` ändert.
    Probe ohne Meldung: `send-push` ohne Ausweis ⇒ 401, mit
    `x-push-secret` und `{"messages":[]}` ⇒ 200.
  - **Das Ziel ist eine Route, keine Seite**: `/trail/:id` setzt den
    Fokus-Wunsch (`mapFocusTrailProvider`) und landet auf der Karte; die
    Karte löst ihn beim Aufbau ODER sobald der Trail geladen ist
    (`_pendingFocus`) — beim Kaltstart aus einer Push kommt der Wunsch
    vor den Trails. Der Web-Worker öffnet die App unter `#/trail/<id>`.
    Erlaubnisliste in `push_routes.dart`; alles andere bleibt liegen.
  - **Der Schalter zeigt das ERGEBNIS, nicht den Wunsch**
    (`PushEnabledNotifier`): Ablehnung, Funkloch und fehlende
    Konfiguration bekommen je ihren Satz. Gemerkt wird nur das Token
    (`Settings.pushToken`); die Wahrheit ist die Zeile in `push_devices`
    (Token = Schlüssel, Kontowechsel zieht sie um).
  - **Android**: Kanal `trailbuddy_meldungen` (Manifest, `strings.xml`,
    `MainActivity.onCreate`, IMPORTANCE_HIGH — die Stufe lässt sich
    nachträglich NICHT ändern, wer sie ändern will, braucht eine neue
    ID), Symbol nur Alphakanal, Tönung `notification_color`. Der
    Manifest-Test hält alles zusammen. Im Vordergrund zeigt Android
    nichts — `PushListener` (in `app.dart`, über dem `UpdateGate`) zeigt
    die Leiste, erst `clearSnackBars`, dann zeigen.
  - **Web**: eigener Worker `web/push/firebase-messaging-sw.js` ohne
    Firebase-SDK, Scope `push/` (der Basis-Scope gehört `sw.js`), Fokus
    statt Sichtbarkeit und nur DIESE App (`APP_BASE`), Übergabe
    `trailbuddy-push` (`kPushBridgeType`, ein Test hält beide zusammen).
    `tool/check_push_worker.mjs` prüft ihn im echten Chrome (Job „Build
    Web"). `www.gstatic.com` ist `afterConsent` im Datenschutz-Wächter.
- **Noch nicht da, bewusst** (jeweils eigener PR, Muster in PilzBuddy):
  der Kachel-Zwischenspeicher der Online-Karte („Gesehenes bleibt
  liegen", Konzept 3.2), Ausgangskorb und
  Zwischenspeicher im Browser, Nachrichten zwischen Buddys (#34, Rest),
  Meldung zu einem einzelnen Trail, `docs/play-console.md`.

## Code-Konventionen

Wie PilzBuddy: Business-Logik in Repositories, Mutationen per
`reloadAfterWrite`, `mounted` nach jedem `await`, `requireUid` statt
`currentUser!.id`, `catch (_) {}` nur mit Grund. Farben aus
`lib/core/app_colors.dart` (Marke Lime `AppColors.brand`, hell und dunkel
als `AppPalette`, gelesen mit `AppPalette.of(context)`; Text in Marke,
Warnung, Buddy über `accentText`/`warningText`/`buddyText` — die
Linienfarben reichen im Hellen als Text nicht). **Die Karte ist immer
hell**: Linien nehmen `AppColors.mapLines` (heller Satz, weißer Saum),
nicht den Modus der App. Schriften als Assets (`AppFonts`: Barlow,
Barlow Condensed für Titel, JetBrains Mono für Zahlen), kein
`google_fonts`. Theme in `lib/core/app_theme.dart`, Modus aus
`Settings.appearance` (Profil, „Erscheinungsbild").

## Tests

`flutter analyze` + `flutter test` nach jeder Änderung, **kein `dart
format .`**. Harness `test/fakes/test_app.dart` (`pumpApp`) gegen die Fakes
in `test/fakes/`, die die RLS-Regeln spiegeln (`fake_trails.dart` für die
Trail-Sichtbarkeit). Kein Netz in Tests; Kartenkacheln kommen aus dem
Fake-Tile-Provider.
