// Der Link zur Quelle im eigenen Beitrag (#103, Patch 012,
// `docs/konzept-rework.md` 4): die Seite eines Vereins mit Beschreibung
// und Regeln. Er gehört dem Beitrag wie der Name. Die App ruft ihn nie
// selbst ab — ein Tipp öffnet ihn im Browser, sonst geht nichts raus.

/// Höchstlänge — dieselbe wie der Check `trail_details_link_check`.
const kTrailLinkMaxLength = 500;

/// Hosts, deren Link in einer GPX-Datei nichts über den Trail sagt: der
/// Hersteller des Geräts oder der App (`<metadata><link>` ist dort meist
/// die Werbung des Exporteurs), oder die eigene Aktivität in einem
/// Tourenportal — die verriete Buddys das eigene Konto dort. Gilt nur
/// für den VORSCHLAG aus der Datei; von Hand darf man jeden Link setzen.
const kLinkIgnoredHosts = {
  'garmin.com',
  'strava.com',
  'komoot.com',
  'komoot.de',
  'locusmap.app',
  'locusmap.eu',
  'polar.com',
  'suunto.com',
  'wahoofitness.com',
  'ridewithgps.com',
  'gpsies.com',
  'bikemap.net',
  'apple.com',
  'google.com',
};

/// Ein Link, wie ihn die Datenbank annimmt: https, mit Host, ohne Query
/// und Fragment (Freigabelinks tragen dort Tokens), ohne Leerzeichen,
/// höchstens [kTrailLinkMaxLength] Zeichen. Sonst null. Ohne Schema wird
/// `https://` davorgesetzt — „trailsurfers-bw.de" tippt man so.
String? sanitizeLink(String? raw) {
  var text = raw?.trim() ?? '';
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
  if (!text.contains('://')) text = 'https://$text';
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return null;
  }
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  final out = Uri(
    scheme: 'https',
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
  return out.length <= kTrailLinkMaxLength ? out : null;
}

/// [sanitizeLink] für den Vorschlag aus einer GPX-Datei: dazu null für
/// die Hosts aus [kLinkIgnoredHosts] und ihre Unterdomänen.
String? linkFromFile(String? raw) {
  final link = sanitizeLink(raw);
  if (link == null) return null;
  final host = Uri.parse(link).host;
  final ignored = kLinkIgnoredHosts.any((h) => host == h || host.endsWith('.$h'));
  return ignored ? null : link;
}

/// „trailsurfers-bw.de" — was die App vom Link zeigt: der Host ohne
/// „www.". Der ganze Link steht erst im Browser.
String linkHost(String link) {
  final host = Uri.tryParse(link)?.host ?? link;
  return host.startsWith('www.') ? host.substring(4) : host;
}
