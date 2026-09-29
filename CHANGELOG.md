# TrailBuddy

*Was ist neu — in Alltagssprache, nach Themen. Jeder Block nennt seine Versionen.*

## Trails finden

*Versionen 0.32.0 bis 0.33.0, 2026-09-29*

- **Der Filter gilt jetzt auch auf der Karte** (0.33.0): Was du in der
  Liste filterst — Meine oder Von Buddys, „bis S2", neuer Hinweis,
  gemeldet —, zeigt auch die Karte, und umgekehrt: Dieselben Chips
  stehen auf der Karte im Blatt „Ebenen". Solange ein Filter gilt, sagt
  die Karte es oben („Gefiltert: bis S2 · 3 von 5 Trails"), und das X
  daneben hebt ihn auf. Suche und Sortierung bleiben in der Liste.

- **Suche in der Trail-Liste**: Tippe einen Trailnamen oder den Namen
  eines Buddys. Umlaute, Bindestriche und Leerzeichen sind egal —
  „rosskopf sued" findet „Roßkopf Süd". Bei einem Tippfehler zeigt die
  Liste den nächsten Namen und sagt dazu „Meintest du …?".
- **Filter und Sortierung**: Meine oder die meiner Buddys, „bis S2", nur
  mit neuem Hinweis, nur gemeldete. Sortieren nach zuletzt aktiv, Name,
  Länge, Abfahrt oder Schwierigkeit. Bei „bis S2" fehlen Trails, die noch
  niemand eingeschätzt hat — die Liste sagt, wie viele.

## Aussehen

*Versionen 0.28.0 bis 0.31.0, 2026-09-29*

- **Offline-Karten: eine Regel statt Grün und Rot** (0.31.0): Hell ist,
  was auf dem Gerät liegt, abgedunkelt der Rest — und um alles
  Gespeicherte läuft jetzt ein durchgehender Rand. Was du gerade dazu-
  oder wegnimmst, ist schraffiert und gestrichelt umrandet: helle
  Streifen auf Dunklem kommen dazu, dunkle Streifen auf Hellem fallen
  weg. Grün bleibt damit deinen Trails vorbehalten.
- **Neue Knöpfe auf der Karte** (0.30.0): Rechts unten stehen runde
  Knöpfe — Idee, Ebenen, Position — und darunter, gut mit dem Daumen
  erreichbar, der große Aufnahmeknopf: Lime zum Starten, orange mit
  Stop-Quadrat, solange die Fahrt läuft. Ist die Werkzeugleiste offen,
  hat der Ebenen-Knopf einen farbigen Rand.
- **Die Werkzeugleiste links ist größer und ruhiger**: Die Knöpfe sind
  größer (auch mit Handschuhen gut zu treffen), die Gruppen stehen mit
  etwas Abstand statt mit Trennlinien. Das gewählte Werkzeug ist
  hervorgehoben, Speichern leuchtet, sobald es etwas zu speichern gibt,
  und die Zahl darunter sagt, wie viel dazukommt und wegfällt. Maßstab
  und Quellenhinweis rücken zur Seite, solange die Leiste offen ist.

- **Ein eigenes Logo** (0.29.0): eine Serpentine — zwei Kehren und ein
  Ziel. Sie ersetzt das Flutter-Standardsymbol auf dem Startbildschirm
  des Telefons, im Browser-Tab und bei der installierten Web-App, und sie
  steht jetzt auch in der Anmeldung.
- **Auch die Benachrichtigungen tragen das Logo**: Meldungen von Buddys
  und die laufende Fahrt zeigen oben in der Statusleiste die Serpentine
  statt der Berge.
- **Neue Farben und Schriften**: TrailBuddy trägt jetzt Lime als
  Markenfarbe, eine schmale Titelschrift und für Kilometer, Höhenmeter
  und Schwierigkeit eine Schrift, in der Zahlen sauber untereinander
  stehen. Die Schriften sind in der App eingebaut und sehen auch ohne
  Empfang gleich aus.
- **Hell oder dunkel**: Im Profil unter „Erscheinungsbild" wählst du
  System, Hell oder Dunkel. Die Karte selbst bleibt hell.
- **Trails heben sich besser von der Karte ab**: Jede Linie hat einen
  schmalen weißen Rand. Die Farben sagen weiter dasselbe — Grün ist
  deins, Blau kommt von einem Buddy, Orange ist gemeldet.

## Karte

*Versionen 0.24.0 bis 0.27.0, 2026-09-28 bis 2026-09-29*

- **Offline-Karten über eine schmale Leiste statt eines halben Blatts**
  (0.27.0): Der Ebenen-Knopf öffnet links eine Werkzeugleiste, die Karte
  bleibt frei. Darin: Orte und offizielle Trails, der aktuelle
  Ausschnitt (Kamera), Fläche dazunehmen und wegnehmen, die Kacheln
  entlang der eigenen Trails, Rückgängig, „Meine Bereiche" (Karte mit
  Zahnrad), Speichern und Schließen. Speichern fragt noch einmal nach
  und nennt vorher Größe, Zahl der Kartenstücke und Zahl der Orte.
  Schließen — über das X, den Ebenen-Knopf oder die Zurück-Taste —
  fragt nach, wenn etwas noch nicht gespeichert ist.
