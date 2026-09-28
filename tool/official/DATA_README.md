# TrailBuddy – offizielle Trails (Daten)

Dieser Branch wird von `.github/workflows/official-trails.yml` geschrieben,
nie von Hand. Er enthält die Dateien hinter der Kartenebene „Offizielle
Trails“ (Konzept: `docs/konzept-offizielle-trails.md` auf `main`):

- `index.json` — Regionen mit Datei, Rahmen, Anzahl, Stand; Quellen mit
  Lizenz und Quellenangabe
- `<region>.geojson` — je Trail ein Feature (MultiLineString; Hauptroute
  und Varianten als Teile, `sections` sagt, welcher Teil was ist)

Alles hier sind öffentliche Daten Dritter unter der Lizenz, die
`index.json` je Quelle nennt — keine Daten von Nutzern.
