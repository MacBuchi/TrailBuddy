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
- Commit-/PR-Titel: Conventional Commits. Auf GitHub Englisch (Commits,
  PRs, Issues); Deutsch für UI-Strings, Nutzer-Doku und die Kommunikation
  mit dem Betreiber.
- **Version Guard** (ci.yml): Code-Änderung ohne Bump in `pubspec.yaml`
  blockiert den Merge, sobald es einen Release-Tag gibt. Ausgenommen sind
  `*.md` (außer `CHANGELOG.md`, die liegt als Asset im Binary), `.github/`,
  `tool/`, `supabase/`, `docs/`. Beide Teile erhöhen (`0.1.0+1 → 0.1.1+2`).
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
  Bestand (Basis-Schema + neue Patches) und Frischinstallation (nur
  `schema.sql`) —, danach `tool/schema_check.sh` (App-Queries gegen das
  Schema), `tool/matcher_check.sql` (der Abgleich mit echten Linien) und
  `tool/auth_reset_check.sh` (Auth-Flows gegen echtes GoTrue). **Ein
  Live-„Schema Check" gibt es noch nicht** — es gibt kein Live-Projekt
  (Konzept, Punkt 9); er kommt mit dem Projekt, samt Secret
  `SUPABASE_DB_URL`.
- **Patches**: `supabase/patch_NNN_*.sql` + Struktur in `schema.sql` + Eintrag
  in der Saat-Liste, alles im selben PR; ein eingespielter Patch wird nie
  wieder angefasst (`tool/patch_guard.sh`). Baseline ist 0: Es gibt keine
  von Hand eingespielten Patches.
- **Supabase-Konfiguration der App**: `lib/core/supabase_config.dart` liest
  `SUPABASE_URL`/`SUPABASE_KEY` aus `--dart-define`, Vorgabe ist der lokale
  Stack. Ein Live-Projekt trägt seine Werte dort ein (Publishable Key ist
  öffentlich; niemals den service_role-Key).

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
- **Kein Netzziel ohne Datenschutzerklärung**: `test/privacy_policy_test.dart`
  prüft jeden Host in `lib/` und `web/` gegen seine Einordnung.
- **Web**: `web/flutter_bootstrap.js` + `web/sw.js` sind PilzBuddys
  Service Worker (netzwerkzuerst, Cache als Rückfall); die Platzhalter
  dürfen in keinem Kommentar stehen. `--no-web-resources-cdn` in jedem
  Web-Build, `--base-href /trailbuddy/`. Geprüft im echten Chrome
  (`tool/check_service_worker.mjs`, Job „Build Web").
- **Android**: Flavors `github` (mit `REQUEST_INSTALL_PACKAGES` für den
  In-App-Update-Weg) und `play` (ohne), gleiche `applicationId`
  `de.mcbuchi.trailbuddy`. Jeder Build braucht `--flavor`. Backup-Ausschlüsse
  in `res/xml/`: Session-Token, `offline_maps/`, `outbox/`, `trail_cache/`,
  `rides/`, `updates/`.
- **Noch nicht da, bewusst** (jeweils eigener PR, Muster in PilzBuddy):
  MapLibre-Engine für Android, Offline-Karten, Ausgangskorb, Aufzeichnung
  (Phase 2), Nachrichten und Push, Feedback-Bot und Fehlerbericht-Digest,
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