- **Die hervorgehobenen Kacheln bleiben beim Zoomen stehen**: Gespeichertes
  und Geändertes erscheint jetzt immer in den feinen Kartenstücken,
  nicht mehr je nach Zoom in größeren.
- **Gespeichertes lässt sich wieder wegnehmen, und man sieht, was sich
  ändert**: Hell ist, was auf dem Gerät liegt. Grün schraffiert ist,
  was beim Speichern dazukommt; rot und andersherum schraffiert, was
  wegfällt. Der Radierer über hellen Kacheln markiert sie zum Entfernen,
  der Stift über schon Gespeichertem ändert nichts — es wird nicht
  doppelt geladen. Die Leiste zählt beides getrennt (+ und −), der
  Speicher-Dialog nennt, was geladen wird und wie viel Platz frei wird.
  Entfernen geht auch ohne Empfang; ein Bereich, von dem nichts übrig
  bleibt, verschwindet ganz.
- **Die Knöpfe der Karte stehen jetzt rechts**, Maßstab und
  Quellenhinweis links unten — dort liegt nichts mehr darüber.
- **Einpassen stürzt auf Android nicht mehr ab** (0.26.1): Wenn die Karte
  auf das Netz, einen Trail, eine Fahrt oder einen Bereich zoomte, gab
  es im Hintergrund jedes Mal einen Fehler — sichtbar war er nicht, die
  Karte stand meist trotzdem richtig. Jetzt rechnet die App den
  Ausschnitt selbst und setzt ihn in einem Schritt. Nebenbei landet
  „Meine Position" auf Android nicht mehr eine Zoomstufe zu nah.
- **Bereiche zeichnen** (0.26.0): Im Blatt „Offline-Karten" gibt es
  „Bereich zeichnen". Stift antippen, dann auf der Karte mit dem Finger
  eine Fläche umfahren — jedes Kartenstück, das sie berührt oder
  umschließt, kommt dazu und steht grün auf der Karte. Weitere Striche
  kommen dazu, der Radierer nimmt wieder weg, was man umfährt oder
  überwischt. „Entlang meiner Trails" lässt sich als Ausgangspunkt
  übernehmen und dann zurechtschneiden; „Rückgängig" nimmt den letzten
  Schritt zurück. Zwischen zwei Strichen lässt sich die Karte ganz normal
  verschieben. Die Zahl der Kartenstücke steht live da, „Speichern …"
  misst die Größe und lädt wie gewohnt — samt Orten. Wer das Blatt
  zwischendurch schließt, verliert seine Striche nicht.
- **„Offline-Karten" zeigt, was auf dem Gerät liegt** (0.25.0): Unter
  „Ebenen und Orte" gibt es jetzt den Punkt „Offline-Karten". Solange
  das Blatt offen ist, bleibt auf der Karte hell, was gespeichert ist,
  der Rest ist abgedunkelt — die Karte lässt sich dabei schieben und
  zoomen. Im Blatt stehen die gespeicherten Bereiche (Antippen zeigt
  einen auf der Karte), „Bereich speichern" und der Weg zur Verwaltung.
