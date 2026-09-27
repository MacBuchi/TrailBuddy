// Eigene Startdatei der Web-App (#387).
//
// Flutter erzeugt diese Datei sonst selbst. Sobald sie hier liegt, nimmt
// der Build sie als Vorlage und ersetzt die drei Platzhalter unten
// (Lader, Build-Konfiguration, Bauversion).
//
// **Die Platzhalter dürfen in KEINEM Kommentar stehen** — auch nicht als
// Beispiel. Der Build ersetzt sie überall in der Datei, und der Lader ist
// mehrzeilig: Aus einer `//`-Zeile bricht er sofort aus, danach ist die
// Datei Syntaxmüll und die App startet gar nicht mehr. Genau so beim Bau
// dieses Features passiert — sichtbar nur als `SyntaxError` in der
// Browser-Konsole.
//
// **Warum wir sie brauchen, und zwar zwingend:** Die erzeugte Fassung
// übergibt dem Loader `serviceWorkerSettings`. Der registriert damit
// `flutter_service_worker.js` — eine 784-Byte-Datei, deren einzige
// Aufgabe es ist, sich selbst wieder abzumelden (Flutters eigener Worker
// ist abgekündigt). Und er tut das genau dann, wenn für diesen Scope
// schon eine Registrierung existiert. Ab dem zweiten Besuch wäre das
// UNSERE — sie würde überschrieben und meldete sich ab. Der Cache wäre
// bei jedem Laden weg, ohne eine einzige Fehlermeldung.
//
// Der Aufruf unten hat deshalb kein `serviceWorkerSettings`, und die
// Versionsnummer aus dem Build wandert stattdessen an unseren Worker.
{{flutter_js}}
{{flutter_build_config}}

// Eigener Einstieg statt des Standardaufrufs: Von hier an meldet die
// Seite dem Worker fortlaufend, was sie geholt hat. Ohne diesen Schritt
// läge nach dem ERSTEN Besuch nur die Hülle im Cache — die ersten
// Anfragen gehen raus, bevor der Worker aktiv ist, er sieht sie also nie.
// Der Offline-Start hinge damit daran, dass jemand die Seite zufällig ein
// zweites Mal öffnet.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    warmServiceWorkerCache();
  },
});

// Gemeldet wird, was der Browser WIRKLICH geholt hat: Welche
// CanvasKit-Variante und welche Schriften nötig sind, entscheidet er
// selbst. Eine gepflegte Aufzählung im Worker wäre bei jeder Änderung
// still falsch — und „still falsch" heißt hier: startet ohne Netz nicht
// mehr.
//
// **Ein BEOBACHTER, keine Momentaufnahme** (#427). Bis 1.128.1 stand hier
// ein einmaliges `getEntriesByType('resource')` gleich nach dem ersten
// Bild. Das ersetzte die Liste zwar, tauschte sie aber gegen einen
// Wettlauf: Was bis zu genau diesem Augenblick geholt war, kam in den
// Cache, alles Spätere nie. Zwei Läufe desselben Builds legten daraufhin
// verschiedene Dateien ab, und einer der beiden startete ohne Netz nicht.
// `buffered: true` liefert das bereits Geholte UND jedes weitere Stück,
// solange die Seite lebt; damit gibt es keinen Augenblick mehr, an dem
// gemessen wird.
//
// Der erste Besuch verhält sich dadurch wie jeder weitere: Ab dem zweiten
// legt der Worker als Kontrolleur der Seite ohnehin jede erfolgreiche
// eigene Antwort ab. Der Beobachter reicht ihm nur nach, was er beim
// ersten Mal nicht sehen konnte.
function warmServiceWorkerCache() {
  if (!('serviceWorker' in navigator)) return;
  if (typeof PerformanceObserver === 'undefined') return;
  navigator.serviceWorker.ready
      .then(function (registration) {
        var worker = registration.active;
        if (!worker) return;
        var observer = new PerformanceObserver(function (list) {
          var urls = list.getEntries()
              .map(function (entry) { return entry.name; })
              .filter(function (name) {
                return name.startsWith(self.location.origin);
              });
          if (urls.length) worker.postMessage({type: 'warm', urls: urls});
        });
        observer.observe({type: 'resource', buffered: true});
      })
      .catch(function () {
        // Kein Worker, kein Vorwärmen — die App läuft trotzdem.
      });
}

// Registriert wird RELATIV, damit der Scope dem `--base-href` folgt:
// `/trailbuddy/` in der Freigabe, `/trailbuddy-preview/` in der Vorschau.
// `updateViaCache: 'none'` hält den Worker selbst aus dem HTTP-Cache
// heraus — sonst könnte ausgerechnet die Datei alt bleiben, die alles
// andere aktuell halten soll.
//
// Die Versionsnummer würfelt Flutter je Build neu. Sie ist keine
// Prüfsumme, aber genau das, was hier gebraucht wird: neuer Deploy,
// neuer Worker, neuer Cache. `sw.js` liest sie aus seiner eigenen URL —
// eine Quelle, keine zweite Stelle zum Synchronhalten.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker
        .register('sw.js?v=' + {{flutter_service_worker_version}},
                  {updateViaCache: 'none'})
        .catch(function (error) {
          // Kein Offline-Start ist kein Grund, die App nicht zu starten.
          console.warn('Service Worker nicht registriert:', error);
        });
  });
}
