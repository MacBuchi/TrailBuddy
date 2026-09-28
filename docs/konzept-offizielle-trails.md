# Offizielle Trails — Konzept (Issue #13)

*Stand 2026-09-28. Entscheidungen des Betreibers in Abschnitt 2; was
vor dem Bauen noch zu klären ist, in Abschnitt 6.*

## 1. Kurzfassung

Offiziell ausgewiesene Singletrails und Bikeparks — vom Land, von einem
Verein mit Genehmigung, vom Betreiber eines Bikeparks — erscheinen als
**eigene Ebene** auf der Karte, getrennt von den Trails des Buddy-Netzes.
Ein CI-Job holt die Quellen wöchentlich, filtert auf Singletrails, bringt
sie in ein gemeinsames Format und veröffentlicht sie als statische
GeoJSON-Dateien je Region. Die App lädt die Region, die sie gerade zeigt,
merkt sie sich und zeichnet sie als abschaltbare Ebene mit eigenem Blatt
und Quellenangabe. Keine Tabelle, keine RLS, kein Abgleich: Die Daten
sind öffentlich, und das Buddy-Modell bleibt unberührt.

## 2. Entscheidungen des Betreibers (2026-09-28)

1. **Eigene Ebene, CI baut Dateien.** Verworfen: ein offizielles Konto
   in der Datenbank (Abschnitt 3) und Live-Abfragen aus der App wie bei
   den Orten (mehrere fremde Server sähen den Kartenausschnitt, jede
   Quelle bräuchte eine eigene Anbindung im Client).
2. **Nur Singletrails und Bikeparks.** Ausgeschilderte Touren über
   Forstwege bleiben draußen: Sie sind nach der Importregel Fahrten, und
   ein Trail des Netzes wäre darin immer nur ein „Teil".
3. **Regionen zum Start:** Tirol, Vorarlberg, Schweiz, Baden-Württemberg
   — dort ausdrücklich auch Vereins-Trails (Trailsurfers
   Baden-Württemberg e.V., Bikeländ Eberbach, Flowtrail Mosbach und
   weitere dieser Art).
4. **Kein OpenStreetMap als Quelle — Klasse statt Masse.** Nur, was
   eine zuständige Stelle ausweist oder betreibt: eine Behörde, ein
   Verein mit Genehmigung, ein Bikepark. Lieber eine dünne Ebene, auf
   die man sich verlassen kann, als eine volle mit Unbekanntem.
5. **Die Ebene ist beim ersten Start an.**

## 3. Warum kein offizielles Konto

