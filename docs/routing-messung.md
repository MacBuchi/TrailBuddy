# Routing-Messung (#35): tragen unsere Daten die eigene Engine?

*Messplan: `docs/konzept-routing.md` Abschnitt 6. Werkzeug:
`tool/route_measure.py` (Selbsttest in CI), Tirol-Lauf `route-measure.yml`
(Run 4 vom 2026-10-01, Kacheln `dach-20261001.pmtiles` vom eigenen Host,
offizielle Trails vom Daten-Branch, Höhen Copernicus GLO-90). Dieser
Bericht nennt Kennzahlen, keine Orte, keine Namen von Fahrten. Stand:
2026-10-01 — M1, M3 (Tirol-Hälfte) und M5 gemessen; M2, M4 und die
Kalibrierung kommen aus dem lokalen Lauf des Betreibers an seinen Fahrten
und werden hier nachgetragen.*

## Ergebnis in fünf Sätzen

1. **Die z13-Kacheln tragen den Graphen — mit zwei Reparaturen beim
   Bauen** (M1): Ohne sie zerfällt das Wegenetz eines 20-km-Rahmens in
   500 bis 8 000 Stücke, die größte Komponente hält nur 50–80 % der
   Kantenlänge. Werden tote Enden innerhalb von 2 m an den nächsten
   anderen Weg gebunden (auch mitten in ein Segment) und Kreuzungen
   ohne gemeinsamen Knoten geteilt (gleiche Ebene, keine Brücke, kein
   Tunnel), hält die größte Komponente 95 / 97 / 98 % und trägt
   98 / 93 / 100 % der Trail-Enden. Beide Schwellen sind erfüllt.
2. **Ein größerer Verbindungsradius bringt nichts mehr**: 10 m statt
   2 m heben die größte Komponente um 0–2 Punkte und keinen Trail-End-
   Anschluss. 2 m bleibt.
3. **Das PilzBuddy-Gitter reicht fürs Routing nicht** (M3): 250-m-Waben
   mit 20-m-Stufen treffen die Abstiegsmeter der offiziellen Trails mit
   42 % Medianfehler und überschätzen sie um ein Viertel; das DEM
   direkt (90 m) trifft sie mit 5 % und zu zwei Dritteln innerhalb
   ±10 %. Weg B aus dem Konzept (Höhenkacheln je Bereich, 90 m, die
   Auflösung von Locus) ist gesetzt.
4. **Die Laufzeit ist unkritisch** (M5): Graph aus 25 000 Wegstücken in
   ~2 s, Dijkstra von 22 Trail-Enden mit 3-h-Budget in 3,7 s — in
   Python, auf dem Runner. Teuer ist nur das Lesen der Kacheln vom Host
   (18–22 s je 49 Kacheln über Range-Anfragen); auf dem Gerät liegen sie
   im gespeicherten Bereich.
5. Offen: Klassenmix und Aufstiegstreue an echten Fahrten (M2, M4), die
   Steigraten je Profil — der lokale Lauf.

## M1 — Zusammenhang des z13-Graphen

Drei 20-km-Rahmen um die dichtesten Gruppen offizieller Trails (Ötztal,
Kitzbüheler Alpen, Innsbruck — als Gegend, nicht als Trail). Je Rahmen
49 Kacheln; „Wegstücke" sind die nutzbaren Linien nach Klassentabelle
und Zuschnitt auf den Kachelrahmen (der Puffer der Kacheln fällt weg,
sonst läge jeder Weg nahe einer Grenze doppelt im Graphen).