- **„Entlang meiner Trails" speichert nur noch, was die Trails
  berühren**: Bisher legte „Um meine Trails" ein Rechteck um alle
  Trails — bei verstreuten Trails vor allem Land dazwischen, und bei
  vielen Trails zu groß. Jetzt kommen nur die Kartenstücke mit, denen
  ein Trail näher als 1 km kommt, samt den Orten dort. Aus einem
  Bereich, der an der Grenze scheiterte, wird so ein Bruchteil. „Meine
  Bereiche" und „Aktualisieren" kennen die Form; alte Bereiche bleiben,
  wie sie sind.

## Benachrichtigungen

*Version 0.23.0, 2026-09-28*

- **Wenn ein Buddy einen Trail meldet, sagt es dir dein Telefon**: Ein
  Schalter im Profil („Benachrichtigungen", ab Werk aus) trägt dieses
  Gerät ein. Meldet danach ein Buddy einen Trail, den du siehst, als
  gesperrt, zerstört, verändert oder wieder offen — oder schreibt einen
  Hinweis dazu —, bekommst du eine Meldung; mehrere Meldungen in kurzer
  Zeit werden zu einer. Antippen zeigt den Trail auf der Karte, bei
  mehreren die Liste.
- **In der Meldung steht kein Inhalt.** Kein Trailname, kein Name, keine
  Koordinate, nicht der Text des Hinweises — eine Meldung läuft über
  Googles Server, und ein Trail verlässt sein Netz nicht. Was passiert
  ist und wo, zeigt die App erst beim Öffnen. Die Datenschutzerklärung
  nennt den neuen Weg.
- „Testnachricht senden" prüft die ganze Kette bis zu diesem Gerät.
  Solange der Betreiber das Firebase-Projekt noch nicht angelegt hat,
  sagt der Schalter, dass Benachrichtigungen in diesem Build noch nicht
  eingerichtet sind.

## Buddys

*Version 0.22.0, 2026-09-28*

- **Nach dem Annehmen einer Anfrage sagt die App, was sich auf der Karte
  tut**: „Mit Jan verbunden: 14 Trails gemeinsam, 8 neu von Jan, 5 neu
  für Jan." Gemeinsam sind Trails, die ihr beide belegt habt — sie sind
  ab jetzt EIN Trail auf beiden Karten. Gezählt wird erst nach dem
  Annehmen, nie davor: Vorher wäre die Zahl ein Blick in die Sammlung
  eines Fremden. Deine privaten Trails zählen nicht als „neu für Jan",
  er sieht sie ja nicht.

## Wenn die App abstürzt

*Version 0.21.0, 2026-09-28*

- **Ein Absturz meldet sich beim nächsten Start selbst**: Wird die App
  von Android beendet — weil sie nicht mehr reagiert hat, abgestürzt ist
  oder der Speicher knapp war —, liest sie das beim nächsten Öffnen aus
  Androids eigener Liste und schickt den Grund als Fehlerbericht: mit
  Speicherwerten und einem Auszug des Thread-Dumps, aber ohne deine
  Trails, deine Position oder deine Fahrt. Normales Beenden (wegwischen,
  Neustart) wird nicht gemeldet. Nur Android ab Version 11.
- Fehlerberichte werden wie bisher nach 90 Tagen gelöscht; der Betreiber
  sieht sie als wöchentliche Zusammenfassung ohne Nutzerkennung.

## Fahrt zerlegen

*Version 0.20.0, 2026-09-28*

- **Nach der Fahrt zeigt ein Blatt, was daraus wird**: Die Fahrt liegt
  auf der Karte, zerlegt in Stücke. **Wieder gefahren** sind Trails
  deines Netzes, die unter deiner Spur liegen — vorangehakt, als Beleg
  beigesteuert, das hält den Trail aktuell. **Kandidaten für neue
  Trails** sind Stücke mit anhaltendem Gefälle abseits von Fahr- und
  Forststraßen: Mit zwei Griffen schneidest du zu (die Linie auf der
  Karte folgt), gibst einen Namen und einen S-Grad, oder verwirfst.
  Anfahrt, Forstweg und Straße werden nicht angeboten. Ein Kandidat, der
  nahe bei Start oder Ziel deiner Fahrt liegt, bekommt einen Hinweis —
  keinen Riegel.
- **Die Wege kennt die App nur aus einem gespeicherten Bereich.** Ohne
  Bereich bis Zoomstufe 13 über der Fahrt findet sie keine Kandidaten
  und sagt das; wieder gefahrene Trails gehen trotzdem. Also erst den
  Bereich speichern, dann die Fahrt aus „Meine Fahrten" zerlegen (die
  Schere).