Der Vorschlag im Issue war ein TrailBuddy-Konto, das CI mit offiziellen
Trails füllt. Als **Buddy aller** geht das nicht: Wer Buddy ist, sieht
nach der Sichtbarkeitsregel (Konzept 3) die Aufzeichnungen seiner Buddys
— ein Konto, das mit allen befreundet ist, sähe alles, und ein
abgeflossener Schlüssel dieses Kontos läge offen. Bliebe eine
Sonderregel „offizielle Aufzeichnungen sieht jeder". Dann liefen
fremdlizenzierte Linien durch den Abgleich und würden mit Beiträgen von
Nutzern zu einer Trail-Kennung verschmolzen: Lizenzpflichten (Quellen-
angabe je Linie) wandern in die Trail-Tabellen, und wenn eine Quelle
einen Trail umbenennt, verlegt oder streicht, trifft das eine Kennung,
an der Beiträge von Nutzern hängen. Konzept 3 („sichtbar ist, was
jemand GEFAHREN ist") gälte nicht mehr. Die getrennte Ebene hat keinen
dieser Nachteile.

## 4. Quellen — Stand der Recherche

| Quelle | Was | Singletrails erkennbar? | Lizenz | Zugang |
|---|---|---|---|---|
| Tirol, MTB-Modell 2.0 (Land Tirol, tiris) | Routen **und Singletrails**, Schwierigkeit grün/blau/rot/schwarz | ja, eigene Kategorie | Open Government Data — Datensatz und Lizenz genau bestimmen (der frühere Katalogeintrag ist nicht mehr erreichbar) | tiris Open-Data-Portal (Shape, GeoJSON, Dienste) |
| Vorarlberg (Land, VOGIS) | Mountainbikenetz, Wegweiser, Streckenabschnitte | zu prüfen | Open Government Data, je Datensatz prüfen | WFS, GeoPackage, GeoJSON |
| Schweiz, Mountainbikeland (ASTRA, SchweizMobil) | nationale, regionale, lokale Routen | **nein** — die Attribute sind Route, Routennummer, Segment | frei, Quellenangabe Pflicht | api3.geo.admin.ch, data.geo.admin.ch |
| Schweiz, Sperrungen/Umleitungen Mountainbikeland | täglich | — | frei | wie oben |
| Trailsurfers Baden-Württemberg e.V. | legale Naturtrails im Bottwartal, GPX auf der Vereinsseite | ja | **keine offene Lizenz** — Erlaubnis nötig | GPX-Download |
| Bikeländ Eberbach (Kanu Club Eberbach) | 12 freigegebene Singletrails | ja | Erlaubnis nötig | Website |
| Flowtrail Mosbach | drei Abfahrten und ein Uphill | ja | Erlaubnis nötig | Website |
| Bikeparks | je Betreiber | ja | Erlaubnis nötig | je Betreiber |

Ausgeschlossen: **Trailforks** (Daten nur für nicht-kommerzielle,
„share-alike"-Nutzung mit Registrierung, keine Kopie für
nicht-persönliche Zwecke), **OpenStreetMap** (Entscheidung 4),
Tourenportale (Outdooractive, Komoot, Bergfex — keine offenen Daten).

Folgen für den Start: **Tirol ist die einzige Quelle, die heute alle
drei Bedingungen erfüllt** (offen, amtlich, Singletrails unterscheidbar).
Die Schweiz liefert Singletrails nicht als Merkmal — entweder wir fragen
bei SchweizMobil nach, ob es das gibt, oder die Schweiz kommt zunächst
nur mit ihren Sperrungen (Abschnitt 7). Die Vereine in
Baden-Württemberg gehen nur mit schriftlicher Erlaubnis.

## 5. Aufbau

### 5.1 Der CI-Job

- `tool/official/sources.json` — die Quellenliste: Kennung, Name,
  Region, Lizenz, Quellenangabe (Wortlaut), Abrufweg, Filter auf
  Singletrails, bei Vereinen der Verweis auf die Erlaubnis (Datum; das
  Schreiben selbst liegt im DocuHub, nicht im Repo).
- `tool/official_trails.py` (nur Standardbibliothek, wie die anderen
  Werkzeuge) holt jede Quelle, filtert, bringt sie in das Format unten,
  vereinfacht die Linien (dieselbe Toleranz wie der Import) und schreibt
  je Region eine Datei plus einen Index.
- `official-trails.yml`, wöchentlich und von Hand auslösbar. Ergebnis
  sind die Assets eines festen Releases `official-trails` (kein
  App-Release, kein Tag-Bump); `github.com` steht schon in der
  Datenschutzerklärung.
- **Wächter:** Eine Quelle, die nicht antwortet, behält ihre letzte
  Datei (Run-Summary sagt es). Eine Quelle, die plötzlich mehr als ein
  Drittel ihrer Trails verliert, wird NICHT veröffentlicht — ein
  kaputter Export soll keine Region leeren. Jede Datei trägt Stand und
  Quelle.
- `--self-test` mit kleinen Beispieldateien je Abrufweg, in CI.

### 5.2 Das Format

Eine GeoJSON-FeatureCollection je Region, jedes Feature eine
`LineString` mit:

| Feld | Inhalt |
|---|---|
| `id` | `quelle:originalkennung`, stabil über Läufe |
| `name` | wie in der Quelle |
| `kind` | `trail` oder `bikepark` |
| `difficulty` | Originalwert der Quelle (z. B. „rot") |
| `level` | vereinheitlicht: `easy`, `medium`, `hard`, `expert`, oder leer |
| `source` | Kennung aus `sources.json` |
| `updated` | Stand der Quelle |

Der Index (`index.json`) nennt je Region Datei, Rahmen (Bounding Box),
Anzahl, Stand und die Quellen mit Lizenz und Quellenangabe.

**Keine S-Grade.** Die Farbskalen der Quellen sind keine
Singletrail-Skala; umgerechnet würde eine Einschätzung behauptet, die
niemand abgegeben hat. Das Blatt zeigt den Originalwert.

### 5.3 In der App

- Eine Ebene „Offizielle Trails", ein- und ausschaltbar (Vorgabe: an,
  Entscheidung 5), gerätelokal wie der Orte-Filter.
- Geladen wird eine Region erst, wenn der Ausschnitt ihren Rahmen
  berührt; gemerkt auf dem Gerät, neu geholt, wenn der Index einen neuen
  Stand nennt.
- **Eigene Linienart**, gestrichelt und in einer Farbe, die keine
  Trail-Farbe ist (Grün, Blau, Orange sagen, was ICH mit einem Trail zu
  tun habe). Unter den Trails des Netzes, über den Orten.
- Ein Tipp öffnet ein eigenes Blatt: Name, Art, Schwierigkeit laut
  Quelle, Stand, Quellenangabe mit Lizenz, Link zur Quelle. Keine
  Beiträge, keine Hinweise, kein Status — dafür gibt es die Trails des
  Netzes.
- **„Auch ausgeschildert als …"** im Trail-Blatt, wenn ein Trail des
  Netzes eine offizielle Linie deckt — gerechnet auf dem Gerät mit
  derselben Deckung wie der Abgleich (Korridor 15 m, ≥ 0,8). Beide
  Linien sieht der Nutzer ohnehin; über Netzgrenzen geht nichts
  (Konzept 12).
- Die Quellenangaben der sichtbaren Regionen stehen in der
  Karten-Attribution, solange die Ebene an ist.

## 6. Vor dem Bauen zu klären

1. **Vereine und Bikeparks:** Anfrage je Verein durch den Betreiber
   (was wir zeigen, mit welcher Quellenangabe, dass nichts verkauft
   wird, dass die Zusage jederzeit widerrufbar ist). Ohne Zusage bleibt
   der Verein draußen; die Zusage liegt im DocuHub.
2. **Tirol:** genauen Datensatz und Lizenz bestimmen, prüfen, ob die
   Singletrails als eigene Kategorie herauskommen.
3. **Vorarlberg:** prüfen, ob Singletrails im Mountainbikenetz
   unterscheidbar sind.
4. **Schweiz:** bei SchweizMobil anfragen, ob es Singletrail-Abschnitte
   als Daten gibt; sonst zunächst nur die Sperrungen (Abschnitt 7).
5. **Rechtlich** (Konzept 7): Die Ebene sagt „ausgewiesen laut Quelle",
   nie etwas über andere Trails. Ein Satz im Blatt, keine Kennzeichnung
   der übrigen Trails als „inoffiziell".

## 7. Später

- **Sperrungen** aus offiziellen Quellen (Schweiz täglich) als Warnung
  an offiziellen Linien — und, wenn ein Trail des Netzes eine gesperrte
  offizielle Linie deckt, als Hinweis im Trail-Blatt. Anders als der
  Status eines Buddys kommt diese Meldung von der Quelle und sagt das.
- Weitere Regionen, sobald eine Quelle die Bedingungen aus Abschnitt 4
  erfüllt.

## 8. Fahrplan

1. Dieses Konzept (Issue #13).
2. Pipeline mit Tirol als erster Quelle, Format, Wächter, Self-Test.
3. Ebene in der App mit Blatt und Attribution; Datenschutzerklärung
   (kein neuer Host, aber ein neuer Abruf).
4. „Auch ausgeschildert als …" im Trail-Blatt.
5. Vereine, sobald Zusagen da sind; Vorarlberg und Schweiz nach Klärung.