| Rahmen | Wegstücke | Graph | Komponenten | größte (Länge) | Trail-Enden ≤ 30 m | davon an der größten |
|---|---|---|---|---|---|---|
| 1 | 3 035 | nur geteilte Knoten | 499 | 57 % | 63 / 64 | 60 / 64 (94 %) |
| | | + Enden ≤ 2 m verbunden | 83 | 95 % | 63 / 64 | 63 / 64 (98 %) |
| | | + Kreuzungen geteilt | 73 | 95 % | 63 / 64 | 63 / 64 (98 %) |
| | | ≤ 10 m + Kreuzungen | 56 | 97 % | 63 / 64 | 63 / 64 (98 %) |
| 2 | 13 706 | nur geteilte Knoten | 3 611 | 50 % | 43 / 46 | 22 / 46 (48 %) |
| | | + Enden ≤ 2 m verbunden | 392 | 97 % | 43 / 46 | 39 / 46 (85 %) |
| | | + Kreuzungen geteilt | 332 | 97 % | 43 / 46 | 43 / 46 (93 %) |
| | | ≤ 10 m + Kreuzungen | 349 | 98 % | 43 / 46 | 43 / 46 (93 %) |
| 3 | 24 722 | nur geteilte Knoten | 8 093 | 80 % | 44 / 44 | 34 / 44 (77 %) |
| | | + Enden ≤ 2 m verbunden | 989 | 98 % | 44 / 44 | 44 / 44 (100 %) |
| | | + Kreuzungen geteilt | 855 | 98 % | 44 / 44 | 44 / 44 (100 %) |
| | | ≤ 10 m + Kreuzungen | 903 | 98 % | 44 / 44 | 44 / 44 (100 %) |

Was die Diagnose dazu sagt:

- **Tote Enden** im strengen Graphen: 2 174 / 13 448 / 25 375. Davon
  liegt der nächste andere Weg bei 42 / 37 / 44 % innerhalb von 2 m —
  das sind die Kachelgrenzen UND die T-Kreuzungen, deren Knoten die
  Vereinfachung aus dem durchgehenden Weg entfernt hat. 26 / 24 / 12 %
  liegen weiter als 30 m weg: echte Sackgassen (Forstwege enden im
  Wald, Zufahrten am Haus).
- **Kreuzungen ohne gemeinsamen Knoten**: 417 / 1 983 / 4 019 je Rahmen.
  Sie sind der Hebel für die Trail-Enden in Rahmen 2 (85 → 93 %); für
  die Kantenlänge tun sie wenig, weil die 2-m-Verbindung die meisten
  Stücke schon erreicht.
- **Kleinstteile** unter 200 m nach allen Reparaturen: 33 / 270 / 802
  Komponenten, zusammen 0 / 0 / 1 % der Länge — Stichwege hinter
  Privatstraßen und Zufahrten, die die Klassentabelle verwirft. Kein
  Routing-Verlust.
- **Nicht angeschlossene Trail-Enden** (1 / 3 / 0): kein Weg innerhalb
  von 30 m — Trails, die an einer Bergstation oder auf einer Wiese
  beginnen. Der Planer sagt dann „nicht erreichbar".

Die drei Zahlen, die das Ergebnis erst herstellten, stehen im
Werkzeug und gehören in die Dart-Engine (Schritt 3):

1. **Zuschnitt auf den Kachelrahmen**, damit der Puffer der Kacheln
   keinen Weg doppelt legt; die beiden Enden an der Grenze bindet die
   Verbindung.
2. **Verbindung ≤ 2 m, auch mitten in ein Segment.** Der erste Lauf
   verband nur Knoten mit Knoten (554 Verbindungen, wo 11 000 Enden in
   Reichweite lagen) — die Suche nach dem nächsten Segment fand das
   eigene, in Abstand 0, und übersprang den Fall. Ein Selbsttest hält
   die T-Kreuzung seither fest.
3. **Kreuzungen teilen**, aber nur auf derselben Ebene: Die Kacheln
   tragen `is_bridge` und `is_tunnel`, und eine Brücke über eine Straße
   ist keine Kreuzung.

## M3 — Höhen (Tirol-Hälfte, gemessen 2026-10-01)

168 der 181 offiziellen Trails nennen Abstiegsmeter. Entlang ihrer
Linie, 50-m-Abtastung, 10 m Hysterese, gegen die Zahl der Quelle (die
ist selbst gerechnet — eine Bodenwahrheit sind erst die GPX-Höhen des
lokalen Laufs):

| Höhenquelle | Medianfehler | 90. Perzentil | innerhalb ±10 % | Median DEM/Quelle |
|---|---|---|---|---|
| DEM direkt (Copernicus GLO-90, 90 m, bilinear) | 5 % | 53 % | 67 % | 0,99 |
| Gitter A simuliert (250-m-Waben, Mittel, 20-m-Stufen) | 42 % | 167 % | 15 % | 1,25 |

