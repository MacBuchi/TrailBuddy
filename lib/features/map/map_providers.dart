import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Die Online-Rasterquelle — heute noch OSM, bis der Vektor-Host steht
/// (`docs/konzept-offline-karten.md`, Schritt 2). Beide Engines lesen
/// dieselbe Vorlage.
const kOsmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// OSM liefert Kacheln nur bis Zoom 19; darüber skaliert jede Engine hoch.
const kOsmMaxZoom = 19;

/// Der Kachel-Lieferant der flutter_map-Engine — ein Provider, damit Tests
/// eine transparente 1×1-PNG einhängen (kein Netz in Tests).
final mapTileProviderProvider =
    Provider<TileProvider>((ref) => NetworkTileProvider());
