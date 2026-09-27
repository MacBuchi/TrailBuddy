# TrailBuddy

Plattform und App für Mountainbike-Trails, die man mit seinen Buddys
teilt: Das persönliche Trail-Netz wächst mit den Leuten, mit denen man
verbunden ist. Schwesterprojekt von
[PilzBuddy](https://github.com/MacBuchi/pilzbuddy), gleicher Stack
(Flutter für Android und Web, Supabase mit PostGIS).

**Stand: Phase 1, das Grundgerüst.** Anmelden, Buddys finden, Trails aus
GPX-Dateien beisteuern und auf der Karte sehen. Der Server gleicht jede
beigesteuerte Linie still mit bekannten Trails ab; sichtbar ist nur, was
man selbst oder ein direkter Buddy gefahren ist.

- Konzept: [`docs/konzept-trails.md`](docs/konzept-trails.md) — Trails,
  Duplikate, das Community-Tor, die Entscheidungen des Betreibers.
- Messung der Abgleich-Schwellen:
  [`docs/trail-abgleich-messung.md`](docs/trail-abgleich-messung.md).
- Arbeitsregeln für Mitwirkende und Werkzeuge: [`CLAUDE.md`](CLAUDE.md).

Noch nicht da: Aufzeichnen in der App (Phase 2), Offline-Karten,
Nachrichten, Routing. Es gibt noch kein Live-Backend; Entwicklung und CI
laufen gegen den lokalen Supabase-Stack (`supabase/config.toml`).