Hysterese 3 / 5 / 10 / 20 m am DEM direkt: Medianfehler 6 / 5 / 5 / 5 %,
Verhältnis 1,01 / 1,00 / 0,99 / 0,98 — 10 m bleibt. Je Rahmen streut
der Median zwischen 4 % (Kitzbühel) und 18 % (Innsbruck, n = 21); die
Zahl über alle 168 ist die belastbare. Der DEM-Leser wurde an drei
bekannten Höhen geprüft (Innsbruck 581 m zu 574, Patscherkofel 2240 zu
2246, Hafelekar 2273 zu 2334 — an einem Grat glättet eine 90-m-Zelle den
Gipfel, das ist die Auflösung, kein Lesefehler).

Warum das Gitter durchfällt, obwohl die Waben-MITTEL stimmen: Entlang
einer Linie springt der Wert an jeder Wabengrenze um ganze 20-m-Stufen,
und in Kehren liegen Anfang und Ende einer Kehre oft in derselben Wabe
— das Höhenprofil wird eine Treppe, deren Stufen die Hysterese nicht
mehr als Rauschen erkennt. Für die Pilzampel (Temperaturkorrektur je
Spot) ist dasselbe Gitter richtig; für Routing ist die Linie die
Einheit, nicht der Punkt.

**Folge für Schritt 2 des Plans:** Höhenkacheln vom eigenen Host, 1 Byte
je 90-m-Zelle, gezippt ~3 KB je z13-Kachel, geladen mit dem Bereich wie
die Orte-Zellen. Kein neues Netzziel.

## M5 — Laufzeit (Python auf dem Runner)

| Rahmen | Kacheln lesen (Host, Range) | Graph bauen (zweimal) | Höhen je Kante | Dijkstra von allen Trail-Enden, 3 h | erreichbare Trail-Anfänge je Ende |
|---|---|---|---|---|---|
| 1 (3 035 Wegstücke) | 19,4 s | 0,60 s | 13,7 s (4 DEM-Kacheln geholt) | 0,38 s (31 Läufe) | Median 27, max 30 |
| 2 (13 706) | 18,7 s | 2,42 s | 3,8 s | 1,32 s (21) | Median 12, max 16 |
| 3 (24 722) | 18,2 s | 4,28 s | 0,9 s | 3,70 s (22) | Median 18, max 21 |

Graph plus Dijkstra liegen in Python bei 0,7–6 s je Rahmen; die
Schwelle „< 2 s auf dem Rechner" hält der dichteste Rahmen damit nicht,
die „< 5 s auf dem Telefon" ist für die Dart-Engine (AOT, ohne die
Diagnose-Varianten) zu messen — Schritt 3. Das Lesen der Kacheln ist auf
dem Gerät kein Thema (gespeicherter Bereich, keine Range-Anfragen); die
DEM-Zeit ist der Download der Copernicus-Kacheln, nicht die Rechnung.

## Beispiel-Aufstiege (zum Ansehen)

Ende eines Trails zum nächsten Anfang eines anderen, Profil Bio-Bike,
Kostentabelle aus dem Konzept:

| Luftlinie | Weg | bergauf | bergab | Wanderweg | Zeit | Klassenmix |
|---|---|---|---|---|---|---|
| 0,9 km | 4,2 km | 509 hm | 14 hm | 0 | 85 min | Zufahrt 4,2 km |
| 2,3 km | 4,8 km | 491 hm | 22 hm | 0,8 km | 91 min | Forstweg 2,5, Nebenstraße 1,4, Wanderweg 0,8 |
| 1,2 km | 1,9 km | 210 hm | 11 hm | 0,1 km | 37 min | Forstweg 1,8 |
| 0,4 km | 2,1 km | 145 hm | 15 hm | 0,2 km | 28 min | Forstweg 1,4, Bundesstraße 0,3, Wanderweg 0,2 |
| 0,6 km | 2,7 km | 116 hm | 0 hm | 1,2 km | 31 min | Wanderweg 1,1, Nebenstraße 0,9, Bundesstraße 0,4 |

