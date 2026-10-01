# Konzept: Routing-Engine — Anforderungsprofil und Plan

*Entwurf vom 2026-10-01 für #35 (Messung) und #158 (Trail-zuerst-Planer).
Antwort auf die Betreiberfrage vom selben Tag: „Macht ein Zusatztool wie
BRouter Sinn? Besser wäre eine eigene Engine." — und auf die Auflage,
VOR dem Bauen einen sauberen Plan mit Anforderungsprofil zu machen.
Zahlen in diesem Dokument sind Vorschläge, solange Abschnitt 8 sie
nicht als entschieden führt; was die Messung (#35) klären muss, steht
in Abschnitt 6. Dieses Dokument ergänzt `konzept-trails.md` Abschnitt 9
und 13; bei Widerspruch gilt das Hauptkonzept.*

## 0. Die Entscheidung: eigene Engine, kein BRouter

Entschieden vom Betreiber am 2026-10-01. Die Gründe, damit die nächste
Diskussion nicht bei null beginnt:

- **BRouter ist eine zweite App.** Locus ruft sie über eine
  Schnittstelle; sie muss getrennt installiert und mit eigenen
  Segmentdateien (5°×5°, von brouter.de) versorgt werden. Für TrailBuddy
  hieße das: nur Android, ein neues Netzziel, ein zweiter Datenstand
  neben unseren Kacheln — ein Weg wäre auf der Karte da und im Router
  nicht, oder umgekehrt. Im Web gibt es BRouter nicht, und die Web-App
  soll gleich viel können.
- **BRouter beantwortet die falsche Frage.** Es rechnet von A nach B.
  Der Planer braucht die Aufstiege zwischen ALLEN Trail-Enden und
  verkettet sie unter einem Budget; „möglichst viele meiner Trails
  mitnehmen" kann kein BRouter-Profil ausdrücken. Als Zulieferer für die
  Einzelaufstiege wäre es hunderte Anfragen an eine fremde App.
- **Der Wegegraph liegt schon auf dem Gerät.** Die gespeicherten
  Bereiche tragen die Wege bis Zoom 13, und das Zerlege-Blatt liest sie
  (`road_index.dart`). Eine eigene Engine ist damit offline von Geburt
  an, läuft auf beiden Plattformen und braucht keinen neuen Host.
- **Was fehlt, ist überschaubar:** ein A* mit Kostenfunktion (einige
  hundert Zeilen Dart), ein Höhenmodell (Copernicus-DEM, ohne
  Bibliothek lesbar — am 2026-10-01 geprüft), und die Messung, ob die
  Kacheln als Wegenetz REICHEN (Abschnitt 6). Fällt die Messung durch,
  liegt die Antwort in der eigenen Pipeline (`map-data.yml`), nicht in
  einem Fremdprogramm.

Valhalla und jeder Server-Router scheiden aus demselben Grund aus wie
bisher: kostet Geld und ist im Funkloch tot, wo geroutet wird.

## 1. Was die Engine tun soll — und was nicht

Zwei Funktionen, eine Engine:

1. **Zum Trailkopf, offline** (#158 Schritt 4). Vom eigenen Standort
   oder einem getippten Punkt zum Anfang EINES Trails, als Aufstieg nach
   Wegklasse bewertet. Ergebnis: Linie auf der Karte, Länge, Höhenmeter,
   geschätzte Zeit, Anteil Wanderweg. Ersetzt die Übergabe an die
   Navi-App (#151) nicht, sondern ergänzt sie: Die Navi-App kennt die
   Straße zum Parkplatz, die Engine kennt den Forstweg vom Parkplatz zum
   Trailkopf.
2. **Die Trail-zuerst-Runde** (#158 Schritt 5). Start (und wahlweise
   Ziel = Start), Budget, Pool. Ergebnis: eine Runde, die möglichst viele
   sichtbare Trails BERGAB in ihrer Richtung mitnimmt, verbunden durch
   Aufstiege mit möglichst wenig verschenkter Höhe. Gespeichert als
   geplante Fahrt (`planned`, Konzept 5.2), exportiert als GPX (#150).

Nicht-Ziele, damit sie nicht hineinwachsen:

- **Keine Abbiegehinweise, keine Sprachausgabe** (Konzept 13). Die
  Runde geht als GPX an die Navi-App des Nutzers.
- **Kein Routing über fremde Gegenden.** Gerechnet wird nur, wo ein
  gespeicherter Bereich liegt; ohne Bereich sagt das Blatt das und
  bietet die Übergabe an.
- **Kein Urteil über Erlaubnis** (Konzept 7). Die Engine plant über
  Wanderwege, wenn der Aufschlag trotzdem gewinnt, und SAGT es. Sie
  sagt nie, dass ein Weg befahren werden darf.
- **Kein Bergab auf fremden Pfaden.** Verbindungsstücke bergab laufen
  nur über Fahrstraßen und Forstwege. Ein Pfad bergab wäre ein Trail,
  den niemand beigesteuert hat — und genau die Linie, die Konzept 7
  nicht erzeugen will.
- **Keine Daten anderer Nutzer** (Konzept 12): Gerechnet wird über die
  sichtbaren Trails des Aufrufers, auf dem Gerät, nie auf dem Server.

## 2. Anforderungsprofil

### 2.1 Fahrerprofil: Bio-Bike oder E-Bike

Eine Einstellung, gerätelokal (`Settings.riderProfile`), Vorgabe
**Bio-Bike**; änderbar im Profil und im Planer-Blatt (dort für diese
Planung). Das Profil ändert drei Dinge und sonst nichts:

| | Bio-Bike | E-Bike |
|---|---|---|
| Steigrate Forstweg | 450 hm/h | 850 hm/h |
| Steigrate Pfad (fahrend) | 350 hm/h | 650 hm/h |
| Schieben/Tragen (Steig, Stufen) | 300 hm/h, 3 km/h | 220 hm/h, 2,5 km/h |
| Aufschlag Wanderweg bergauf | ×1,4 | ×2,0 |
| Vorgabe Höhenmeter-Budget | 800 hm | 1 400 hm |

Warum der E-Bike-Aufschlag höher ist: Das Rad wiegt 25 kg; was beim
Bio-Bike ein kurzes Schiebestück ist, ist beim E-Bike der Grund, die
Runde nicht noch einmal zu fahren. Das Profil ändert NICHT die
Wegerechte und NICHT die Trail-Seite: Bergab ist ein S2 ein S2.

Die Raten sind Startwerte (Konzept 9: „Aufstieg 400–600 hm/h, Abfahrt
nach Trail-Länge"). **Kalibriert werden sie aus den eigenen Fahrten auf
dem Gerät** (Abschnitt 5, Schritt 6): Die Fahrten tragen Zeit und
GPS-Höhe je Punkt; aus Aufstiegsabschnitten auf Forstwegen folgt die
eigene Steigrate. Nie aus Fahrten anderer.

### 2.2 Zeitmodell

Die Zeit je Kante ist eine Summe aus Strecke und Höhe (nach dem Muster
der Wanderzeit-Formeln, nicht aus einer Geschwindigkeit allein — eine
Geschwindigkeit „12 km/h bergauf" ist am Hang falsch und im Flachen
auch):

    t = L / v(Klasse, Richtung) + max(0, Δh) / Steigrate(Profil, Klasse)

| Klasse / Lage | v (km/h) Bio | v (km/h) E-Bike |
|---|---|---|
| Forstweg, Nebenstraße, flach | 15 | 20 |
| Pfad bergauf (fahrend) | 8 | 10 |
| Steig, Stufen (schiebend) | 3 | 2,5 |
| Straße/Forstweg bergab | 25 | 25 |
| Trail bergab S0 / S1 / S2 / S3 / S4+ | 16 / 12 / 9 / 6 / 4 | gleich |
| Trail ohne Einschätzung bergab | 10 | 10 |

Bergab zählt nur die Strecke (kein Höhenterm), auf Trails über den
S-Grad des Medians (`Trail`-Anzeige, derselbe Wert wie das Schild). Der
Zeitwert ist eine Schätzung und wird so genannt („etwa 2 h 40").

### 2.3 Budget je Planung

Drei Regler im Planer-Blatt, jeder mit Vorgabe; der engste gewinnt:

| Regler | Vorgabe | Spanne | Schritt |
|---|---|---|---|
| Höchstens Zeit | 3 h | 1–6 h | 30 min |
| Höchstens Höhenmeter bergauf | 800 hm (Bio) / 1 400 hm (E) | 200–2 500 | 100 |
| Höchstens Wanderweg bergauf | 2 km | 0–10 km („kein Wanderweg" = 0) | 0,5 km |

Dazu „Start ist auch Ziel" (Vorgabe AN — eine Runde) und wahlweise ein
Zielpunkt. Die Vorgaben merkt sich das Gerät mit der letzten Planung.
Eine Reserve von 10 % auf die Zeit bleibt eingebaut (die Schätzung
kennt keine Pausen).

### 2.4 Wegklassen und Kosten

Die Engine kennt Kanten aus zwei Quellen: **Wege** aus der
`roads`-Ebene der Kacheln (`kind` + `kind_detail` + `access` +
`oneway`) und **Trails** aus dem sichtbaren Netz. Jede Wegekante bekommt
eine Klasse; die Klasse bestimmt Geschwindigkeit, Steigrate, Aufschlag
und ob die Kante überhaupt gilt.

| `kind` / `kind_detail` | Klasse | Aufschlag bergauf | bergab erlaubt | Bemerkung |
|---|---|---|---|---|
| `path` / `track` | Forstweg | 1,0 | ja | Grundlinie — „Schotter/Waldweg bevorzugt" |
| `path` / `cycleway` | Radweg | 1,0 | ja | |
| `minor_road` / `unclassified`, `residential`, `living_street` | Nebenstraße | 1,2 | ja | Asphalt, Verkehr |
| `minor_road` / `service` (ohne `driveway`, `parking_aisle`) | Zufahrt | 1,2 | ja | Almzufahrten sind oft `service` |
| `path` / `path`, `bridleway` | Wanderweg | 1,4 (Bio) / 2,0 (E) | **nein** | zählt gegen „höchstens Wanderweg" |
| `path` / `footway`, `pedestrian` | Fußweg | 2,0 | nein | im Ort als Lücke brauchbar |
| `path` / `steps` | Stufen | 3,0, schiebend | nein | nur als letzte Brücke |
| `medium_road` (tertiary) | Landstraße | 1,6 | ja | |
| `major_road` / `secondary` | Hauptstraße | 2,5 | ja | |
| `major_road` / `primary` | Bundesstraße | 4,0 | ja | nie ausgeschlossen (#158) |
| `highway` (motorway, trunk) | — | gesperrt | nein | |
| `access` = `private`, `no` | — | gesperrt | nein | |
| `other` (Rennstrecken, Pisten) | — | gesperrt | nein | |
| `oneway` | — | nur auf Straßenklassen beachtet | | Forstwege und Pfade in beide Richtungen |

Kosten einer Wegekante = geschätzte Zeit × Aufschlag. Der Aufschlag
drückt aus, was die Zeit nicht sagt: Eine Bundesstraße ist nicht
langsam, sie ist falsch. **Bergab auf Wegen kostet zusätzlich die
verschenkte Höhe**: Jeder Meter, den eine Wegekante bergab geht, muss
wieder erstiegen werden, bevor der nächste Trail kommt — er geht als
„verschenkte Höhenmeter" in den Vergleich zweier Pläne und ins Blatt
(„120 hm auf Forstweg verschenkt").

Trailkanten: nur in Trail-Richtung (`reversed` beachtet), nur bergab
gedacht, Kosten = Zeit nach S-Grad, Gewinn = Trail-Meter. Ein Trail mit
bestätigter warnender Meldung (`Trail.status.warns`) ist aus dem Pool,
solange der Nutzer ihn nicht ausdrücklich hineinnimmt; wartende und
„nur für mich"-Trails sind drin (es ist meine Planung).

### 2.5 Was die Kacheln NICHT tragen — und was daraus folgt

Gemessen am 2026-10-01 an den Feldern der `roads`-Ebene (Protomaps
Basemap 4.14): es gibt `kind`, `kind_detail`, `access`, `oneway`,
`is_bridge`, `is_tunnel`, `service`, `ref`, Namen. Es gibt **keinen
Belag** (`surface`, `tracktype`), keine `mtb:scale`, keine `sac_scale`,
keine `incline`, keine `width`. Drei Folgen:

- **„Forstweg" ist eine Annahme**: `track` heißt in OSM „Wirtschaftsweg",
  das kann Schotter sein oder eine Wiesenspur. Für die Aufstiegsplanung
  trägt das: Die Sorte, die wir suchen (geschoben oder gefahren, aber
  breit), ist fast immer `track`.
- **„Wanderweg" ist eine Spanne** von der Forststraße mit
  `highway=path` bis zum Klettersteig. Ohne `sac_scale` lässt sich das
  nicht trennen. Deshalb der Regler „höchstens Wanderweg" und die
  Nennung im Ergebnis — und deshalb misst #35, wie oft die eigenen
  Fahrten überhaupt über `path` bergauf gehen.
- **Wenn die Messung zeigt, dass es nicht reicht**, ist die Antwort
  unsere Pipeline: `map-data.yml` schneidet aus dem Protomaps-Planetbau
  und kann die Felder nicht ergänzen; eine eigene Datei je Region
  (`roads-<build>/<zelle>.json` wie die Orte, aus dem Geofabrik-Extrakt
  mit `surface`, `tracktype`, `sac_scale`, `mtb:scale`) wäre der
  nächste Schritt — auf dem eigenen Host, kein neues Netzziel. Nicht
  vorher bauen.

### 2.6 Höhen

Das Modell hat kein Höhengitter (CLAUDE.md). Die Trails tragen Höhen aus
Aufzeichnungen, die Wege tragen nichts. Zwei Kandidaten, beide aus dem
Copernicus-DEM GLO-90 (offen, ohne Konto, in CI lesbar — geprüft):

- **A — ein Gitter-Asset wie in PilzBuddy** (`elevation_grid.py`: 250-m-
  Waben, 20-m-Stufen, ~3,4 MB für DACH im APK). Offline, ohne neues
  Netzziel, sofort da. Risiko: Auf einer Forststraße in Kehren liegt die
  halbe Steigung in EINER Wabe; die Summe der Höhenmeter über viele
  Waben stimmt grob, die Kante einzeln nicht. Für ein Budget („etwa 800
  hm") reicht ±10 %; ob es das hält, ist Messfrage M3.
- **B — Höhenkacheln je Bereich** vom eigenen Host (1 Byte je 90-m-
  Zelle, ~3 KB je z13-Kachel gezippt), geladen mit dem Bereich wie die
  Orte-Zellen. Genauer, ein zweiter Dateityp, kein neues Netzziel.

Vorschlag: **A messen, B nur bauen, wenn A durchfällt.** Die Höhe einer
Kante wird nicht an den Enden, sondern alle 50 m entlang der Linie
abgetastet und mit einer Hysterese von 10 m zu Anstieg/Abstieg summiert
(die 3 m der Trail-Höhen gelten für aufgezeichnete Höhen, nicht für ein
Gitter). Die Trailkanten behalten ihre aufgezeichneten Höhen.

### 2.7 Daten und Offline

- **Der Graph entsteht aus gespeicherten Bereichen**, z13, Ebene
  `roads`, lesbar über denselben Weg wie `loadRoads`. Keine Kachel, kein
  Weg — und zwar ehrlich: `partial` heißt „nicht planbar", nicht „ein
  halber Plan".
- **Gebaut wird je Planung** für den Rahmen Start ± Reichweite
  (Reichweite = Zeitbudget × 15 km/h / 2, höchstens 25 km), im Isolate,
  und für die Sitzung gemerkt (Schlüssel: Bereichs-Builds + Rahmen). Ein
  20-km-Rahmen sind rund 70 Kacheln und schätzungsweise 20 000
  Wegekanten — das baut ein Telefon in unter einer Sekunde (Messfrage
  M5).
- **Knoten**: Zwei Linien teilen einen Knoten, wenn ihre Punkte auf
  dieselbe Kachelkoordinate fallen (Extent 4096 ⇒ 1,2 m bei z13). An
  Kachelrändern werden Enden innerhalb von 2 m verbunden. Ob die
  Vereinfachung bei z13 Kreuzungen trennt, ist Messfrage M1.
- **Trail-Enden** werden an den nächsten Wegeknoten innerhalb von 30 m
  geheftet (die GPS-Unschärfe des Trailanfangs); liegt keiner da, wird
  der nächste Wegepunkt im Umkreis als Knoten eingefügt. Ein Trail ohne
  Anschluss an beiden Enden ist für den Planer „nicht erreichbar" und
  steht so im Blatt.
- **Kein Netzziel, keine Berechtigung.** Alles kommt von Hosts, die
  die Datenschutzerklärung schon nennt, oder liegt im APK.

## 3. Algorithmus

1. **Aufstiege zwischen allen Trail-Enden** („Zum Trailkopf" ist der
   Sonderfall mit einem Ziel): Dijkstra von jedem Trail-Ende und vom
   Start, begrenzt durch das Budget (abgebrochen, sobald die Kosten das
   Budget übersteigen). Bei N Trails im Rahmen sind das 2N + 1 Läufe auf
   20 000 Kanten — Sekundenbruchteile. Ein A* mit Luftlinien-Heuristik
   für die Einzelanfrage „zum Trailkopf".
2. **Verkettung** (Orienteering-Problem, NP-schwer, hier klein):
   greedy einfügen nach „Trail-Meter je Kostenzuwachs", dann lokale
   Suche (Tausch, Entfernen und Einfügen) mit festem Zeitdeckel
   (300 ms). Jeder Trail höchstens einmal; „diese will ich heute"
   (Pflicht-Trails) werden zuerst eingefügt und nie entfernt.
3. **Zielfunktion**: zuerst mehr **Trail-Meter** (Länge der gefahrenen
   Trails — nicht Anzahl, sonst gewinnen drei kurze gegen einen langen),
   bei Gleichstand weniger Aufstiegs-Höhenmeter, dann weniger
   verschenkte Höhe. Alles unter den drei Budgets aus 2.3.
4. **Ergebnis**: Linie mit Abschnitten (Aufstieg nach Klasse, Trail),
   Summen (Länge, hm bergauf, hm Trail bergab, Zeit, Wanderweg-km,
   verschenkte hm), Liste der Trails in Reihenfolge, die Trails, die
   NICHT hineingepasst haben und warum (zu weit, Budget, nicht
   erreichbar).

Alles pur in Dart (`lib/features/routing/`: `road_graph.dart`,
`route_profile.dart`, `route_search.dart`, `loop_planner.dart`), ohne
Widgets, geprüft mit erzeugten Kacheln wie `road_index_test`. Das
Python-Werkzeug `tool/route_measure.py` ist die Referenz für die
Messung und spiegelt Kostentabelle und Zeitmodell; wie bei
`trail_match.py` kommen Werkzeug und Dart bei Änderungen im SELBEN PR.

## 4. Oberfläche

- **Trail-Blatt**: „Zum Trailkopf" neben „Anfahrt" (#151). Ergebnis
  als Vorschau auf der Karte (dieselbe Strecke wie das Zerlege-Blatt:
  Fahrt blass, Aufstieg nach Klasse), darunter die Summen und der
  Satz zum Wanderweg. „Als Fahrt speichern" (geplant) und „Als GPX".
- **Planer-Blatt** vom Kartenknopf „Idee" (der heute das Feedback
  trägt — Entscheidung 8.7) oder aus dem Reiter Trails: Start (Position
  / getippt), Profil, drei Regler, Pool (alle sichtbaren im Rahmen,
  abwählbar; Pflicht-Haken), Rechnen, Ergebnis wie oben. Ohne Bereich:
  ein Satz und der Knopf „Bereich speichern".
- **Gespeicherte Runde** = geplante Fahrt in „Meine Fahrten" (Konzept
  5.2), mit Schere wie jede Fahrt; nach dem Fahren geht sie durch das
  Zerlege-Blatt wie jede andere.
- Highlight-Eintrag und Vorführung je Schritt (PR-Vorlage); die
  Kurzanleitung bekommt einen Abschnitt „Runde planen".

## 5. Umsetzung in Schritten (je ein PR)

| Schritt | Inhalt | Issue | Bump |
|---|---|---|---|
| 0 | dieses Dokument; Konzept 9 und 11 nachziehen | #35 | — |
| 1 | `tool/route_measure.py` + `route-measure.yml`: Graph aus Kacheln, DEM, A*, Messung an Tirol (CI) und an den eigenen Fahrten (lokal), Bericht `docs/routing-messung.md` | #35 | — |
| 2 | Höhen: Gitter-Asset (A) oder Höhenkacheln (B) nach M3, mit Wächter in `generated_assets.py` | #158/2 | feat |
| 3 | `road_graph.dart`, `route_profile.dart`, `route_search.dart`, Tests mit erzeugten Kacheln; Profil-Einstellung Bio/E | #158/3 | feat |
| 4 | „Zum Trailkopf" im Trail-Blatt, Vorschau, speichern, GPX | #158/4 | feat |
| 5 | `loop_planner.dart`, Planer-Blatt, Pool, Pflicht-Trails | #158/5 | feat |
| 6 | Kalibrierung aus eigenen Fahrten (Steigrate je Klasse), im Profil sichtbar („deine Steigrate: 520 hm/h aus 14 Fahrten") | #158 | feat |

Schritt 1 entscheidet, ob 2–5 so gebaut werden oder ob vorher die
Pipeline (2.5, letzter Punkt) dran ist. Schritte 3–5 brauchen keine
anderen Nutzer und laufen parallel zur Abgleich-Arbeit (Fahrplan #156,
Stufe 3).

## 6. Messplan (#35, neu geschnitten)

Die alte Frage „welche Engine?" ist entschieden. Die Messung fragt
jetzt, ob **unsere Daten** die eigene Engine tragen. Fünf Fragen, jede
mit Schwelle:

| | Frage | Daten | Schwelle |
|---|---|---|---|
| M1 | **Zusammenhang**: Teilen Wege an Kreuzungen bei z13 einen Knoten? Wie groß ist die größte Komponente, wie viele Trail-Enden hängen innerhalb von 30 m an ihr? | Tirol: 181 offizielle Trails (öffentlich, CI) + eigene Trails (lokal) | ≥ 90 % der Trail-Enden angeschlossen, größte Komponente ≥ 95 % der Kanten im Rahmen |
| M2 | **Wegklassen**: Wie oft führen die eigenen Aufstiege über `track`, `path`, Straße? Trägt die Tabelle 2.4 die Praxis? | eigene Fahrten (lokal; Zerlege-Logik kennt die Aufstiegsstücke) | Bericht, keine Schwelle |
| M3 | **Höhenfehler**: hm bergauf aus Gitter A gegen GPX-Höhen derselben Linie; je Kante und je Aufstieg | eigene Tracks (lokal), Tirol `up_m`/`down_m` (CI) | Aufstiegssumme ±10 %, sonst Höhenkacheln B |
| M4 | **Aufstiegstreue**: Vom Fahrtstart zum ersten Trailkopf — findet A* den Weg, den der Betreiber gefahren ist? Länge, hm, Klassenmix gegen die Fahrt | eigene Fahrten (lokal) | ≥ 70 % der Aufstiege „gleich" nach den Abgleich-Schwellen (15 m, 0,8), Rest erklärbar |
| M5 | **Laufzeit**: Graph bauen + 2N+1 Dijkstra + Verkettung für einen 20-km-Rahmen | Tirol (CI), auf dem Telefon nach Schritt 3 | < 2 s auf dem Rechner, < 5 s auf dem Telefon |

Dazu die **Kalibrierung** (kein Durchfallen möglich): Steigrate und
Flachgeschwindigkeit je Klasse aus den eigenen Fahrten, als Startwerte
für 2.1.

Zwei Läufe, ein Werkzeug: `python3 tool/route_measure.py tirol` liest
die z13-Kacheln aus dem Host-Archiv (Range, wie `map_tiles.py check`),
die offiziellen Trails aus dem Daten-Branch und das DEM aus dem offenen
Bucket — alles öffentlich, läuft in CI (`route-measure.yml`,
`workflow_dispatch`, Bericht in der Run-Summary). `python3
tool/route_measure.py rides --gpx <Sammlung> --rides <Export>` läuft
beim Betreiber: Fahrten verlassen das Gerät nie, also kommen sie als
GPX-Export (#150) auf seinen Rechner, und der Bericht nennt Kennzahlen,
keine Orte. Der CI-Lauf allein beantwortet M1, M3 (Tirol-Hälfte) und
M5; M2 und M4 nur der lokale.

## 7. Risiken, benannt

- **Die Kacheln sind für Karten gemacht, nicht für Graphen.** M1 ist
  die Frage, an der es scheitern kann. Ausweg: eigener Wege-Export je
  Region (2.5), dieselbe Pipeline wie die Orte.
- **Pfad ist nicht gleich Pfad.** Ohne `sac_scale` plant die Engine im
  Zweifel über einen Steig. Der Regler, die Nennung im Ergebnis und die
  Vorgabe 2 km begrenzen den Schaden; der Nutzer sieht die Linie, bevor
  er fährt.
- **Das Zeitmodell ist ohne Kalibrierung grob** (±30 %). Deshalb
  „etwa", deshalb Schritt 6, deshalb die Reserve.
- **Große Pools.** Hundert Trails im Rahmen sind 201 Dijkstra-Läufe;
  die Budget-Grenze hält jeden klein. Über 150 Trails nimmt der Planer
  die nächsten 150 zum Start und sagt es.
- **Der Planer lädt zum Risiko ein** wie jedes Werkzeug, das eine Runde
  vorschlägt. Das Blatt trägt den Sicherheitshinweis (`kSafetyNote`),
  und die Nutzungsbedingungen (Entwurf, Abschnitt 4) gelten.

## 8. Entscheidungen des Betreibers (offen, mit Vorschlag)

1. **Profil Bio-Bike / E-Bike** als gerätelokale Einstellung mit
   Vorgabe Bio-Bike, im Planer je Planung umschaltbar. *Vorschlag: ja.*
2. **Startwerte** aus 2.1–2.3 (Steigraten, Geschwindigkeiten, 3 h,
   800/1 400 hm, 2 km Wanderweg). *Vorschlag: so, bis die eigenen
   Fahrten andere Zahlen liefern.*
3. **Wanderwege nur bergauf, nie bergab** als Verbindungsstück (1,
   vierter Punkt). *Vorschlag: ja.*
4. **Hauptstraßen nie ausgeschlossen, nur teuer** (#158). *Vorschlag:
   ja; `motorway`/`trunk` und `access=private` bleiben gesperrt.*
5. **Höhenquelle**: erst Gitter A messen, B nur bei Durchfallen.
   *Vorschlag: ja.*
6. **Zielfunktion Trail-Meter** vor Anzahl. *Vorschlag: ja.*
7. **Einstieg in den Planer**: der Kartenknopf „Idee" ist heute das
   Feedback. *Vorschlag: eigener Eintrag im Reiter Trails und im
   Trail-Blatt; der Kartenknopf bleibt Feedback.*
8. **BRouter**: nein, keine Hintertür. *Entschieden 2026-10-01.*
9. **Trails mit warnender Meldung** aus dem Pool, einzeln
   hineinholbar. *Vorschlag: ja.*
10. **Reihenfolge**: Schritt 1 (Messung) vor allem anderen; Schritte
    3–5 erst nach dem Bericht. *Vorschlag: ja — die Regel aus #35.*
