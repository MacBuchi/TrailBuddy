// Was der Web-Push-Worker an die Seite weiterreicht (#34; PilzBuddy
// 1.203.0 als Muster).
//
// Der Worker (`web/push/firebase-messaging-sw.js`) schickt einer
// fokussierten App eine eintreffende Meldung und einem Tipp das Ziel per
// `postMessage`. Diese Datei hört dort zu — nur das Abonnieren ist
// plattformabhängig; was eine Nachricht bedeutet, steht in
// `push_messaging.dart` (`pushBridgeMessageOf`) und ist auf der VM prüfbar.
//
// Dieselbe Bauweise wie `browser_db.dart`: Der Web-Weg ist die Vorgabe,
// `dart.library.io` wählt den Stub.
export 'push_web_bridge_web.dart'
    if (dart.library.io) 'push_web_bridge_stub.dart';