Die Wege sehen aus wie Wege, die man fährt: Forststraße und Almzufahrt
zuerst, Wanderweg dort, wo es kürzer ist als der Umweg, Bundesstraße nur
als Brücke über wenige hundert Meter. Ob das stimmt, sagt M4.

## #194 — Steile Anstiege (Run 7 vom 2026-10-02)

Feldbericht aus 0.74.0: „Super steile Anstiege (falls nicht zum
deklarierten Uphill-Trail gehörend) sollten bestraft werden, insbesondere
wenn kein Asphalt sondern nur Weg." Gemessen wird, wie steil die Klassen
auf dem DEM sind und was ein Aufschlag ab einer Grenze an den
Beispiel-Aufstiegen ändert. Höhen alle 50 m je Kante, in ihrer
Aufwärtsrichtung; „geglättet" heißt Höhen UND Positionen über drei Proben
gemittelt (`steep_excess`). Rahmen 2 und 3:

| Klasse | Steigung Median / 90. / 99. Perzentil | hm über 15 %, roh / geglättet | über 20 %, geglättet |
|---|---|---|---|
| Forstweg | 9 / 18 / 29–30 % | 22–23 % / 10 % | 3–4 % |
| Zufahrt | 7–8 / 15–16 / 26–28 % | 16–21 % / 6–7 % | 2–3 % |
| Nebenstraße | 7 / 14–15 / 25 % | 12–15 % / 4–6 % | 1 % |
| Wanderweg | 13–14 / 30–36 / 51–66 % | 39–47 % / 29–36 % | 18–25 % |

Vier Dinge daraus:

1. **Roh doppelt so viel wie geglättet** — auf allen Klassen. Ein Weg
   liegt ein paar Meter neben seiner Linie im 90-m-Modell, und quer zu
   einer steilen Flanke ist das allein schon einige Prozent je
   50-m-Schritt. Gerechnet wird geglättet.
2. **15 % trifft das steilste Zehntel der Forstweg-Höhenmeter**, auf
   Straßen ein Zwanzigstel; das 90. Perzentil der Forstwege liegt bei
   18 %. Das ist „sehr steil" für eine Forststraße, und das DEM glättet
   eine echte Rampe eher flacher, als sie ist. **Grenze 15 %**
   (`STEEP_GRADE`, `kSteepGrade`).
3. **Der Aufschlag**: Jeder Höhenmeter über der Grenze kostet seine
   Steigzeit noch einmal, mal drei auf Schotter und Pfad, mal eins auf
   Asphalt, auf Stufen nichts (dort wird ohnehin geschoben). Bio auf
   Forstweg: 24 s je steilem Höhenmeter. Kosten, keine Minuten — das
   Zeitmodell bleibt, was die Fahrten kalibrieren.
4. **Die Wirkung**: 3 bzw. 4 von 15 Beispiel-Aufstiegen nehmen einen
   anderen Weg, die steilen Höhenmeter sinken um ein Drittel (291 → 202,
   228 → 161). Wo sich der Weg ändert, wird er im Median 20–31 % länger,
   höchstens 41–52 % — das Beispiel „1,9 km, 210 hm" wird „2,7 km,
   226 hm" mit der Hälfte der steilen Meter. Wanderwege sind von sich aus
   steil (ein Drittel ihrer Höhenmeter über 15 %); der Aufschlag macht
   sie bergauf noch einmal teurer, zusätzlich zu ×1,4.

