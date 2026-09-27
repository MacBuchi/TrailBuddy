# TrailBuddy — Konzept: Trails, Duplikate und das Community-Tor

*Entwurf vom 2026-09-27, vor jeder Umsetzung. Die acht Entscheidungen
in Abschnitt 10 hat der Betreiber am selben Tag getroffen; das
Dokument ist damit die Grundlage für Phase 0. Deutsch, weil es ein
Arbeitspapier für den Betreiber ist; auf GitHub wird Englisch
gesprochen (Commits, Issues, PRs — Regel aus PilzBuddy).*

## 0. Kurzfassung

Das Buddy-Prinzip von PilzBuddy trägt für Trails nur zur Hälfte: Ein
Pilz-Spot ist ein privates Objekt mit einem Besitzer, ein Trail ist ein
Objekt auf dem Boden, das viele Leute kennen und jeder anders nennt.
Das Konzept löst das mit einer Trennung, die es in PilzBuddy nicht
gibt:

1. **Trail, Fahrt und Aufzeichnung sind drei verschiedene Dinge.** Ein
   Trail ist ein Stück Weg mit Anfang, Ende und Richtung. Eine Fahrt ist
   das, was das GPS an einem Tag aufgezeichnet hat (Haustür bis
   Haustür). Eine Aufzeichnung ist der Ausschnitt einer Fahrt, der einen
   Trail belegt. **Fahrten verlassen das Gerät nie.**
2. **Es gibt eine globale Trail-Datenbank, aber der Trail hat keinen
   Besitzer und keine Eigenschaften.** Der kanonische Trail ist nur eine
   Kennung. Alles Sichtbare — Linie, Name, Beschreibung, Schwierigkeit —
   ist ein **Beitrag** eines Nutzers zu dieser Kennung.
3. **Sichtbarkeit ist eine eigene Schicht:** Du siehst einen Trail genau
   dann, wenn du ihn selbst gefahren bist (eigener Beitrag) oder ein
   direkter Buddy ihn gefahren ist. Was du siehst, ist AUSSCHLIESSLICH
   aus diesen sichtbaren Beiträgen gerechnet. Sehen ist nicht
   Weitergeben; nur Gefahrenes wird weitergegeben.
4. **Duplikate werden beim Beitrag erkannt, serverseitig, still und
   gegen ALLE Trails** — nicht nur gegen das eigene Netz. Das ist
   leak-frei, weil der Abgleich nur bestätigt, was der Beitragende schon
   in der Hand hat: Wer eine Linie hochlädt, die einen Trail zu 80 %
   trifft, kennt den Trail. Er erfährt dabei nichts, was er nicht schon
   wusste — nicht einmal, OB andere den Trail haben.
5. **Beim Verbinden gibt es keinen Konflikt mehr, sondern eine
   Verschmelzung:** gemeinsame Trails werden EIN Trail mit zwei Namen,
   der Rest kommt dazu.
6. **Das Tor ist sozial, nicht technisch.** Es leistet Datensparsamkeit
   (keine öffentliche Karte, kein Verzeichnis, nichts ohne Buddys), es
   leistet keinen Schutz gegen jemanden mit Absicht. Das Konzept sagt,
   was die Plattform deshalb nicht tut (Abschnitt 7).

## 1. Warum das PilzBuddy-Modell hier nicht trägt

In PilzBuddy ist die Welt einfach: Ein Spot gehört einem Nutzer, der
teilt ihn mit Buddys, Funde hängen am Spot. Zwei Nutzer, die dieselbe
Stelle kennen, legen zwei Spots an — das kommt vor, ist aber selten
(Fundstellen sind privat) und es gibt dafür „Zusammenführen" im
Spot-Blatt.

Bei Trails ist die Dublette der Normalfall, nicht die Ausnahme:

- **Jeder Ortsansässige hat die meisten Trails seiner Gegend.** Zwei
  Leute aus derselben Stadt, die sich verbinden, haben 80 % Überlappung.
  Mit dem Spot-Modell hätte jeder danach jeden Trail doppelt auf der
  Karte, mit zwei Namen und zwei Bewertungen.
- **Ein Trail hat keinen natürlichen Besitzer.** Wer ihn zuerst
  hochgeladen hat, ist eine Zufallsfrage und keine Grundlage für „wessen
  Name gilt" oder „wer darf ihn löschen".
- **Das Löschen eines Beitrags darf den Trail nicht löschen**, wenn
  andere ihn belegen — und umgekehrt darf ein Nutzer nach DSGVO seine
  eigene Aufzeichnung zurückziehen.
- **Ein Trail ist eine Linie, kein Punkt.** „Derselbe Ort" ist bei
  Punkten ein Radius (in PilzBuddy 20 m). Bei Linien ist es eine
  Ähnlichkeitsfrage mit Teilüberlappungen, Abzweigungen, Gegenrichtung.

Die Antwort ist die Trennung von Identität (Trail) und Aussage
(Beitrag), wie sie OpenStreetMap zwischen `way` und GPS-Trace macht, und
wie Strava sie zwischen Segment und Aktivität macht.

## 2. Begriffe

