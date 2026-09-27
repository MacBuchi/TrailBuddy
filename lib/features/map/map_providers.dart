import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Der Kachel-Lieferant der Karte — ein Provider, damit Tests eine
/// transparente 1×1-PNG einhängen (kein Netz in Tests, PilzBuddy-Regel).
final mapTileProviderProvider =
    Provider<TileProvider>((ref) => NetworkTileProvider());
