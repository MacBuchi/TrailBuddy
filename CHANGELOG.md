# TrailBuddy

*Was ist neu — in Alltagssprache, nach Themen. Jeder Block nennt seine Versionen.*

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