Uphill-Trails und Verbinder tragen keinen Aufschlag — sie sind der
Anstieg, den jemand gewählt hat (#185). Der Feldtest (#188) prüft Grenze
und Faktoren mit.

## #188 — Rechenzeit des Planers (Dart, 2026-10-02)

Der Rundenplaner rechnete bis 0.80.0 im UI-Isolate. Gemessen mit
`test/routing/perf_loop_planner_measure.dart` (von Hand, nicht in CI) auf
einem erfundenen Netz in der Größe des dichtesten Tirol-Rahmens: Gitter
25 × 25 km, 200 m Maschenweite, 31 500 Kanten, Forstweg/Wanderweg/
Nebenstraße im Wechsel, Höhen aus einer glatten Hügelfläche; die Trails
steigen das Gitter hinab, gestreut über 12 km um den Start. Rechner, JIT —
eine untere Grenze für das Telefon. Alle Zeiten in ms; „Pause" ist die
längste Lücke eines 4-ms-Takts im UI-Isolate, also das, was man als
stehende Karte sieht.

| Trails | Budget | Graph bauen | Trails auflegen | an Ort und Stelle (= Pause) | Isolate, 1. Rechnung: Dauer / Pause | Isolate, weitere: Dauer / Pause | Halte |
|---|---|---|---|---|---|---|---|
| 12 | Bio 3 h / 1 000 hm | 248 | 48 | 290 | 562 / 276 | 207 / 11 | 1 |
| 30 | Bio 3 h / 1 000 hm | 209 | 41 | 466 | 906 / 352 | 521 / 23 | 1 |
| 40 | Bio 5 h / 1 600 hm | 304 | 53 | 1 171 | 1 822 / 301 | 1 586 / 31 | 4 |
| 60 | E-Bike 5 h / 2 500 hm | 112 | 52 | 2 351 | 2 351 / 289 | 2 005 / 23 | 8 |

Drei Befunde:

1. **Die Rechnung wächst mit der Auswahl**, nicht mit dem Netz: je
   Trail-Ende ein begrenzter Dijkstra über das ganze Budget, dazu 300 ms
   lokale Suche (fester Deckel). Ab 30–40 Trails steht die Oberfläche auf
   dem Rechner über eine Sekunde, auf dem Telefon länger — die Schwelle
   aus #188 („spürbar") ist damit ohne Gerät überschritten.
2. **`Isolate.run` je Rechnung hilft kaum**: Das Senden kopiert den
   Graphen IM UI-Isolate, und das allein sind 0,3–0,6 s Pause. Deshalb
   ein dauerhafter Rechen-Isolate (`loop_plan_runner.dart`, seit 0.80.1):
   Der Graph geht einmal hinüber (~0,3 s Pause, einmal je geladenem
   Graphen), jede weitere Rechnung schickt nur Start, Budget, Profil und
   Trails — 11–31 ms Pause, unabhängig von der Auswahl.
3. **Was bleibt, ist das Laden**: Graph bauen (0,1–0,3 s) und Trails
   auflegen (≤ 0,1 s) laufen weiter im UI-Isolate, dazu das einmalige
   Senden. Sie hinüberzunehmen hieße, die Kacheln roh zu schicken und
   drüben zu dekodieren — erst, wenn das Telefon dort eine Pause zeigt.

Die Halte sind wenige, weil die Hügelfläche steil und das Budget knapp
ist; gemessen wird die Zeit, nicht die Güte der Runde.

## M2 / M4 / Kalibrierung — eigene Fahrten (lokaler Lauf, offen)

`python3 tool/route_measure.py rides --trails <Sammlung> --rides
<Ordner mit GPX-Fahrten> --profile bio` beim Betreiber. Der Bericht
(`build/route/rides.md`) nennt den Klassenmix der Aufstiegsabschnitte,
die Steigrate je dominanter Klasse und für jede Fahrt, ob der A* vom
Fahrtstart zum ersten bekannten Trailkopf den gefahrenen Weg findet
(gleich nach den Abgleich-Schwellen 15 m / 0,8). Schwelle M4: ≥ 70 %
gleich, Rest erklärbar.

## Was aus dem Werkzeug bleibt

- Der MVT-Decoder, der COG-Leser, Klassentabelle, Zeitmodell, Graph
  (Zuschnitt, Verbindung, Kreuzungen), Dijkstra und A* sind die Referenz
  für die Dart-Engine (Schritt 3); Werkzeug und Dart ändern sich im
  selben PR, wie bei `trail_match.py`.
- Vier CI-Läufe bis zum Ergebnis: Lauf 1 hing in einer O(N·E)-Suche
  (Zellenraster seither), Lauf 3 zeigte den Verbindungs-Fehler, Lauf 4
  ist dieser Bericht. Die Reihenfolge steht hier, damit die nächste
  Messung nicht dieselben Umwege geht.