| Begriff | Bedeutet | Wem gehört es | Verlässt das Gerät |
|---|---|---|---|
| **Fahrt** | Eine GPS-Aufzeichnung von Start bis Ziel, mit Zeiten. | dem Nutzer, gerätelokal | **nie** |
| **Aufzeichnung** | Ein Ausschnitt einer Fahrt (oder einer importierten GPX-Datei), der einen Trail belegt: Linie, Zeitpunkt, Richtung, GPS-Qualität. | dem Nutzer | ja, an den Server |
| **Trail** | Die Kennung für „dieses Stück Weg auf dem Boden". Trägt selbst nichts Sichtbares. | niemandem | — |
| **Beitrag** | Alles, was ein Nutzer über einen Trail sagt: Name, Beschreibung, S-Grad, Typ, Status, Sichtbarkeit. Genau einer je Nutzer und Trail. | dem Nutzer | ja |
| **Netz** | Die Trails, die ich sehe: eigene Beiträge plus Beiträge direkter Buddys. | — | — |

Im Deutschen der Oberfläche heißt ein Trail „Trail"; „Strecke" oder
„Abfahrt" wären enger (nicht jeder Trail geht bergab).

## 3. Datenmodell

Supabase/Postgres wie in PilzBuddy, dazu **PostGIS** (auf Supabase
verfügbar, Erweiterung einschalten). Skizze, kein fertiges Schema:

```sql
-- Die Kennung. Bewusst ohne Name, ohne Besitzer, ohne created_at in der
-- API-Sicht: Nichts in dieser Zeile darf verraten, dass jemand anderes
-- den Trail schon hatte.
create table public.trails (
  id uuid primary key default gen_random_uuid()
);

-- Ein Beleg: „ich bin das gefahren". Geometrie in WGS84.
create table public.trail_recordings (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  geom geography(LineString, 4326) not null,
  recorded_at timestamptz,             -- null bei Import ohne Zeiten
  -- 'planned': importierte Datei ohne Zeiten oder mit unplausiblen
  -- Geschwindigkeiten — eine geplante Route, keine Fahrt. Zählt als
  -- Beitrag (Entscheidung 2), mit Qualität nahe null.
  source text not null check (source in ('app', 'import', 'planned')),
  reversed boolean not null default false,  -- gegen die Trail-Richtung gefahren
  quality real not null,               -- 0..1, siehe 4.5
  created_at timestamptz not null default now(),
  client_id uuid                       -- Ausgangskorb, Idempotenz wie PilzBuddy Patch 016
);
create index trail_recordings_geom_gix on public.trail_recordings using gist (geom);
create index trail_recordings_trail_idx on public.trail_recordings (trail_id);
create index trail_recordings_user_idx on public.trail_recordings (user_id);

-- Was ein Nutzer über einen Trail sagt. Genau eine Zeile je Nutzer und
-- Trail. Entsteht mit der ersten Aufzeichnung.
create table public.trail_details (
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text,
  description text,
  grade smallint check (grade between 0 and 5),   -- Singletrail-Skala S0–S5
  kind text check (kind in ('natural', 'flow', 'tech', 'jump', 'connection')),
  visibility text not null default 'buddies' check (visibility in ('buddies', 'private')),
  status text not null default 'open' check (status in ('open', 'closed', 'destroyed', 'changed')),
  status_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (trail_id, user_id)
);

-- Unsichtbare Nachbarschaft für später (Abschnitt 4.4): „Trail A
-- überlappt Trail B zu 45 %". Kein Client liest diese Tabelle.
create table app_internal.trail_overlaps (
  a uuid references public.trails(id) on delete cascade,
  b uuid references public.trails(id) on delete cascade,
  coverage_ab real, coverage_ba real,
  primary key (a, b)
);
```

**Die Sichtbarkeitsregel**, formal:

> Nutzer U sieht Trail T, wenn es eine Aufzeichnung zu T von U gibt,
> oder eine Aufzeichnung zu T von einem Buddy B, dessen Beitrag zu T die
> Sichtbarkeit `buddies` hat.

Als RLS auf `trail_recordings` und `trail_details` (Muster
`are_friends` aus PilzBuddy, Patch 006/011):

```sql
create policy recordings_select on public.trail_recordings for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)));
```

Die Tabelle `trails` selbst braucht keine eigene Sicht: Der Client
fragt nie „welche Trails gibt es", sondern „welche Aufzeichnungen und
Beiträge sehe ich" und gruppiert nach `trail_id`. **Alles, was auf der
Karte steht, ist aus sichtbaren Beiträgen gerechnet:**

- **Linie** = die Aufzeichnung mit der höchsten Qualität unter den
  sichtbaren. Wer allein ist, sieht seine eigene; wer Buddys hat, sieht
  vielleicht deren bessere. Kein Mittelwert (siehe 4.5).
- **Länge, Höhenmeter, mittleres Gefälle** = aus dieser Linie plus dem
  Höhengitter (PilzBuddy-Baustein, offline).
- **Name** = eigener Name, sonst der Name des ältesten sichtbaren
  Beitrags; die anderen als „auch: …" (Muster Buddy-Alias in PilzBuddy).
