# Routing-Messung (#35): tragen unsere Daten die eigene Engine?

*Messplan: `docs/konzept-routing.md` Abschnitt 6. Werkzeug:
`tool/route_measure.py` (Selbsttest in CI). Dieser Bericht nennt
Kennzahlen, keine Orte, keine Namen von Fahrten. Stand: 2026-10-01,
Teil 1 (Höhen) gemessen; Teil 2 (Graph, Laufzeit) kommt aus dem
CI-Lauf `route-measure.yml`, Teil 3 (eigene Aufstiege) aus dem lokalen
Lauf des Betreibers — beide werden hier nachgetragen.*

## Ergebnis in drei Sätzen (vorläufig)

1. **Das PilzBuddy-Gitter reicht fürs Routing nicht** (M3): 250-m-Waben
   mit 20-m-Stufen treffen die Abstiegsmeter der offiziellen Tiroler
   Trails mit 42 % Medianfehler und überschätzen sie um ein Viertel;
   das DEM direkt (90 m) trifft sie mit 5 % und zu zwei Dritteln
   innerhalb ±10 %. Weg B aus dem Konzept (Höhenkacheln je Bereich,
   90 m, die Auflösung von Locus) ist damit gesetzt.
2. **Der DEM-Leser stimmt**: Innsbruck 581 m (Karte: 574), Patscherkofel
   2240 m (2246), Hafelekar 2273 m (2334 — an einem Grat glättet eine
   90-m-Zelle den Gipfel, das ist die Auflösung, kein Lesefehler).
3. Graph (M1), Laufzeit (M5), Klassenmix und Aufstiegstreue (M2, M4):
   noch offen, siehe unten.

## M3 — Höhen (Tirol-Hälfte, gemessen 2026-10-01)

168 der 181 offiziellen Trails (Daten-Branch `official-trails-data`,
Stand 2026-09-23) nennen Abstiegsmeter. Entlang ihrer Linie, 50-m-
Abtastung, 10 m Hysterese, gegen die Zahl der Quelle (die ist selbst
gerechnet — eine Bodenwahrheit sind erst die GPX-Höhen des lokalen
Laufs):

| Höhenquelle | Medianfehler | 90. Perzentil | innerhalb ±10 % | Median DEM/Quelle |
|---|---|---|---|---|
| DEM direkt (Copernicus GLO-90, 90 m, bilinear) | 5 % | 53 % | 67 % | 0,99 |
| Gitter A simuliert (250-m-Waben, Mittel, 20-m-Stufen) | 42 % | 167 % | 15 % | 1,25 |

Hysterese 3 / 5 / 10 / 20 m am DEM direkt: Medianfehler 6 / 5 / 5 / 5 %,
Verhältnis 1,01 / 1,00 / 0,99 / 0,98 — 10 m bleibt. Anstieg (nur 15
Trails mit ≥ 50 hm Anstiegsangabe): Median 20 %, zu wenig Material für
eine Aussage; die Aufstiegsfrage beantwortet der lokale Lauf an echten
Fahrten.

Warum das Gitter durchfällt, obwohl die Waben-MITTEL stimmen: Entlang
einer Linie springt der Wert an jeder Wabengrenze um ganze 20-m-Stufen,
und auf einem Hang in Kehren liegen Anfang und Ende einer Kehre oft in
derselben Wabe — das Höhenprofil wird eine Treppe, deren Stufen die
Hysterese von 10 m nicht mehr als Rauschen erkennt. Für die Pilzampel
(Temperaturkorrektur je Spot) ist dasselbe Gitter richtig; für Routing
ist die Linie die Einheit, nicht der Punkt.

**Folge für Schritt 2 des Plans:** Höhenkacheln vom eigenen Host, 1
Byte je 90-m-Zelle (Stufen von 10 m über eine Kachel-Basis, oder
Zeilen-Delta wie beim Regengitter — das entscheidet der Bau), gezippt
~3 KB je z13-Kachel, geladen mit dem Bereich wie die Orte-Zellen. Kein
neues Netzziel.

## M1 — Zusammenhang des z13-Graphen (CI-Lauf, offen)

`route-measure.yml` von Hand starten; die Run-Summary zeigt je Rahmen
Kanten, Knoten, Komponenten, den Anteil der größten Komponente und wie
viele Trail-Enden innerhalb von 30 m an ihr hängen — einmal streng
(nur geteilte Knoten) und einmal mit verbundenen Enden (≤ 2 m, die
Kachelgrenzen). Schwelle: ≥ 90 % der Enden an der größten Komponente,
größte Komponente ≥ 95 % der Kantenlänge.

## M5 — Laufzeit (CI-Lauf, offen)

Derselbe Lauf: Kacheln lesen, Graph bauen, Höhen je Kante, Dijkstra von
jedem Trail-Ende mit Budget. Schwelle < 2 s auf dem Rechner ohne das
Lesen der Kacheln.

## M2 / M4 / Kalibrierung — eigene Fahrten (lokaler Lauf, offen)

`python3 tool/route_measure.py rides --trails <Sammlung> --rides
<Ordner mit GPX-Exporten> --profile bio` beim Betreiber. Der Bericht
(`build/route/rides.md`) nennt den Klassenmix der Aufstiegsabschnitte,
die Steigrate je dominanter Klasse und für jede Fahrt, ob der A* vom
Fahrtstart zum ersten bekannten Trailkopf den gefahrenen Weg findet
(gleich nach den Abgleich-Schwellen 15 m / 0,8). Schwelle M4: ≥ 70 %
gleich, Rest erklärbar.

## Was aus dem Werkzeug bleibt

- Der MVT-Decoder, der COG-Leser, Klassentabelle, Zeitmodell, Graph,
  Dijkstra und A* sind die Referenz für die Dart-Engine (Schritt 3);
  Werkzeug und Dart ändern sich im selben PR, wie bei `trail_match.py`.
- Die Kacheln werden beim Lesen auf ihren Rahmen ZUGESCHNITTEN
  (Puffer weg), sonst läge jeder Weg nahe einer Kachelgrenze doppelt im
  Graphen; die beiden Enden an der Grenze bindet das Verbinden ≤ 2 m.
  Dieselbe Regel braucht der Graph auf dem Gerät.