- **Auch für GPX-Fahrten**: Im Import führt die Schere neben einer
  Fahrt auf die Karte in dasselbe Blatt. Höhen aus der Datei werden
  mit beigesteuert; die GPS-Höhe einer eigenen Aufzeichnung dient nur
  der Suche nach dem Gefälle und geht nicht mit.
- Die Fahrt bleibt als Ganzes auf dem Gerät; beigesteuert werden nur
  die gewählten Stücke.

## Karte

*Versionen 0.16.0, 0.17.0, 0.18.0 und 0.19.0, 2026-09-28*

- **Bereiche für unterwegs speichern** (0.19.0): Unter „Ebenen und Orte"
  gibt es jetzt „Bereich für unterwegs speichern" — der aktuelle
  Ausschnitt oder ein Rahmen um deine Trails mit 2 km Rand. Die Größe
  steht vorher da, genau gemessen, nicht geschätzt. Die Karte bis
  Zoomstufe 13 samt Orten bleibt dann auf dem Gerät und ist ohne
  Empfang die Karte. „Meine Bereiche" im Profil zeigt, was liegt, mit
  Größe und Kartenstand; ein neuerer Stand wird angeboten, nie
  aufgezwungen. Bereiche werden nie von selbst gelöscht.
- **Die Orte auf der Karte kommen jetzt auch vom eigenen Kartenspeicher**
  (0.18.0): Einkehr, Wasser, Rad-Service und Sonstiges liegen als fertige
  Dateien je Rasterzelle neben der Karte, einmal im Monat frisch aus
  OpenStreetMap. Die App lädt nur die Zellen, die dein Ausschnitt
  berührt, und fragt keinen fremden Dienst mehr live — schneller, und
  ohne dass dein genauer Ausschnitt irgendwohin geht. Filter, Nadeln und
  das Blatt beim Antippen bleiben, wie sie waren.
- **Die Karte kommt jetzt von unserem eigenen Kartenspeicher** (0.17.0):
  eine Vektorkarte von Deutschland, Österreich und der Schweiz bis
  Zoomstufe 13, mit Forstwegen, Pfaden und Steigen als eigene Linien
  statt in der Sammelgrube — Trails SIND die Wege. Die App lädt davon
  nur die Stücke, die der Ausschnitt braucht. Die Kachelserver von
  OpenStreetMap werden nicht mehr angefragt.

- **Neue Karten-Engine auf Android**: Die Karte rendert jetzt nativ auf
  der Grafikeinheit (MapLibre) — flüssiger beim Wischen und Zoomen,
  besonders mit vielen Trails. Im Browser bleibt alles wie bisher.
- **Eine Übersichtskarte ohne Empfang**: Fällt das Netz weg, liegt
  unter deinen Trails eine mitgelieferte Übersicht von Deutschland,
  Österreich und der Schweiz (Länder, Städte, große Straßen und Wege) —
  statt einer leeren Fläche. Sie steckt in der App und braucht kein
  Netz. Fein aufgelöste Karten für ganze Gebiete kommen als Nächstes.
- **Tippen auf Linien und Orte** funktioniert auf beiden Plattformen
  gleich: Liegt ein Trail über einer Stecknadel, gewinnt der Trail.

## Ohne Empfang

*Version 0.15.0, 2026-09-28*

- **Deine Trails auch im Funkloch**: Die App merkt sich beim letzten
  Laden mit Netz das ganze Netz — Trails, Beiträge, Hinweise — auf dem
  Gerät. Startest du sie ohne Empfang, siehst du diesen Stand auf Karte
  und Liste, mit dem Hinweis, von wann er ist. Sobald wieder Netz da ist,
  kommt der aktuelle.