- **Schwierigkeit** = Median der sichtbaren S-Grade, mit Spanne.
- **Status** = die jüngste sichtbare Statusmeldung, mit ihrem Alter
  („gesperrt, gemeldet vor 14 Monaten"). Kein automatisches Verfallen,
  aber ein sichtbares Datum; alle Meldungen bleiben im Blatt. **Jede
  neue Aufzeichnung setzt den Status des Aufzeichnenden auf „offen"**
  — wer den Trail fährt, hat ihn befahrbar vorgefunden. Bei
  Widerspruch zwischen Buddys gewinnt der jüngste, ohne Abstimmung.

Eine zentrale Sicht (`trails_visible`) rechnet das serverseitig, damit
Karte, Liste und Blatt dieselbe Antwort geben — dieselbe Regel wie in
PilzBuddy „Fläche, Legende und Blatt müssen dasselbe sagen".

**Löschen und DSGVO.** Ein Nutzer löscht seine Aufzeichnungen und
seinen Beitrag; der Trail bleibt, solange ein anderer Beitrag existiert,
und verschwindet mit dem letzten (Aufräumjob, kein Cascade vom Beitrag
zur Kennung). Kontolöschung kaskadiert wie in PilzBuddy. Eine
Aufzeichnung ist ein Bewegungsprofil-Ausschnitt und damit
personenbezogen; sie steht in der Datenschutzerklärung als eigene
Kategorie. Fahrten sind gar nicht erst auf dem Server.

## 4. Duplikate: der Abgleich

### 4.1 Eingang

Der Abgleich bekommt eine **Kandidatenlinie** (Abschnitt 5 sagt, wie
sie entsteht): eine Polyline mit 20 bis einigen tausend Punkten, mit
oder ohne Zeitstempel, mit oder ohne Genauigkeitsangabe je Punkt. Er
läuft in EINER Security-Definer-Funktion `contribute_recording(geom,
source, recorded_at, client_id)` auf dem Server: Der Client kann nicht
gegen fremde Trails vergleichen, weil er sie nicht sehen darf, und
genau deshalb muss es die Datenbank tun. Die Funktion legt die
Aufzeichnung an, hängt sie an einen bestehenden oder neuen Trail und
gibt **nur die Trail-Kennung** zurück. Ob sie neu ist, sagt sie nicht.

### 4.2 Drei Stufen

1. **Vorfilter, billig:** PostGIS `ST_DWithin` auf der Hülle — alle
   Trails, deren beste Aufzeichnung dem Kandidaten irgendwo näher als
   der Korridor kommt. GiST-Index, Millisekunden.
2. **Deckungsgrad, beide Richtungen:** Beide Linien werden auf 5 m
   abgetastet. `cov(A→B)` = Anteil der Punkte von A, die näher als der
   Korridor `d` an B liegen; ebenso `cov(B→A)`. Das ist mit
   `ST_Buffer`/`ST_Intersection` direkt in SQL zu haben.
3. **Reihenfolge, gegen Serpentinen:** Ein Trail mit Kehren hat
   parallele Schenkel im Abstand von 10 bis 20 m — ein Korridortest
   allein hält den benachbarten Schenkel eines ANDEREN Trails für
   Deckung. Deshalb für die Kandidaten aus Stufe 2 zusätzlich die
   diskrete Fréchet-Distanz auf den abgetasteten Punkten, **die im
   Korridor liegen** — beide Seiten vorher beschnitten. Sie verlangt,
   dass die Punkte in derselben REIHENFOLGE nah beieinander liegen. Das
   Maximum über ALLE Punkte wäre falsch: Ein einzelner GPS-Sporn oder
   ein grob gezeichneter Bogen sagt nichts über die Reihenfolge, treibt
   das Maximum aber auf 40–90 m (gemessen an namensgleichen Trails).
   Als SQL unpraktisch — das ist PL/pgSQL oder eine Edge Function; bei
   ≤ 1200 Punkten je Linie ist O(n·m) kein Problem.

**Schwellen, gemessen am 2026-09-27** (`docs/trail-abgleich-messung.md`,
584 Tracks des Betreibers):

| Größe | Wert | Grund |
|---|---|---|
| Korridor `d` | 15 m | GPS unter Blätterdach liegt 10–20 m daneben; 10 und 15 m liefern dieselben Gleich-Paare, ab 20 m kommen Gabeln als „gleich" dazu. |
| Deckung „gleich" | ≥ 0,8 beidseitig | Die Verteilung hat eine Lücke: 26 Paare unter 0,7, 7 über 0,9, 4 dazwischen — und die sind Trail und Variante. |
| Fréchet „gleich" | ≤ 2·d, **auf den Punkten im Korridor** | Alle Gleichen ≤ 19,4 m, der nächste Wert 84 m. Ohne den Zuschnitt treibt ein einzelner Sporn das Maximum auf 40–90 m bei namensgleichen Trails. |
| Mindestlänge Trail | 150 m | Darunter ist es eine Zufahrt oder ein Fragment; 12 von 584 Dateien. |
| Abtastung | 5 m | Kehren mit 10 m Radius bleiben sichtbar; Locus-Exporte sind auf 13 m gedünnt, gezeichnete Routen haben 100-m-Schenkel. |

### 4.3 Richtung

Ein Trail hat eine Richtung — die des ersten Beitrags. Wird dieselbe
Linie in Gegenrichtung gefahren (Deckung ≥ 0,8, Fréchet auf der
umgedrehten Linie), ist es **derselbe Trail** mit `reversed = true` an
der Aufzeichnung. Ein Trail, der in beiden Richtungen belegt ist, gilt
als beidseitig befahrbar; das ist für das spätere Routing die
entscheidende Information (Abschnitt 9). Zwei Trail-Kennungen für zwei
Richtungen wären zwei Namen für einen Weg.

### 4.4 Die vier Fälle — und was v1 davon macht

Kandidat K gegen bestehenden Trail T:

| Fall | Deckung | Bedeutet | v1 |
|---|---|---|---|
| gleich | K→T ≥ 0,8 und T→K ≥ 0,8 | derselbe Trail | **anhängen** |
| K liegt in T | K→T ≥ 0,8, T→K < 0,8 | jemand ist nur einen Teil gefahren | anhängen als Teilbeleg, wenn K→T ≥ 0,9 und K ≥ 50 % von T; sonst neuer Trail + Overlap-Link |
| T liegt in K | T→K ≥ 0,8, K→T < 0,8 | Kandidat enthält T und mehr | **neuer Trail + Overlap-Link** |
| Gabel | beide zwischen 0,3 und 0,8 | gemeinsames Stück, dann Abzweig | **neuer Trail + Overlap-Link** |

Die Entscheidung für v1 ist bewusst konservativ: **Nur „gleich" wird
verschmolzen, alles andere wird ein neuer Trail mit einer unsichtbaren
Nachbarschaftskante** (`app_internal.trail_overlaps`). Zwei Gründe:

- **Zerschneiden nach fremden Grenzen wäre ein Leak.** Enthält meine
  40-km-Fahrt einen Trail, den nur andere kennen, und der Server
  schnitte den Kandidaten an dessen Anfang und Ende auf, dann wüsste
  ich danach, WO ein fremder Trail beginnt und endet. Deshalb gilt:
  **Schnittvorschläge kommen nur aus eigenen Daten und aus dem
  sichtbaren Netz, nie aus fremden Trails.**
- **Eine falsche Verschmelzung ist teurer als eine Dublette.** Zwei
  Trails, die eigentlich einer sind, kann man später zusammenführen
  (Werkzeug wie „Spots zusammenführen" in PilzBuddy, nur innerhalb des
  eigenen Netzes, wo beide sichtbar sind). Einen falsch verschmolzenen
  Trail wieder zu trennen, ist eine Handarbeit mit Datenverlust.

Die Overlap-Kanten sind der Vorrat für später: Wenn zwei Nutzer sich
verbinden und die App zwei sichtbare Trails mit einer Kante findet,
kann sie „Sind das dieselben?" fragen — dann kennen beide Seiten beide
Linien, und der Vorschlag verrät nichts.

### 4.5 Kanonische Linie und Qualität

Es gibt keine gemittelte Linie. Jede Aufzeichnung bekommt eine
**Qualität** 0..1 aus: Anteil der Punkte mit Genauigkeit ≤ 15 m, keine
Lücke > 10 s bzw. > 50 m, Punktdichte, Quelle (`app` vor `import` ohne
Zeiten). Die Linie, die ein Nutzer sieht, ist die beste unter den ihm
SICHTBAREN Aufzeichnungen. Ein Mittelwert über mehrere Linien ist
eine spätere Verbesserung, wenn es Messungen gibt, dass er etwas
bringt — und er müsste dann ebenfalls nur über sichtbare Beiträge
gerechnet werden.

### 4.6 Warum das leak-frei ist — und was trotzdem verborgen bleibt

Das Argument in einem Satz: **Der Abgleich beantwortet nur die Frage
„ist meine Linie ein bekannter Trail" mit einer Kennung, und diese
Kennung sagt mir nichts, solange kein Buddy Beiträge dazu hat.**

Prüfung der Angriffe:

- **Sondieren:** Ein Fremder lädt Linien entlang aller Forstwege eines
  Reviers hoch. Er bekommt je Linie eine Kennung — für neue wie für
  bekannte Trails dieselbe Sorte Antwort. Er sieht keine Zähler
  („3 Buddys kennen das"), keine fremden Namen, keine fremde Linie,
  kein Erstellungsdatum. Was er sehen könnte, hat er selbst geliefert.
  Um einen Trail zu „treffen", müsste er zu 80 % innerhalb 15 m auf
  ihm fahren — dann kennt er ihn.
- **Rate:** 50 Aufzeichnungen je Nutzer und Tag reichen jedem echten
  Nutzer (auch für einen Bestandsimport an einem Abend) und machen das
  Sondieren als Fläche unattraktiv.
- **Synthetische GPX:** Ein Import ohne Zeitstempel oder mit
  unplausiblen Geschwindigkeiten wird als „geplant" gespeichert
  (`source = 'planned'`), bekommt Qualität nahe null und steht in der
  Anzeige so da; ein Import mit Zeiten als „importiert". Beides gilt
  als Beitrag — der Nutzer hat die Linie, mehr beweist auch eine
  App-Aufzeichnung nicht. Die Linie eines Buddys mit echter
  Aufzeichnung gewinnt in der Anzeige immer.

Was DESHALB nie an den Client geht: Zähler über alle Beiträge, das
Alter der Kennung, die Overlap-Tabelle, irgendeine Aggregation über
Nutzer außerhalb des Netzes. Ein Wächter-Test wie `schema_check.sh` in
PilzBuddy prüft, dass `trails` und `app_internal.*` für `anon` und
`authenticated` gar keine Grants tragen.

### 4.7 Offline

Der Abgleich braucht den Server. Ohne Empfang landet die Aufzeichnung
im Ausgangskorb (PilzBuddy-Baustein) und der Trail steht als
„wartend" auf der Karte, mit der eigenen Linie. Beim Nachholen bekommt
er seine Kennung; die eigene Sicht ändert sich dabei nur, wenn ein
Buddy eine bessere Linie hat.

## 5. Wie Trails entstehen

Drei Wege, davon zwei in v1.

### 5.1 In der App aufzeichnen

Der Aufzeichnungs-Baustein aus PilzBuddy (Pilztour: Foreground-Service
vom Typ `location`, Messung im Service-Isolate, JSON Lines auf der
Platte, prozesssicher) wird zur **Fahrt**. Am Ende zeigt ein Blatt die
Fahrt auf der Karte, zerlegt in Abschnitte:

- **Bekannte Trails** aus dem sichtbaren Netz (Abgleich lokal gegen den
  Zwischenspeicher, dieselben Schwellen) — vorangehakt, „wieder
  gefahren" wird als Aufzeichnung beigesteuert (das aktualisiert
  Qualität und Status).
- **Kandidaten** für neue Trails, vorgeschlagen aus eigenen Daten:
  Abschnitte mit anhaltendem Gefälle (Höhengitter, offline) UND abseits
  von Forst- und Fahrstraßen. Letzteres ist aus den Offline-Kacheln zu
  haben — die PMTiles-Straßenebene kennt `track`, `service`, `road`;
  ein Abschnitt, der zu > 70 % mehr als 15 m von all dem entfernt
  liegt, ist Singletrail oder Wiese. Heuristik, kein Urteil: Der Nutzer
  schneidet mit zwei Griffen zu, benennt, wählt S-Grad, oder verwirft.
- **Rest** (Anfahrt, Forstweg, Straße) wird nicht angeboten.

Die Fahrt bleibt danach als Ganzes auf dem Gerät (Statistik, eigene
Historie), gelöscht wird nichts ohne Nachfrage. **Heimzone:** Kandidaten,
die innerhalb 300 m vom Start- oder Endpunkt der Fahrt beginnen oder
enden, werden markiert („beginnt nahe deinem Start") — kein Riegel, ein
Hinweis, weil ein Trail durchaus an der Haustür beginnen kann.

### 5.2 GPX-Import (der Bestand)

Der Grund, warum das Konzept vor dem Code stehen muss: Die ersten
Nutzer bringen Sammlungen mit. Der Import nimmt eine oder viele
Dateien und entscheidet je Datei:

- **Kurz und überwiegend bergab** (< 8 km, Höhenverlust > 2× Gewinn,
  aus dem Höhengitter oder den Höhen in der Datei) ⇒ ist ein Trail, wird
  direkt Kandidat; Name aus `<name>` der Datei vorgeschlagen. Die 8 km
  sind gemessen: Alpine Trails sind 3 bis 8 km lang, Fahrten beginnen
  im Bestand bei 8 km; die wenigen langen Abfahrten darüber gehen als
  Fahrt durchs Zerlege-Blatt, der harmlose Fehler.
- **Sonst** ⇒ ist eine Fahrt, geht durch dasselbe Blatt wie 5.1.

Dann für jeden bestätigten Kandidaten `contribute_recording`. Zwanzig
Dateien sind zwanzig Aufrufe; das Ergebnis ist eine Karte, auf der
Trails, die Buddys schon haben, verschmolzen sind, und alle anderen als
eigene stehen. **Einen Import „konfliktfrei" zu machen, ist damit keine
Oberfläche, sondern eine Eigenschaft des Modells.**

### 5.3 Von Hand zeichnen — nicht in v1

Ein Trail ohne Aufzeichnung ist eine Behauptung ohne Beleg und würde
das „nur Gefahrenes wird weitergegeben" unterlaufen. Später denkbar
für Korrekturen an einer bestehenden Linie, nicht zum Anlegen.

## 6. Freundschaft: was beim Verbinden passiert

Nichts, was gelöst werden müsste. Nach dem Annehmen:

- Trails, die beide belegt haben, sind EIN Trail auf beiden Karten, mit
  beiden Namen („Hexentanz · auch: Roots").
- Trails, die nur einer belegt hat, erscheinen beim anderen neu.
- Eine Zusammenfassung nach dem Annehmen — nicht davor —: „14 Trails
  gemeinsam, 8 neu von Jan, 5 neu für Jan". Vor dem Annehmen wäre die
  Zahl ein Orakel über den Bestand eines Fremden.
- Overlap-Kanten zwischen zwei jetzt sichtbaren Trails werden als
  Vorschlag gezeigt: „Sind das dieselben? Beide Linien ansehen".

Beim **Entfreunden** verschwinden die Trails, die nur über diesen
Buddy sichtbar waren; eigene Beiträge bleiben, auch die zu Trails, die
der Buddy zuerst hatte. Symmetrisch zu PilzBuddy: jeder behält, was er
selbst eingetragen hat.

**Keine Transitivität.** Buddys von Buddys sehen nichts. Ein Trail
wandert nur weiter, wenn jemand ihn FÄHRT und damit einen eigenen
Beitrag hat. Das ist die eine Regel, die das Tor trägt: Ein Netz von
1 000 Leuten mit Weitergabe von Gesehenem wäre eine öffentliche Karte
mit Anmeldung.

Ein Beitrag mit Sichtbarkeit `private` ist nur für den Nutzer selbst —
für Trails, die man kennt und niemandem zeigen will. Wer einen privaten
Trail fährt und selbst beiträgt, sieht ihn natürlich; der private
Beitrag des anderen bleibt dabei unsichtbar.

## 7. Das Tor: was die Community leistet — und was nicht

Regeln, die aus dem Modell folgen und alle mit RLS erzwungen sind:

- **Keine öffentliche Karte, keine Suche nach Trails, kein
  Verzeichnis.** Ohne Buddys ist die Karte leer bis auf das Eigene.
- **Buddy-Suche nur über exakten Nutzernamen oder E-Mail**, ohne Liste
  (PilzBuddy-Muster, kein Orakel).
- **Nur Gefahrenes wird weitergegeben, nichts transitiv.**
- **Aggregationen über das Netz hinaus gibt es nicht.** Keine „beliebte
  Trails in deiner Nähe", keine Heatmap, keine Zähler.
- **Einladung** als Bequemlichkeit (Link, der eine Buddy-Anfrage
  vorausfüllt), nicht als Pflicht: Eine Pflicht-Einladung hält niemanden
  ab, der jemanden kennt, und sperrt alle aus, die niemanden kennen —
  und die haben ohnehin eine leere Karte.

Was das Tor **nicht** ist, muss ebenso klar sein, sonst baut man ein
Versprechen, das nicht hält:

- Es hält **Neugier** ab, nicht **Absicht**. Wer einen Trail finden
  will, kann sich ein Rad leihen und ihn fahren — dann hat er ihn, mit
  Recht. Das Modell macht das Finden nicht leichter als ohne App, und
  das ist der ehrliche Anspruch: **Die App darf niemandem einen Trail
  zeigen, den er nicht ohnehin schon kennt oder von einem Freund gezeigt
  bekommt.** Mehr Schutz als eine WhatsApp-Gruppe kann sie nicht
  bieten, weniger darf sie nicht bieten.
- Es ist **kein Rechtsschutz** für den Betreiber. Wenn die Plattform
  dazu einlädt, Wege zu zeigen, die nach Landesrecht nicht befahren
  werden dürfen, kann das den Betreiber treffen (Stichwort
  Störerhaftung), und die Datenschutzerklärung muss die Aufzeichnungen
  als Bewegungsdaten benennen. Das ist keine Rechtsberatung; die
  Empfehlung ist eine juristische Prüfung der Nutzungsbedingungen VOR
  dem ersten Nutzer, der nicht der Betreiber selbst ist.

Daraus folgen Dinge, die die Plattform **bewusst nicht tut**:

- **Keine Bau-Features.** Kein „Trail im Bau", kein Bautagebuch, keine
  Aufrufe zu Arbeitseinsätzen. Das Anlegen von Trails ist in allen
  DACH-Ländern der Punkt, an dem aus einer Grauzone eine Straftat wird
  — das Befahren vorhandener Wege ist es meist nicht (die Regeln
  unterscheiden sich je Bundesland: „geeignete Wege" in Bayern,
  2-Meter-Regel in Baden-Württemberg, „feste Wege" in NRW).
- **Schutzgebiete werden gesagt, nicht gesperrt.** Das
  Schutzgebiets-Gitter aus PilzBuddy (Naturschutzgebiete, Nationalparks,
  Kernzonen; 250-m-Waben; DACH) läuft hier mit: Ein Kandidat, der ein
  Schutzgebiet quert, bekommt beim Anlegen einen Satz („liegt
  wahrscheinlich in einem Naturschutzgebiet — dort ist Radfahren abseits
  der Wege meist verboten"). Kein Riegel, keine Rückfrage, dieselbe
  Linie wie in PilzBuddy: keine Bevormundung, aber auch kein Schweigen.
- **Kein Status „legal/illegal" am Trail.** Die App kann es nicht
  wissen, und ein solches Feld wäre entweder immer „unbekannt" oder ein
  Geständnis in einer Datenbank. Was es gibt: „gesperrt" als
  Statusmeldung eines Nutzers, damit Buddys nicht in eine Sperrung
  fahren.
- **Rankings bleiben im Netz.** Strava hat vorgeführt, was ein
  öffentliches Segment auf einem geduldeten Trail bewirkt: Es zieht
  Aufmerksamkeit an, auch die falsche. Ein Airtime-Ranking (Abschnitt 9)
  ist deshalb nur unter Buddys sichtbar, nie global.

## 8. Was von PilzBuddy übernommen wird

Das Projekt beginnt nicht bei null. Der Stack bleibt derselbe (Flutter
für Android und Web, Supabase, Riverpod ohne Codegen, go_router,
deutsche UI-Strings im Code, RLS als einzige Rechtequelle), und ein
großer Teil der Infrastruktur ist eins zu eins übertragbar:

| Baustein | Aus PilzBuddy | Für TrailBuddy |
|---|---|---|
| Auth, Profil, Passwort/E-Mail-Flows, Konto löschen | komplett | unverändert |
| Freundschaften, `are_friends`, Alias, Nachrichten, Push | komplett | unverändert; Alias wird zum Muster für Trail-Namen |
| RLS-Muster, Schema-Patches, Schema Check, Dry Run, Patch-Wächter | CI und `tool/` | unverändert, plus PostGIS im lokalen Stack |
| Version Guard, Release-Kanäle, Vorabversionen, Web-Vorschau, Service Worker | komplett | unverändert |
| Feedback-Bot, Fehlerberichte, Beendigungsgründe, Wochendigest | komplett | unverändert |
| Offline-Karten (PMTiles-Regionen, DACH-Übersicht, Foreground-Service für Downloads) | komplett | unverändert; die Wege-Ebene wird dazu für die Kandidaten-Heuristik gelesen |
| Tour-Aufzeichnung (Service-Isolate, JSON Lines, Brücke) | `lib/features/tour/` | wird zur Fahrt; Leergang-Logik entfällt |
| Ausgangskorb (Idempotenz per `client_id`) | `lib/data/outbox*.dart` | Aufträge: Aufzeichnung beitragen, Beitrag ändern |
| Höhengitter (Copernicus DEM, 20-m-Stufen, DACH, offline) | `elevation-data.yml` | Höhenmeter je Trail, Kandidaten-Heuristik, später Routing |
| Höhenlinien auf der Karte | `elevation_contours.dart` | unverändert |
| Schutzgebiets-Gitter | `protected_areas.dart` | Hinweis beim Anlegen |
| Erklär-Tour, Neuheiten, Kurzanleitung | Hinweis-Maschine | Skripte neu, Maschine gleich |
| Kartenfassade (MapLibre Android, flutter_map Web), Linienzüge | `map_view/` | Trails als Linien; die Fassade kann das seit 1.126.0 |

Nicht übernommen: Ampel, Arten, GBIF, Regen, Wald, Fundfotos,
iNaturalist — alles, was Pilz ist.

**Zwei Warnungen dazu:**

- **Kopieren, nicht extrahieren.** Die Versuchung, ein gemeinsames
  `buddy_core`-Paket herauszuziehen, ist groß und in diesem Moment
  falsch: Erst wenn TrailBuddy steht, sieht man, was WIRKLICH gleich
  geblieben ist. Ein Paket, das vorher entsteht, bremst beide Apps bei
  jeder Änderung. Kopie, mit Vermerk der Quellversion (1.213.0), und in
  einem halben Jahr die Frage neu stellen.
- **`CLAUDE.md` nicht kopieren.** Die Datei in PilzBuddy ist die
  Geschichte dieses einen Projekts. TrailBuddy bekommt eine eigene, die
  klein anfängt und nur trägt, was hier entschieden wurde — und eine
  davon ist die Regel „nichts Privates ins Repo", die sofort gilt.

**Neu** gegenüber PilzBuddy: PostGIS und Geometrie-Abgleich in der
Datenbank; Trails als Vektordaten offline auf der Karte (der
Zwischenspeicher hält Linien statt Punkte — GeoJSON-Text, dasselbe
IndexedDB/Datei-Muster); GPX-Parser (für Import und Export; PilzBuddy
hat einen Export, kein Import von Tracks); die Zerlegung von Fahrten.

## 9. Später: Routing und Airtime — nur die Randbedingungen

Beides wird nicht jetzt gebaut. Festzuhalten ist, was das Datenmodell
dafür heute schon tragen muss, damit es später nicht umgebaut wird.

**Routenvorschläge nach Höhenmetern oder Zeit.** Ein Router braucht
einen Graphen: Kanten mit Länge, Höhenmetern, Richtung und Kosten.
Trails sind die Kanten, die es sonst nirgends gibt; das Verbindungsnetz
kommt aus OSM (die PMTiles-Regionen tragen die Wege, aber nicht als
Graph — ein Graph muss aus den Kacheln oder aus einem OSM-Auszug
gebaut werden). Das Modell trägt deshalb ab v1 die **Richtung** und die
**beidseitige Befahrbarkeit** je Trail (4.3). Was es NICHT trägt und
später kommt: Knoten an Trail-Anfang und -Ende, Anschluss an das
Wegenetz. Kandidaten für die Maschine: BRouter (offline-fähig auf
Android, eigene Profile, Java), ein eigener A* über einen regionalen
Graphen (klein, aber Arbeit), Valhalla auf einem Server (kostet, und im
Funkloch tot). Entscheidung nach einer Messung, nicht vorher. Der
Zeit-Eingang ist ohne Nutzerprofil grob (Aufstieg 400–600 hm/h, Abfahrt
nach Trail-Länge), wird mit eigenen Fahrten kalibrierbar — die liegen
ja auf dem Gerät.

**Airtime und Ranking.** Sprünge lassen sich aus dem
Beschleunigungssensor lesen (Freifallphase: Betrag der Beschleunigung
nahe 0 für > 150 ms), Zuordnung zum Trail über die laufende Fahrt. Drei
Randbedingungen: Ranking nur unter Buddys (7); Manipulation ist
trivial (Telefon werfen) und deshalb ist es ein Spiel, kein
Leistungsnachweis — die Oberfläche sagt das; und es ist ein Anreiz zu
Risiko, das gehört in die Nutzungsbedingungen. Das Modell braucht dafür
eine Tabelle Ereignis-je-Fahrt-und-Trail, nichts davon in v1.

## 10. Entscheidungen des Betreibers (2026-09-27)

Alle acht sind entschieden; die verworfenen Alternativen stehen dabei,
damit die nächste Diskussion nicht bei null beginnt.

1. **Sichtbarkeit: nur Gefahrenes wandert weiter.** Ich sehe eigene
   Beiträge und die meiner direkten Buddys; weitergeben kann nur, wer
   selbst einen Beleg hat. Verworfen: „Weitergeben auf Tastendruck"
   (Kette unbegrenzt, der Erstbeitragende sieht nicht, wo sein Trail
   landet) und Transitivität (öffentliche Karte mit Anmeldung).
2. **Importierte Trails sind gleichwertig, mit Kennzeichnung.** Import
   mit Zeiten heißt „importiert", ohne Zeiten oder mit unplausiblen
   Geschwindigkeiten „geplant" (`source`, 3); beides mit niedrigerer
   Qualität als eine App-Aufzeichnung. Verworfen: Import nur für sich
   selbst (zwei Klassen von Trails, Start mit leerem Netz über Monate)
   und kein Import (ignoriert den Bestand).
3. **Offen registrieren, leere Karte, Einladung optional.** Wie
   PilzBuddy; ein Einladungslink füllt nur eine Buddy-Anfrage vor. Das
   Tor sitzt in der Sichtbarkeit, nicht an der Tür. Verworfen:
   Pflicht-Einladung (Play-Review braucht Testzugänge, Einladungskette
   ist eine weitere personenbezogene Tabelle) und Bürgen-Modell.
4. **Keine Fahrten in der Cloud in v1.** Fahrten bleiben auf dem
   Gerät, Sicherung ist der GPX-Export; Gerätewechsel heißt Fahrten
   weg, Trails bleiben. Verworfen für jetzt: private Sicherung (erste
   Tabelle, die mit gefahrener Zeit wächst; Bewegungsprofile unter
   Verantwortung des Betreibers). Eine spätere private Tabelle ändert
   nichts am Sichtbarkeitsmodell, die Tür bleibt offen.
5. **Die Messung läuft mit den Locus-Tracks des Betreibers** (GPX,
   gezippt; Zeiten und Höhen sind dabei). Die Sonderfälle — derselbe
   Trail mehrfach, Kehren, parallele Trails, Gegenrichtung, Fahrt mit
   mehreren Trails — sind im Bestand weitgehend enthalten. **Die
   Dateien gehören nicht ins Repo** (öffentlich; eine Fahrt beginnt an
   der Haustür): Sie liegen im DocuHub oder in einem lokalen Ordner, den
   das Werkzeug über eine Umgebungsvariable findet (Muster `KEYS_DIR`).
   Der Messbericht nennt Kennzahlen, keine Koordinaten und keine
   Ortsnamen; ein Wächter wie `private_info_test.dart` kommt von Anfang
   an mit. Das Werkzeug liest direkt aus dem Zip.
6. **Statusmeldungen in v1**, alle vier Werte, mit Datum; der jüngste
   gewinnt, alle bleiben sichtbar, eine neue Aufzeichnung setzt den
   eigenen Status auf „offen" (3). Verworfen: nur gesperrt/offen, oder
   später.
7. **Rechtliche Prüfung vor dem Play-Store-Eintrag.** Bis dahin nur
   persönlich bekannte Nutzer über die GitHub-APK. Nutzungsbedingungen
   und Datenschutzerklärung werden vorher als Entwurf aus dem Konzept
   vorbereitet, aufbauend auf PilzBuddy, damit der Prüfende etwas in der
   Hand hat. Die Grenze, an der aus einem privaten Werkzeug eine
   Plattform wird, ist der erste Nutzer über einen Einladungslink, den
   der Betreiber nicht selbst verschickt hat — die liegt vor dem
   Play-Store und ist bewusst in Kauf genommen.
8. **Web voll wie PilzBuddy, von Anfang an**: Import, Liste, Blatt,
   Buddys, Status UND Offline-Karten samt IndexedDB-Zwischenspeicher
   für Trails; nur das Aufzeichnen bleibt Android. Folgen: Jede
   Kartenfunktion läuft ab v1 auf beiden Engines (MapLibre, flutter_map),
   Trails als Linien im Web brauchen den GeoJSON-Zwischenspeicher ab
   v1, und für die Offline-Karten im Web gilt die bekannte Grenze
   (100 MB je Datei auf raw.githubusercontent.com, DACH als eine Datei
   nur bis z8; `docs/offline-karten-web.md` in PilzBuddy). Verworfen:
   Web nur zum Pflegen ohne Offline, oder Android zuerst.

## 11. Fahrplan

- **Phase 0 — Messen, bevor gebaut wird. ERLEDIGT am 2026-09-27**,
  Ergebnis in `docs/trail-abgleich-messung.md`; was sich dadurch am
  Konzept geändert hat, steht dort unter „Folgen". Ein Python-Werkzeug
  `tool/trail_match.py` (nur Standardbibliothek, wie die Werkzeuge in
  PilzBuddy) nimmt die Locus-Tracks des Betreibers direkt aus dem Zip
  (Pfad aus der Umgebung, nie im Repo), rechnet Deckung und Fréchet für
  alle Paare und schreibt eine Tabelle: Welche Paare sind „gleich",
  welche „Gabel", und stimmen die Schwellen? Ein `--self-test` mit
  synthetischen Fällen (Kehren, Parallelen, Gegenrichtung) prüft das
  Werkzeug, bevor es echte Daten sieht. Ergebnis ist
  `docs/trail-abgleich-messung.md` mit Kennzahlen ohne Koordinaten.
  Erst dann werden die Schwellen in SQL gegossen. Kein App-Code in
  dieser Phase.
- **Phase 1 — Grundgerüst.** Repo aus PilzBuddy-Bausteinen aufsetzen
  (Auth, Buddys, Karte, CI, Schema-Werkzeuge, eigene `CLAUDE.md`),
  PostGIS, Tabellen aus 3, `contribute_recording`, GPX-Import mit
  Zerlege-Blatt, Trails auf der Karte, Trail-Blatt mit Beitrag. Damit
  ist der Bestand des Betreibers und zweier Buddys drin, und die
  Verschmelzung ist im Feld prüfbar.
- **Phase 2 — Aufzeichnen.** Fahrt-Aufzeichnung aus der Pilztour,
  Kandidaten-Heuristik, Ausgangskorb.
- **Phase 3 — Offline und Austausch.** Offline-Karten, Trails im
  Zwischenspeicher, Nachrichten, Statusmeldungen, Zusammenführen im
  Netz.
- **Phase 4 — Routing.** Nach eigener Messung (9).
- **Phase 5 — Community.** Airtime, Ranking unter Buddys, Fotos am
  Trail (Fundfoto-Baustein).

Die Punkte aus Abschnitt 10 sind entschieden, Phase 0 ist gemessen. Der
nächste Schritt ist Phase 1.
