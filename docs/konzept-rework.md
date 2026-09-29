# TrailBuddy — Rework: Besitz, Bewertung, Aufzeichnen, Duplikate

*Entwurf vom 2026-09-30, aus einem Gespräch mit dem Betreiber über
Schwachstellen des Konzepts aus Sicht eines Nutzers, der viele
GPX-Dateien importiert hat und einen Trail neu aufzeichnen will. Das
Dokument ergänzt `docs/konzept-trails.md`, es ersetzt es nicht: Jeder
Punkt, der gebaut wird, zieht im selben PR die betroffene Stelle dort
nach (Regel aus `CLAUDE.md`). Offene Entscheidungen stehen in
Abschnitt 9, der Plan in Abschnitt 10; verfolgt in #109.*

## 0. Kurzfassung

Das Modell „Trail ohne Besitzer, Beiträge je Nutzer, stiller Abgleich“
trägt. Im Gebrauch zeigen sich sieben Lücken:

1. **Der Name hängt am Beitrag dessen, der ihn vergeben hat.** Wer einen
   Trail über einen Buddy kennt und ihn wieder fährt, bekommt einen
   Beitrag OHNE Namen. Löscht der Buddy, entfreundet er sich oder löscht
   er sein Konto, steht dort „Trail ohne Namen“.
2. **Ein geplanter Import sagt „offen“.** Jede Aufzeichnung setzt den
   eigenen Status auf „offen“, auch eine GPX-Datei von einer
   Vereinsseite ohne Zeiten. Und das Blatt zeigt Buddys nicht, dass eine
   Linie nur geplant ist — anders als Konzept 4.6 sagt.
3. **Es fehlt „wie gut“ und „in welchem Zustand“.** S-Grad und
   Charakter sagen, wie schwer und wie ein Trail ist, nicht ob er Spaß
   macht und ob er gerade ausgefahren ist.
4. **Die Herkunft einer Linie geht verloren.** Eine Vereinsseite mit
   Beschreibung und Regeln wäre ein nützlicher Verweis; GPX trägt ihn
   oft schon in `<link>`.
5. **Aufzeichnen findet nur, was die Heuristik erkennt.** Jump-Lines,
   flache Flowtrails, Uphills und Trails mit Forstweg-Stück werden kein
   Kandidat, und es gibt keinen Weg, ein Stück selbst zu wählen.
6. **Knapp-daneben wird ein Duplikat, das nie heilt.** Lange Version mit
   Anfahrt, gezeichnete Vereinslinie, Gabel, GPS unter dichtem Wald:
   neuer Trail plus unsichtbare Kante. Der Abgleich vergleicht nur mit
   der BESTEN Aufzeichnung eines Trails, und ein zweiter Zwilling bleibt
   für immer daneben. Beim Verbinden sehen Buddys dann doppelte Linien.
