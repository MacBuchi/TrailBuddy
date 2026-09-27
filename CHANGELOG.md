# TrailBuddy

*Was ist neu — in Alltagssprache, nach Themen. Jeder Block nennt seine Versionen.*

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