- Ein Fehler des Servers wird weiterhin als Fehler gezeigt, nicht mit dem
  alten Stand überdeckt. Beim Abmelden wird die Kopie gelöscht. Im
  Browser gibt es sie noch nicht.

## Ausgangskorb

*Version 0.14.0, 2026-09-28*

- **Beisteuern ohne Netz**: Importierst du eine GPX-Datei oder änderst
  deinen Beitrag zu einem Trail, während kein Netz da ist, geht nichts
  verloren. Der Auftrag wartet in einem Ausgangskorb auf deinem Gerät und
  wird gesendet, sobald wieder Verbindung besteht — beim nächsten
  Netzwechsel, beim nächsten Start oder wenn du den Hinweis oben auf der
  Karte antippst.
- **Wartende Trails siehst du sofort**: gestrichelt auf der Karte, in
  der Liste unter „Wartet auf Übertragung". So steuerst du dieselbe Datei
  nicht zweimal bei. Lehnt der Server einen Auftrag ab, steht der Grund
  dabei, mit „Erneut versuchen" und „Aus dem Ausgangskorb entfernen".
- Ein Serverfehler ist kein Funkloch: Er wird weiter sofort gemeldet
  statt still gesammelt. Im Browser gibt es den Korb noch nicht.

## Fahrt aufzeichnen

*Version 0.13.0, 2026-09-28*

- **Der Aufnahme-Knopf auf der Karte**: Ein Tipp startet die Fahrt, die
  App zeichnet deinen Weg auf — auch mit dem Telefon in der Tasche oder
  wenn du die App weggewischt hast. Solange sie läuft, steht eine
  Benachrichtigung in der Statusleiste; oben auf der Karte siehst du
  Strecke und Dauer, und die Spur wächst als dunkle Linie mit.
- **Die Fahrt bleibt auf deinem Gerät.** Unter „Meine Fahrten" im Profil
  liegen alle Aufzeichnungen: ansehen, auf der Karte zeigen, löschen.
  Nichts davon geht an den Server und nichts ins Android-Backup. Welche
  Trails du wieder gefahren bist und wo ein neuer liegt, zeigt bald das
  Zerlege-Blatt — bis dahin bleibt die Fahrt, wie sie ist.
- **Nach einem Neustart geht es weiter**: Räumt Android die App zwischendurch
  weg, hat der Dienst weiter aufgezeichnet, und die Karte holt die Fahrt
  beim nächsten Öffnen zurück. Nach zwölf Stunden hört eine vergessene
  Aufnahme von selbst auf.
- Im Browser gibt es die Aufzeichnung nicht: Ein Tab im Hintergrund
  bekommt keine Positionen.

## Wo bin ich?

*Version 0.12.0, 2026-09-28*

- **Deine Position auf der Karte**: Der neue Knopf „Meine Position"
  unten links springt zu dir und zeigt dich als dunklen Punkt mit einem
  Kreis für die Genauigkeit. Beim ersten Tipp fragt die App nach dem
  Standort; vorher nie. Der Standort bleibt auf deinem Telefon.
- **Die Karte dreht sich nicht mehr**: Norden bleibt oben, auch wenn
  beim Zoomen mit zwei Fingern die Hand etwas dreht.

## Auch ausgeschildert

*Version 0.11.0, 2026-09-28*

- **„Auch ausgeschildert als …" im Trail-Blatt**: Liegt ein Trail aus
  deinem Netz auf einem offiziellen Trail, steht das jetzt in seinem
  Blatt — ebenso, wenn er nur ein Stück davon ist oder einen offiziellen
  Trail enthält. Ist der offizielle Trail gesperrt, steht auch das da,
  mit der Angabe, von wem die Sperre kommt. Ein Tipp öffnet das Blatt
  des offiziellen Trails.

## Offizielle Trails

*Version 0.10.0, 2026-09-28*

- **Offiziell ausgewiesene Singletrails auf der Karte**: Violett
  gestrichelt, unter den Trails deines Netzes. Den Anfang macht Tirol mit
  gut 180 freigegebenen Singletrails vom Land. Sie erscheinen ab mittlerer
  Zoomstufe, sobald die Karte eine Region zeigt, für die es Daten gibt.