7. **Zusammenführen fehlt** (#33 Teil 2), weil die Regel dafür fehlt.

## 1. Der eigene Beitrag beim ersten Wiederfahren (Lücke 1)

**Regel:** Wer einen Trail fährt, den er bisher nur über Buddys sieht,
**macht ihn sich mit einer Bewertung zu eigen** — ein vollständiger
eigener Beitrag, vorbelegt aus dem, was er sieht. Danach hängt nichts
mehr an einem fremden Beitrag.

- **Wann:** genau dann, wenn es zu diesem Trail noch keinen eigenen
  Beitrag gibt (erste Aufzeichnung). Wer ihn schon beschrieben hat,
  wird nicht noch einmal gefragt — sonst wären es bei einer Hausrunde
  sechs Bewertungen nach jeder Fahrt.
- **Wo:** im Zerlege-Blatt, an der Zeile des bekannten Trails (heute
  nur ein Haken). Die Zeile klappt auf: Name, S-Grad, Charakter, Spaß
  (Abschnitt 3). Ein Knopf „Alle übernehmen“ nimmt die Vorbelegung für
  alle Zeilen. Kein neuer Dialog. Beim Import, wo der Client erst nach
  der RPC weiß, dass die Kennung zu einem sichtbaren Trail gehört, zeigt
  das Ergebnis dieselben Zeilen.
- **Vorbelegt:**
  - Name = der angezeigte Name (`displayName`), Charakter = die
    angezeigten Merkmale (`topTraits`). Tatsachennah, eine Kopie schadet
    nicht.
  - S-Grad = der angezeigte Median, sichtbar als **„Vorschlag aus dem
    Netz“** markiert (Entscheidung E1). Ein Tipp bestätigt ihn — das
    ist eine echte Aussage: gefahren und nicht widersprochen. Die
    Verankerung am ersten Urteil ist der bekannte Preis.
  - Spaß: **nie** vorbelegt (Abschnitt 3).
- **Pflicht:** Die Zeile muss bestätigt werden, damit „wieder
  gefahren“ gespeichert wird (Entscheidung E2); mit Vorbelegung ist das
  ein Tipp.
- **Offline:** über den Ausgangskorb wie heute (`ContributeJob` trägt
  schon Grad und Merkmale; er bekommt Name, Spaß und Zustand dazu).
- **Bestand:** Trails mit eigener Aufzeichnung, aber ohne eigenen Namen,
  gibt es schon. Ein Rückfüllen auf dem Server ginge nicht: Er würde
  Namen aus Beiträgen AUSSERHALB des Netzes kopieren (Konzept 12). Die
  Liste bekommt stattdessen den Filter „Bewertung offen“, das Blatt an
  solchen Trails eine Zeile „Übernehmen“ mit derselben Vorbelegung.

`adoptDetails` bleibt die EINE Schreibstelle; sie lernt, einen fremden
Namen zu übernehmen, wenn der eigene leer ist.

## 2. Geplante Importe (Lücke 2)

- **Kein Status-Rücksetzen durch `planned`.** `contribute_recording`
  setzt den Status nur bei `app` und `import` auf „offen“. Eine Datei
  ohne Zeiten belegt nicht, dass der Trail befahrbar war. Patch,
  `matcher_check.sql` bekommt einen Block dafür.
- **Das Blatt sagt „geplant“.** Hat ein Beitrag nur geplante
  Aufzeichnungen, steht beim Namen des Beitragenden „geplant, nicht
  gefahren“; ein Trail, dessen sichtbare Belege alle geplant sind,
  sagt es oben im Blatt. Das löst ein, was Konzept 4.6 schon verspricht.
- **Bleibt:** Geplante Importe gehen an Buddys (Entscheidung 2 vom
  2026-09-27). Ob sie privat bleiben sollten, bis man sie gefahren hat,
  ist Entscheidung E3.

## 3. Spaß und Zustand (Lücke 3)

Zwei neue Werte je Beitrag, beide 1–5, **beide mit 5 als bestem Wert**
(dieselbe Richtung, sonst verwechselt man sie).

### 3.1 Spaß

Frage: **„Wie viel Spaß?“** — nicht „Qualität“, das vermischte sich mit
Zustand und Schwierigkeit. Symbol aus dem Design (Vorschlag: fünf
kleine Serpentinen aus dem Logo statt Sternen; Entscheidung E4 bei der
Design-Datei).

- Einmal gesagt, jederzeit in „Mein Beitrag“ änderbar, nie vorbelegt.
- Anzeige: Mittelwert der sichtbaren Beiträge **mit Anzahl**
  („4,2 · 3“). In einem Netz aus drei Leuten ist eine Zahl ohne Anzahl
  Rauschen.
- Sortieren nach Spaß in der eigenen Liste: ja. Eine Rangliste über das
  Netz hinaus: nie (Konzept 7, 12).

### 3.2 Zustand

| Wert | Wortlaut |
|---|---|
| 5 | Top gepflegt |
| 4 | Gut |
| 3 | Ausgefahren |
| 2 | Abgerockt — Wurzeln frei, Löcher, Wildwuchs |
| 1 | Kaum fahrbar |

- **Er veraltet, deshalb gilt er wie der Status:** der jüngste
  sichtbare gewinnt, angezeigt mit Alter („ausgefahren · vor 3
  Wochen“), nach 90 Tagen ausgegraut. Kein Median, keine Vorbelegung —
  sonst bestätigt man einen alten Stand.
- **Gefragt nach jeder Fahrt**, freiwillig, ein Tipp, in derselben Zeile
  des Zerlege-Blatts. Das ist der dauerhafte „nach dem Fahren“-Moment.
- **Nur mit eigenem Beleg** (wie Status und S-Grad, Konzept 3); wer
  etwas sieht, ohne gefahren zu sein, schreibt einen Hinweis.
- **Keine Push-Meldung** — die bleibt Status und Hinweisen. Bei 1 oder 2
  bietet die App einen Hinweis an, wie beim Status.
- **Zustand, nie Maßnahme.** Kein „Arbeiten fällig“, kein „braucht
  Pflege“: Konzept 7 schließt Bau-Features und Aufrufe zu
  Arbeitseinsätzen aus, und eine Skala, deren unteres Ende „hier müsste
  jemand ran“ heißt, wäre genau das. Wer Konkretes sagen will, schreibt
  einen Hinweis.
- Unterhalb von 1 beginnt der Status („gesperrt“, „zerstört“,
  „verändert“) — der Zustand beschreibt einen OFFENEN Trail.

### 3.3 Schema

Ein Patch an `trail_details`: `fun smallint` (1–5, null),
`condition smallint` (1–5, null), `condition_at timestamptz`. Ein Check
hält `condition_at` und `condition` zusammen. Ältere Clients schreiben
per `upsert` nur ihre eigenen Spalten und lassen die neuen stehen — im
PR per Test gegen den lokalen Stack belegt, nicht angenommen.

## 4. Link zur Quelle (Lücke 4)

- **Im eigenen Beitrag, nicht am Trail:** `trail_details.link`. Anzeige
  wie beim Namen: eigener, sonst der des ältesten sichtbaren Beitrags,
  weitere als „auch: …“. Es gibt damit keine Frage, wem der Link gehört.
- **Nur `https`**, höchstens 500 Zeichen, Check in der Datenbank. Gezeigt
  wird nur der Host mit Pfeil („trailsurfers-bw.de ↗“), geöffnet im
  externen Browser. Die App ruft den Link nie selbst ab — kein neues
  Netzziel, nichts für die Datenschutzerklärung außer dem Satz, dass
  Beiträge einen Link tragen können.
- **Vorgeschlagen beim Import** aus `<link href>` in `<trk>` oder
  `<metadata>` (GPX 1.1), **ohne Query und Fragment**: Freigabelinks von
  Tourenportalen tragen dort Tokens und Nutzerkennungen. Der Nutzer
  kann den Link vor dem Speichern ändern oder leeren.
- **Abgrenzung:** Die offizielle Ebene (#13) bleibt der Weg für
  Vereins-Trails mit Erlaubnis. Ein Link in einem Beitrag ist die
  Aussage eines Nutzers, keine Quelle der App.

## 5. Aufzeichnen: ein Stück selbst wählen (Lücke 5)

Zwei Wege, damit man sagen kann „genau DAS war der Trail“. Beide
bleiben im Konzept: Das Stück kommt aus eigenen Daten und ist gefahren.

1. **„Stück selbst wählen“ im Zerlege-Blatt.** Unter den Kandidaten ein
   Knopf, der einen Kandidaten über die GANZE Fahrt anlegt, mit
   denselben Griffen (`RangeSlider`), Name, S-Grad, Charakter. Die Karte
   zeigt die Vorschau wie bei einem gefundenen Kandidaten. Braucht
   keinen gespeicherten Bereich — die Wege braucht nur die Heuristik.
   Mindestlänge 150 m (Abgleich) gilt.
2. **Markieren während der Aufnahme.** Ein Knopf „Trail beginnt“ /
   „Trail endet“ neben dem Aufnahmeknopf schreibt eine Marke in die
   JSON-Lines-Datei (im Service-Isolate, wie die Punkte). Das
   Zerlege-Blatt macht aus jedem Paar Marken einen Kandidaten,
   zusätzlich zur Heuristik, vorangehakt. Eine offene Marke am Ende der
   Fahrt gilt bis zum letzten Punkt.

**Nie ein Merkmal „neu“ oder „selbst gebaut“** — die App fragt nicht,
seit wann es einen Trail gibt (Konzept 7).

Folge: Die Heuristik darf weiter nur Abfahrten vorschlagen; Uphills
und Jump-Lines kommen über die zwei Wege oben.

## 6. Abgleich: weniger Zwillinge (Lücke 6)

Zwei Änderungen am Abgleich, beide mit Messung, `tool/trail_match.py`
und SQL im selben PR (Regel aus `CLAUDE.md`):

1. **Gegen mehrere Aufzeichnungen je Trail vergleichen**, nicht nur
   gegen die beste. Heute fällt eine saubere kurze Linie durch, wenn die
   beste Aufzeichnung zufällig die lange Version mit Anfahrt ist —
   obwohl eine passende kurze schon am Trail hängt. Vorschlag: die
   besten drei je Trail; der Trail mit der höchsten Deckung gewinnt wie
   heute. Die Messung sagt, ob drei genügen und was es kostet
   (`tool/limit_measure.sql`).
2. **Zwillinge sichtbar machen.** Passt ein Kandidat „gleich“ auf ZWEI
   Trails, hängt er am besseren, und zwischen den beiden entsteht eine
   Overlap-Kante mit der Markierung „beide gleich einer dritten Linie“.
   Das ist der beste Beleg für ein Duplikat, den es gibt, und der
   Vorrat für den Vorschlag in Abschnitt 7.

**Nicht:** den Korridor weiten oder die Deckung senken. Die Schwellen
sind gemessen, und ab 20 m werden Gabeln „gleich“ (`docs/trail-abgleich-messung.md`).
Eine falsche Verschmelzung bleibt teurer als eine Dublette (Konzept 4.4).

**Später, eigener Schritt:** Kurze Importe (< 8 km, direkt als Trail)
auf Forstwege stutzen wie das Zerlege-Blatt, wenn ein gespeicherter
Bereich die Datei trägt — dann entstehen weniger Versionen „mit
Anfahrt“.

## 7. Zusammenführen im Netz (Lücke 7, #33 Teil 2)

**Regel: Zusammenführen ist eine Aussage in MEINEM Beitrag, kein
Eingriff am Trail.** Niemand verändert die Daten eines anderen.

- **„Für mich ist B derselbe wie A“** heißt:
  1. Meine Aufzeichnungen zu B ziehen nach A um (neue RPC
     `merge_own_into(from, to)`, Security Definer, prüft, dass der
     Aufrufer BEIDE Trails sieht). Mein Beitrag zu B verschmilzt mit
     meinem zu A (A gewinnt, leere Felder füllt B). Meine Hinweise
     ziehen mit.
  2. Für die Beiträge meiner Buddys zu B legt der Client eine
     **persönliche Zuordnung** an (`trail_aliases(user_id, from, to)`,
     nur für mich lesbar). `buildTrails` zeigt B's Beiträge unter A. Nur
     die eigene Ansicht ändert sich.
- **Vorgeschlagen** wird nur für Paare, die der Aufrufer ohnehin beide
  sieht und zwischen denen eine Kante liegt (RPC über
  `trail_overlaps`, Konzept 6), zuerst die aus Abschnitt 6.2. Frei
  wählen („mit einem anderen Trail zusammenführen“) nur unter sichtbaren
  Trails mit einer Mindestdeckung von 0,3, auf dem Gerät gerechnet.
- **Beide Seiten bekommen den Vorschlag.** Führt jeder für sich zusammen,
  verschwindet B aus beiden Ansichten; der Aufräumjob holt die Kennung,
  wenn niemand mehr etwas daran hat.
- **Der Abgleich lernt nicht global** aus einer Zusammenführung (keine
  Umleitung B → A für alle): Ein Nutzer soll nicht über fremde Netze
  entscheiden (Entscheidung E5).
- **Sonderfall „B liegt in A“ (lange Version mit Anfahrt):** Statt
  zusammenführen „auf den gemeinsamen Teil kürzen“ — die eigene
  Aufzeichnung wird im Zerlege-Blatt geöffnet, das Stück neu
  beigesteuert, die alte gelöscht.
- **Rückgängig:** Die persönliche Zuordnung lässt sich lösen; umgezogene
  eigene Aufzeichnungen bleiben, wo sie sind.

## 8. Was sich am Konzept ändert

| Stelle in `konzept-trails.md` | Änderung |
|---|---|
| 3, Name | Wiederfahren übernimmt den angezeigten Namen (1) |
| 3, Status | `planned` setzt ihn nicht zurück (2) |
| 3, neu | Spaß und Zustand (3), Link (4) |
| 4.4 | Vergleich gegen mehrere Aufzeichnungen, Zwillingskanten (6) |
| 4.6 | „geplant“ tatsächlich im Blatt (2) |
| 5.1 | Stück selbst wählen, Marken (5) |
| 6 | Regel fürs Zusammenführen (7) |

Jeder PR aus Abschnitt 10 zieht seine Zeile nach.

## 9. Offene Entscheidungen des Betreibers

| | Frage | Empfehlung |
|---|---|---|
| E1 | S-Grad beim Übernehmen: vorgewählt (Wunsch des Betreibers) oder nur als Frage? | vorgewählt, als „Vorschlag aus dem Netz“ markiert |
| E2 | Wie hart ist die Pflicht? Speichern blockiert, oder nur „Bewertung offen“? | im Zerlege-Blatt Pflicht mit „Alle übernehmen“; im Bestand nur der Filter |
| E3 | Geplante Importe erst privat, bis gefahren? | nein (Entscheidung 2 bleibt), aber deutlich „geplant“ im Blatt |
| E4 | Symbol für Spaß | Design-Datei; Vorschlag Serpentinen |
| E5 | Zusammenführen: nur persönlich oder auch globale Umleitung? | nur persönlich |
| E6 | Zustand nur mit eigenem Beleg? | ja |

## 10. Plan

Reihenfolge nach Nutzen je Aufwand und nach Abhängigkeit. Jeder Schritt
ist ein PR mit eigenem Issue; `feat` hebt MINOR, `fix` PATCH (Regeln in
`CLAUDE.md`). Schema-Schritte bringen ihren Patch, `schema.sql`, die
Saat-Liste und einen Block in `matcher_check.sql` mit. Die Patch-Nummern
in der Tabelle gelten für diese Reihenfolge; wer vorzieht, nimmt die
nächste freie.

| # | Schritt | Issue | Typ | Schema | Hängt ab von |
|---|---|---|---|---|---|
| 1 | Geplant: kein Status-Rücksetzen, „geplant“ im Blatt (2) | #100 | fix | Patch 010 | — |
| 2 | Spaß und Zustand: Schema, Anzeige, „Mein Beitrag“ (3) | #101 | feat | Patch 011 | E4, E6 |
| 3 | Übernehmen beim ersten Wiederfahren, Zustand je Fahrt (1, 3.2) | #102 | feat | — | #101, E1, E2 |
| 4 | Link im Beitrag, Vorschlag aus GPX (4) | #103 | feat | Patch 012 | — |
| 5 | Stück selbst wählen im Zerlege-Blatt (5.1) | #104 | feat | — | — |
| 6 | Marken während der Aufnahme (5.2) | #105 | feat | — | #104 |
| 7 | Abgleich gegen mehrere Aufzeichnungen, Zwillingskanten (6) | #106 | feat | Patch 013 | Messung |
| 8 | Zusammenführen im Netz (7) | #107 | feat | Patch 014 | #106, E5 |
| 9 | Kurze Importe auf Forstwege stutzen (6, später) | #108 | feat | — | — |

### Schritt 1 — Geplant

- `contribute_recording`: `on conflict … do update set status = 'open'`
  nur, wenn `source <> 'planned'`. Neuer Block in `matcher_check.sql`:
  „gesperrt“ + geplanter Import ⇒ bleibt gesperrt; + App-Aufzeichnung ⇒
  offen.
- `Trail`: je Beitrag „nur geplant“ ableiten (aus den sichtbaren
  Aufzeichnungen des Nutzers, `RecordingSource.planned`); Blatt und
  Beitragsliste zeigen es. Widget-Test im Harness.
- `konzept-trails.md` 3 und 4.6 nachziehen.

### Schritt 2 — Spaß und Zustand

- Patch 011: drei Spalten, Checks (1–5; `condition_at` genau dann,
  wenn `condition`). Grants unverändert (Spalten erben).
- `TrailDetails`: Felder, `fromJson`/`toRow`/Cache-Encoder (Rundlauf-
  Test), `copyWith`. `Trail`: `funAverage`, `funCount`,
  `latestCondition` (jüngster mit Alter, ausgegraut nach 90 Tagen).
- `singletrail_scale.dart`-Muster: Wortlaut an EINER Stelle
  (`trail_condition.dart`), Symbol für Spaß nach Design-Datei.
- Blatt: Anzeige; „Mein Beitrag“: Auswahl. Liste: Sortierung nach
  Spaß. Beim Zustand 1–2 einen Hinweis anbieten.
- Test gegen den lokalen Stack: ein Upsert ohne die neuen Spalten
  lässt sie stehen.
- `docs/design/README.md` (Symbol), `konzept-trails.md` 3.

### Schritt 3 — Übernehmen beim ersten Wiederfahren

- Zerlege-Blatt: bekannte Zeile klappt auf, wenn kein eigener Beitrag
  existiert; Vorbelegung nach Abschnitt 1; „Alle übernehmen“; Zustand
  je Zeile (immer, freiwillig). Speichern verlangt die Bestätigung
  (E2).
- `adoptDetails`: übernimmt einen fremden Namen, wenn der eigene leer
  ist; schreibt Spaß und Zustand mit. `ContributeJob`: Name, Spaß,
  Zustand (alter Auftrag ohne Felder liest sich leer).
- Import: Ergebnis zeigt dieselben Zeilen für Kennungen, die im Netz
  schon sichtbar waren.
- Liste: Filter „Bewertung offen“; Blatt: „Übernehmen“.
- Flow-Test: Buddy-Trail wieder fahren ⇒ eigener Name; Buddy entfreundet
  ⇒ Name bleibt.

### Schritt 4 — Link

- Patch 012: `trail_details.link text` mit Check (`^https://`, ≤ 500).
- `gpx.dart`: `<link href>` aus `<trk>`, sonst `<metadata>`; Query und
  Fragment weg. Import schlägt ihn vor.
- Blatt: Host mit ↗, öffnet extern; „Mein Beitrag“: Feld.
- Datenschutzerklärung: ein Satz; `privacy_policy_test` bleibt grün.

### Schritt 5 — Stück selbst wählen

- `ride_split_sheet.dart`: Knopf „Stück selbst wählen“ legt einen
  Kandidaten über die ganze Fahrt an (Griffe, Vorschau, Name, Grad,
  Charakter); ohne gespeicherten Bereich verfügbar.
- `ride_split.dart` (pur): Kandidat aus Index-Bereich, Mindestlänge.
- Test: Fahrt ohne Bereich ⇒ Stück wählen ⇒ beigesteuert.

### Schritt 6 — Marken

- `ride_task_handler.dart`: Marke als eigene Zeile in der JSON-Lines-
  Datei; Brücke zum Main-Isolate wie beim Punkt
  (`ride_live_bridge_test.dart` erweitern).
- Kartenknopf neben der Aufnahme (Design-Datei, 44 dp), nur während
  einer Fahrt.
- `ride_split.dart`: Marken-Paare ⇒ Kandidaten, offene Marke bis zum
  Ende.

### Schritt 7 — Abgleich

- Messung zuerst: `tool/trail_match.py` mit „beste N je Trail“ an den
  584 Tracks; Ergebnis in `docs/trail-abgleich-messung.md`.
- `contribute_recording`: `limit 1` → `limit N`; bei zwei „gleich“-
  Trails die Zwillingskante (`trail_overlaps` bekommt `twin boolean`).
- `matcher_check.sql`: Block für kurze Linie gegen Trail mit langer
  bester Aufzeichnung; Block für Zwillinge.

### Schritt 8 — Zusammenführen

- Patch 014: `merge_own_into`, `trail_aliases` (RLS: nur eigene Zeilen),
  RPC für Vorschläge (nur Paare, die der Aufrufer beide sieht).
- `buildTrails` wendet die Zuordnungen an; Blatt „Sind das dieselben?“
  mit beiden Linien auf der Karte; „auf gemeinsamen Teil kürzen“ öffnet
  das Zerlege-Blatt.
- `fake_trails.dart` spiegelt die neuen Regeln; `matcher_check.sql`
  prüft, dass die RPC für nicht sichtbare Paare nichts sagt.
- #33 schließen.
