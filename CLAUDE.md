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
Offizielle Trails (#13) sind eine getrennte Ebene mit eigenem Konzept:
`docs/konzept-offizielle-trails.md`. Gebaut von `official-trails.yml`
(`tool/official_trails.py`, Quellen in `tool/official/sources.json`)
auf den Branch `official-trails-data` — nie als Release (die
Update-Prüfung nähme es im Vorab-Kanal für eine App-Version). Dort
liegen nur öffentliche Daten Dritter, keine Nutzerdaten.

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
  Fahrten können in Phase 1 nicht beigesteuert werden (Zerlegen kommt mit
  der Aufzeichnung, Phase 2). Ohne Zeiten oder mit > 60 km/h Median ⇒
  `planned`.
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
- **Orte auf der Karte** (#12, `lib/features/map/poi*.dart`): live von
  `overpass-api.de` (FOSSGIS), erst ab Zoom 12, geladen in einem festen
  Raster (0,1° × 0,15°), jede Zelle je Gruppe einmal pro App-Lauf; der
  Filter ist gerätelokal (`Settings.poiGroups`, Vorgabe nur „Wasser" —
  Entscheidung des Betreibers). Ist alles aus, geht KEINE Anfrage raus;
  der Test-Harness hängt `FakePoiSource` ein, weil die Karte beim
  Einpassen auf einen Trail über Zoom 12 liegt. Die Nadeln liegen UNTER
  den Trail-Linien und tragen nie eine der Trail-Farben. Eine Art hat
  mehrere Tag-Regeln, die ERSTE passende Art gewinnt (Biergarten vor
  Gasthaus: `biergarten=yes`); das Kuchenstück ist gezeichnet
  (`PoiGlyph`, Material hat keins). Der Detailfilter
  (`Settings.poiHiddenKinds`) blendet nur aus, geladen wird je Gruppe.
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
  den Trail hervor — gelber Rand auf der Karte, getönte Zeile mit „neuer
  Hinweis" in der Liste; eigene zählen nie. Beim Ändern des Status
  bietet „Mein Beitrag" einen Hinweis an. Entscheidungen des Betreibers
  vom 2026-09-28; `matcher_check.sql` Block 20 prüft RLS und Aufräumen.
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
  neben SQL und `tool/trail_match.py`, im selben PR mitändern. Ohne
  Fréchet (nichts wird verschmolzen); Varianten zählen nicht gegen
  „derselbe". Das Blatt lädt die Region des Trails selbst nach.
- **Eigene Position** (`lib/features/map/position_provider.dart`,
  PilzBuddy-Muster): Der Strom (`positionStreamProvider`) fragt NIE nach
  der Berechtigung, nur der Knopf „Meine Position" über
  `positionFixProvider` — kein Systemdialog beim Start (Play: Prominent
  Disclosure). Nur Vordergrund (`ACCESS_FINE/COARSE_LOCATION`, kein
  Background); die Position verlässt das Gerät nicht. Punkt in
  `AppColors.positionDot` (nicht Blau — Blau heißt Buddy), Punkt und
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
  - **Ein Verbraucher, kein Koordinator.** Anders als PilzBuddy (Download
    UND Tour auf einem Service) gibt es nur die Fahrt; mit Offline-Karten
    (Phase 3) kommt der Koordinator von dort — zwei `stop()` auf einem
    Service sind die Falle.
  - **Die GPS-Höhe wird ROH mitgeschrieben** (`RidePoint.altM`) und
    nirgends angezeigt: Ob sie als Höhenquelle taugt, wird gemessen,
    bevor eine Zahl daraus wird; Dateihöhen bleiben die Quelle.
  - **Kein Web.** `rideRecordingAvailableProvider` (= `!kIsWeb`)
    versteckt den Knopf; ein Tab im Hintergrund bekommt keine
    Positionen. Der Service-Import ist bedingt (`ride_service_stub`).
  Manifest: `FOREGROUND_SERVICE(_LOCATION)`, `POST_NOTIFICATIONS`,
  `RECEIVE_BOOT_COMPLETED` entfernt, Service-Typ `location`, Symbol
  `ic_notification.xml` (nur Alphakanal, PilzBuddy #331) über den
  Meta-Data-Namen `rideNotificationIconMetaData` — der Manifest-Test
  hält alles zusammen. Ausdrücklich kein `ACCESS_BACKGROUND_LOCATION`:
  die Dauerbenachrichtigung ist die Offenlegung. Der Harness hängt
  `FakeRideStore`, `FakeRideFix`, `FakeRideServiceBridge` und
  `FakeRideService` ein, sonst ginge jeder Kartentest über `restore()`
  an `path_provider`.
- **Ausgangskorb** (#30, `lib/data/outbox*.dart` +
  `lib/features/trails/outbox_providers.dart`, seit 0.14.0; PilzBuddy
  #267 als Vorlage): Genau ZWEI Aufträge — Aufzeichnung beisteuern
  (`ContributeJob`, die Linie so, wie sie an die RPC ging, plus Name) und
  eigenen Beitrag speichern (`DetailsJob`, samt Status-Hinweis). Alles
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
  - **Der Stil ist ERZEUGT, die Übersicht auch** (`assets/map_style/`,
    `assets/offline_maps/overview_dach.pmtiles`, Zoom 0–7, ~9 MB;
    Glyphs `assets/map_glyphs/`, SIL OFL). `tool/transform_map_style.py`
    (u. a. `emphasize_paths`: Forstwege und Pfade als eigene Ebenen —
    Trails SIND die Wege) muss ein Fixpunkt bleiben;
    `tool/generated_assets.py --check` prüft Prüfsummen und Fixpunkt in
    CI, nach echtem Neu-Erzeugen `--update` im selben Commit. Die
    Übersicht liegt NUR ohne Empfang unter dem OSM-Raster (beide
    Engines dieselbe Regel: `noConnectivityProvider`; PilzBuddy #137 —
    zwei Kartenstile nebeneinander sehen kaputter aus als eine leere
    Fläche); auf dem Telefon aus einer materialisierten Datei, im
    Browser aus dem Speicher (`fromBytes`). Kein neues Netzziel: Alles
    liegt im Binary. `latlong2` 0.9 und `archive` 3.x, weil `pmtiles`
    1.x daran hängt.
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
  `error_reports` nach 90 Tagen (Datenschutzerklärung). Drei Dinge, die
  man wissen muss:
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
- **Noch nicht da, bewusst** (jeweils eigener PR, Muster in PilzBuddy):
  Offline-Karten über die Übersicht hinaus (Schritte 2–4 in
  `docs/konzept-offline-karten.md`: Host und Schnitt, Bereiche, Orte
  offline), Ausgangskorb und Zwischenspeicher im Browser, das Zerlege-Blatt nach der Fahrt (#29), Nachrichten und Push, Fehlerbericht-Digest, Meldung zu einem
  einzelnen Trail,
  Beendigungsgründe (`MainActivity.kt` ist noch die Vorlage),
  Launcher-Icon (noch Flutter-Vorgabe), `docs/play-console.md`.

## Code-Konventionen

Wie PilzBuddy: Business-Logik in Repositories, Mutationen per
`reloadAfterWrite`, `mounted` nach jedem `await`, `requireUid` statt
`currentUser!.id`, `catch (_) {}` nur mit Grund. Farben aus
`lib/core/app_colors.dart` (`trailGreen` ist der Markenton).

## Tests

`flutter analyze` + `flutter test` nach jeder Änderung, **kein `dart
format .`**. Harness `test/fakes/test_app.dart` (`pumpApp`) gegen die Fakes
in `test/fakes/`, die die RLS-Regeln spiegeln (`fake_trails.dart` für die
Trail-Sichtbarkeit). Kein Netz in Tests; Kartenkacheln kommen aus dem
Fake-Tile-Provider.