- **Ein Tipp zeigt, was die Quelle sagt**: Name, Länge, Höhenmeter,
  Schwierigkeit laut Quelle, Beschreibung und ob der Trail freigegeben
  oder gesperrt ist — mit der Angabe, von wem das kommt. Gesperrte Teile
  sind grau.
- **Auch ohne Empfang**: Einmal geladen, merkt sich die App die Region
  und zeigt sie auch im Funkloch.
- **Abschaltbar**: Der Knopf „Ebenen und Orte" unten links (vorher nur
  „Orte") hat dafür einen Schalter.

## Lange Namen beim Import

*Version 0.9.1, 2026-09-28*

- **Kein Fehler mehr bei langen Trail-Namen**: Manche Apps (etwa Locus bei
  Spuren aus Trailforks) schreiben Namen wie „DREI%20EICHEN%20-%20…" in
  die Datei. Die App macht daraus wieder „DREI EICHEN - …" und kürzt, was
  länger als 80 Zeichen ist, statt den Import abzubrechen.
- **Namenlose Trails reparieren**: Ist ein Trail dadurch früher ohne Namen
  angelegt worden, importiere die Datei einfach noch einmal — der Name
  wird übernommen, ohne einen zweiten Trail anzulegen.

## Ganzer Bestand auf einmal

*Version 0.9.0, 2026-09-28*

- **Bis zu 500 Trails am Tag beisteuern** statt 50: Dein ganzes
  GPX-Archiv geht jetzt an einem Abend durch, statt sich über zehn Tage
  zu ziehen.

## Hinweise für Buddys

*Version 0.8.0, 2026-09-28*

- **„Baum liegt quer nach der zweiten Kehre"**: Zu jedem Trail, den du
  siehst, kannst du im Trail-Blatt einen Hinweis schreiben. Deine Buddys,
  die den Trail auch sehen, finden ihn dort mit Datum.
- **Neues fällt auf**: Hat ein Buddy in den letzten sieben Tagen einen
  Hinweis geschrieben, leuchtet der Trail auf der Karte gelb umrandet, und
  in der Liste steht „neuer Hinweis" — bis du das Trail-Blatt geöffnet
  hast.
- **Erledigt?** Ist der Baum weggeräumt, kann jeder, der den Hinweis
  sieht, ihn entfernen. Nach drei Monaten verschwinden alte Hinweise von
  selbst; der jüngste bleibt stehen, bis ihn jemand entfernt.
- **Status mit Grund**: Wer den Zustand eines Trails ändert (etwa auf
  gesperrt), kann gleich dazuschreiben, warum.

## Orte: eigene Symbole und Detailfilter

*Version 0.7.0, 2026-09-28*

- **Jede Art an ihrem Symbol erkennbar**: Biergärten zeigen immer den
  Bierkrug — auch Gasthäuser mit Biergarten, die bisher das Besteck
  hatten. Cafés zeigen ein Stück Kuchen, Quellen ein Wasserglas.
- **Detailfilter**: Unter jeder eingeschalteten Gruppe stehen ihre Arten
  zum einzelnen Abwählen — zum Beispiel Einkehr ohne Kneipen, oder
  Wasser nur mit Trinkwasser.

## Höhen für ältere Trails nachtragen

*Version 0.6.0, 2026-09-28*

- **Einfach dieselbe Datei noch einmal importieren**: Trails, die du vor
  Version 0.3.0 beigesteuert hast, haben noch keine Höhenmeter. Wählst du
  die Original-GPX (oder den ganzen Zip) noch einmal, erkennt die App sie
  und trägt die Höhen nach — ohne doppelten Trail und ohne dein
  Tageslimit zu belasten.
- **Nichts doppelt**: Was du schon beigesteuert hast, steht im Import als
  „schon beigesteuert" und wird nicht noch einmal hochgeladen.

## Orte auf der Karte

*Version 0.5.0, 2026-09-28*

