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
  Release entsteht. `promote.yml` (Freigabe, Pages-Deploy) und
  `preview.yml` (Vorschau-Repo) kommen mit den zugehörigen Secrets; bis
  dahin gibt es kein Web-Deploy.
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
  RPC gibt nur die Trail-Kennung zurück, nie ob sie neu ist. Das
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
    (`simplify`, senkrechte Toleranz `kSimplifyVerticalM`): Ein gerades,
    welliges Stück verlöre sonst seine Wellen. Das Import-Blatt rechnet
    deshalb auf der VEREINFACHTEN Spur, damit es dieselbe Zahl sagt wie
    danach das Trail-Blatt.
  - **Hysterese `kElevationThresholdM`**, Spiegel in
    `tool/elevation_measure.py` mit denselben Testvektoren; Werkzeug und
    Dart im selben PR ändern. Die Importregel „Abstieg > 2 × Anstieg"
    rechnet bewusst ROH — so ist sie gemessen.
  - **Angezeigt wird in Trail-Richtung, aus der besten Aufzeichnung MIT
    Höhen** (`Trail.elevation`), nicht zwingend aus der besten Linie.
    Ohne Höhen sagt das Blatt „Keine Höhenangaben", nie „0 Hm".
    Aufzeichnungen vor 0.3.0 haben keine; ein Weg zum Nachtragen ist
    offen (eigenes Issue).
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
  `rides/`, `updates/`.
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
    Meldungen zu einem einzelnen Trail sind ein eigener, noch offener Weg
    (Hinweise an Buddys: #7).
  - **Rechte des Service-Schlüssels stehen ausdrücklich im Schema**
    (patch_001): `service_role` umgeht RLS, aber keine fehlenden Grants,
    und das Live-Projekt gibt ohne automatische Freigabe keine von
    selbst. `tool/grants_check.sql` prüft sie im Dry Run — der
    API-Wächter sieht sie nicht, er fragt mit dem Publishable Key.
  - **Kein Schlüssel, kein Lauf — sichtbar**: Fehlt
    `SUPABASE_SERVICE_ROLE_KEY`, sagt es die Run-Summary, der Job bleibt
    grün. Die Projekt-URL liest der Bot aus `supabase_config.dart`.
- **Noch nicht da, bewusst** (jeweils eigener PR, Muster in PilzBuddy):
  MapLibre-Engine für Android, Offline-Karten, Ausgangskorb, Aufzeichnung
  (Phase 2), Nachrichten und Push, Fehlerbericht-Digest, Meldung zu einem
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
