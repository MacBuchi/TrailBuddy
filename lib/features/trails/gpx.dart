import 'package:xml/xml.dart';

/// Ein Punkt einer GPX-Spur. `ele` und `time` fehlen bei gezeichneten
/// Routen (Konzept 5.2: „geplant", nicht „gefahren").
class TrackPoint {
  const TrackPoint(this.lat, this.lon, {this.ele, this.time});

  final double lat;
  final double lon;
  final double? ele;
  final DateTime? time;
}

/// Eine Spur aus einer GPX-Datei: ein `<trk>` mit allen Segmenten
/// hintereinander (ein Segmentbruch ist eine Lücke, kein neuer Trail) —
/// oder ein `<rte>`, wenn die Datei nur eine Route trägt.
class GpxTrack {
  const GpxTrack({required this.name, required this.points});

  final String name;
  final List<TrackPoint> points;
}

class GpxFormatException implements Exception {
  const GpxFormatException(this.message);
  final String message;

  @override
  String toString() => 'GpxFormatException: $message';
}

/// Liest alle Spuren einer GPX-Datei. Namensräume werden ignoriert:
/// Locus, Komoot, Garmin und Strava schreiben alle GPX 1.1, aber mit
/// verschiedenen Präfixen und Erweiterungen; uns interessieren nur
/// `trkpt`/`rtept` mit `lat`, `lon`, `ele`, `time`.
///
/// Doppelte aufeinanderfolgende Punkte (Locus schreibt sie an Pausen)
/// fallen weg. Spuren mit weniger als zwei Punkten fallen weg.
List<GpxTrack> parseGpx(String xml, {String fallbackName = 'Ohne Namen'}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw GpxFormatException('Kein gültiges XML: ${e.message}');
  }
  final root = doc.rootElement;
  if (root.name.local != 'gpx') {
    throw GpxFormatException('Keine GPX-Datei (Wurzel ist <${root.name.local}>).');
  }
  final tracks = <GpxTrack>[];
  for (final trk in root.findElements('trk')) {
    final points = <TrackPoint>[];
    for (final seg in trk.findElements('trkseg')) {
      _collect(seg.findElements('trkpt'), points);
    }
    if (points.length >= 2) {
      tracks.add(GpxTrack(name: _name(trk) ?? fallbackName, points: points));
    }
  }
  for (final rte in root.findElements('rte')) {
    final points = <TrackPoint>[];
    _collect(rte.findElements('rtept'), points);
    if (points.length >= 2) {
      tracks.add(GpxTrack(name: _name(rte) ?? fallbackName, points: points));
    }
  }
  return tracks;
}

String? _name(XmlElement parent) {
  final el = parent.getElement('name');
  final text = el?.innerText.trim();
  return (text == null || text.isEmpty) ? null : decodeTrackName(text);
}

final _percentEscape = RegExp(r'%[0-9A-Fa-f]{2}');

/// Manche Apps (Locus beim Export von Trailforks-Spuren) schreiben den
/// Namen URL-kodiert: „DREI%20EICHEN%20-%20…". Dekodiert wird nur, was
/// wie ein Escape aussieht und sich sauber dekodieren lässt — ein Name
/// wie „100 % Flow" bleibt, wie er ist.
String decodeTrackName(String name) {
  if (!_percentEscape.hasMatch(name)) return name;
  try {
    return Uri.decodeComponent(name).trim();
  } on ArgumentError {
    return name;
  } on FormatException {
    return name;
  }
}

void _collect(Iterable<XmlElement> elements, List<TrackPoint> into) {
  for (final p in elements) {
    final lat = double.tryParse(p.getAttribute('lat') ?? '');
    final lon = double.tryParse(p.getAttribute('lon') ?? '');
    if (lat == null || lon == null) continue;
    if (lat.abs() > 90 || lon.abs() > 180) continue;
    if (into.isNotEmpty &&
        (into.last.lat - lat).abs() < 1e-9 &&
        (into.last.lon - lon).abs() < 1e-9) {
      continue;
    }
    final ele = double.tryParse(p.getElement('ele')?.innerText.trim() ?? '');
    final timeText = p.getElement('time')?.innerText.trim();
    final time = timeText == null ? null : DateTime.tryParse(timeText);
    into.add(TrackPoint(lat, lon, ele: ele, time: time?.toUtc()));
  }
}