- **Trinkwasser, Einkehr, Rad-Service**: Die Karte zeigt ab Zoomstufe 12
  Orte aus OpenStreetMap als Stecknadeln — Café, Biergarten, Hütte,
  Brunnen und Quelle, Reparaturstation, Radladen, E-Bike-Ladestation,
  Unterstand, Toilette, Aussichtspunkt und Parkplatz.
- **Du wählst, was du siehst**: Der Knopf unten links schaltet die vier
  Gruppen einzeln an und aus. Am Anfang ist nur Wasser an.
- **Ein Tipp auf eine Nadel** zeigt Name, Öffnungszeiten und bei Quellen,
  ob das Wasser als trinkbar eingetragen ist.

## Höhenmeter an echten Fahrten abgestimmt

*Version 0.4.1, 2026-09-27*

- **Genauere Höhenmeter**: Ab wann ein Auf und Ab zählt, ist jetzt an
  Hunderten echten Fahrten gemessen statt geschätzt. Auf reinen Abfahrten
  erscheint kein erfundener Anstieg mehr, auf Touren geht weniger echter
  Anstieg verloren.

## Schwierigkeit nach der Singletrail-Skala

*Version 0.4.0, 2026-09-27*

- **S0 bis S5, von euch eingeschätzt**: Das Trail-Blatt zeigt den Wert
  deiner Buddys, die Spanne und wie viele eingeschätzt haben — zum
  Beispiel „S2 · S1–S3 · 4 Einschätzungen". Ein Tipp darauf zeigt, wer
  was gesagt hat.
- **Deine Einschätzung mit einem Tipp** direkt im Blatt, bei Trails, die
  du selbst gefahren bist. Noch ein Tipp nimmt sie zurück.
- **Was heißt S3?** Das „?" neben der Auswahl erklärt jede Stufe in einem
  Satz, auch im Dialog „Mein Beitrag".

## Höhenmeter und Höhenprofil

*Version 0.3.0, 2026-09-27*

- **Jeder Trail zeigt seine Höhenmeter**: „↓ 420 Hm · ↑ 35 Hm" und das
  mittlere Gefälle, im Trail-Blatt und kurz in der Liste.
- **Ein Höhenprofil** im Trail-Blatt, immer in Fahrtrichtung des Trails,
  mit dem steilsten Stück darunter.
- Kleine Wellen aus dem GPS-Rauschen zählen nicht mit — auf einer Abfahrt
  steht deshalb nicht plötzlich „40 m bergauf".
- **Trails, die du vor dieser Version importiert hast, haben noch keine
  Höhen** — die App hat sie damals nicht mitgeschickt. Das Blatt sagt es.
  Ein Weg, sie nachzutragen, kommt.

## Idee oder Fehler melden

*Version 0.2.0 und 0.2.1, 2026-09-27*

- **Die Glühbirne auf der Karte** (und im Profil unter „Idee oder Fehler
  melden"): Wünsche und Fehler gehen direkt an den Entwickler.
- Die Meldung wird ein **öffentlicher** Eintrag im GitHub-Projekt — mit
  deinem Text, aber ohne deinen Namen. Bitte keine Trailnamen oder Orte
  hineinschreiben; der Dialog erinnert daran.

## GPX-Import, der wirklich Dateien findet

*Version 0.1.1, 2026-09-27*

- **Auf Android ließ sich keine Datei auswählen** — GPX- und Zip-Dateien
  waren im Auswahldialog ausgegraut. Jetzt kann man jede Datei wählen;
  was kein GPX ist, sagt die App mit Namen.
- **Zip-Archive werden ausgepackt**, zum Beispiel ein Track-Export aus
  Locus: Jede GPX-Datei darin wird zu einer Spur mit eigenem Namen.
- **Mehr als 50 Trails auf einmal?** Der Server nimmt am Tag höchstens 50
  an. Der Import hält dann an, statt jeden weiteren als Fehler zu melden,
  und die übrigen bleiben für den nächsten Tag angehakt.

## Der Anfang

*Version 0.1.0, 2026-09-27*

Das Grundgerüst: Anmelden, Buddys finden, Trails aus GPX-Dateien
importieren und auf der Karte sehen. Noch nichts für den Alltag, aber der
Boden, auf dem alles Weitere steht.
