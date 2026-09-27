import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'poi.dart';
import 'poi_source.dart';

/// Die Orte als Stecknadeln — eine Ebene INNERHALB von `FlutterMap`, damit
/// sie die Kamera kennt. Ab [kPoiMinZoom] lädt sie die Zellen des
/// Ausschnitts nach, kurz verzögert, damit ein Wischen über die Karte
/// nicht zehn Abfragen auslöst.
class PoiLayer extends ConsumerStatefulWidget {
  const PoiLayer({super.key});

  @override
  ConsumerState<PoiLayer> createState() => _PoiLayerState();
}

class _PoiLayerState extends ConsumerState<PoiLayer> {
  Timer? _debounce;
  String? _requested;

  static const _delay = Duration(milliseconds: 500);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final groups = ref.watch(poiGroupsProvider);
    final state = ref.watch(poiControllerProvider);
    final hidden = ref.watch(poiHiddenKindsProvider);
    if (groups.isEmpty || camera.zoom < kPoiMinZoom) {
      _debounce?.cancel();
      _requested = null;
      return const SizedBox.shrink();
    }
    final b = camera.visibleBounds;
    final cells = poiCellsCovering(b.south, b.west, b.north, b.east);
    final key = '${cells.join(';')}|${groups.map((g) => g.name).join(',')}';
    if (key != _requested) {
      _requested = key;
      _debounce?.cancel();
      _debounce = Timer(_delay, () {
        if (mounted) ref.read(poiControllerProvider.notifier).ensure(cells, groups);
      });
    }
    final pois = [
      for (final p in state.inCells(cells, groups))
        if (b.contains(p.position) && !hidden.contains(p.kind)) p,
    ];
    return MarkerLayer(
      markers: [
        for (final p in pois)
          Marker(
            key: ValueKey('poi-${p.id}'),
            point: p.position,
            width: PoiPin.width,
            height: PoiPin.height,
            // Die Spitze sitzt auf dem Ort, der Kopf darüber.
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => showPoiSheet(context, p),
              child: PoiPin(kind: p.kind),
            ),
          ),
      ],
    );
  }
}

/// Eine Stecknadel: ein auf dem Kopf stehender Tropfen in der Farbe der
/// Gruppe, darin das Symbol der Art (Kuchen, Bierkrug, Schlüssel …).
class PoiPin extends StatelessWidget {
  const PoiPin({super.key, required this.kind});

  final PoiKind kind;

  static const width = 30.0;
  static const height = 40.0;

  @override
  Widget build(BuildContext context) => Semantics(
        label: kind.label,
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _PinPainter(kind.group.color),
            child: Align(
              alignment: const Alignment(0, -0.45),
              child: PoiGlyph(kind: kind, size: 17, background: kind.group.color),
            ),
          ),
        ),
      );
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = w / 2 - 1.5;
    final c = Offset(w / 2, r + 1.5);
    // Kopf als Kreis, darunter zwei Bögen zur Spitze — der umgedrehte
    // Tropfen. Die Flanken treffen den Kreis tangential, daher die Kurven
    // statt gerader Linien.
    final path = Path()
      ..moveTo(w / 2, h - 1)
      ..quadraticBezierTo(c.dx - r * 0.35, c.dy + r * 1.25, c.dx - r, c.dy)
      ..arcToPoint(Offset(c.dx + r, c.dy),
          radius: Radius.circular(r), clockwise: true)
      ..quadraticBezierTo(c.dx + r * 0.35, c.dy + r * 1.25, w / 2, h - 1)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color;
}

/// Das Symbol einer Art, weiß auf [background]: ein Material-Symbol oder,
/// wo es keins gibt, gezeichnet (das Kuchenstück fürs Café).
class PoiGlyph extends StatelessWidget {
  const PoiGlyph(
      {super.key, required this.kind, required this.size, required this.background});

  final PoiKind kind;
  final double size;

  /// Die Farbe darunter — gezeichnete Symbole brauchen sie für ihre
  /// Binnenlinien (die Sahneschicht im Kuchen).
  final Color background;

  @override
  Widget build(BuildContext context) {
    final icon = kind.icon;
    if (icon != null) return Icon(icon, size: size, color: Colors.white);
    return CustomPaint(
      size: Size.square(size),
      painter: CakeSlicePainter(fill: Colors.white, cut: background),
    );
  }
}

/// Ein Stück Kuchen von der Seite: Keil mit Spitze links und Rand rechts,
/// eine Sahneschicht, oben eine Kirsche. Gezeichnet auf 24 × 24 wie die
/// Material-Symbole, damit es neben ihnen gleich groß wirkt.
class CakeSlicePainter extends CustomPainter {
  const CakeSlicePainter({required this.fill, required this.cut});

  final Color fill;
  final Color cut;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = fill;
    // Der Keil: oben schräg von der Spitze zum Rand, unten gerade.
    canvas.drawPath(
        Path()
          ..moveTo(1.8, 12.8)
          ..lineTo(21, 7.4)
          ..quadraticBezierTo(22.4, 7.4, 22.4, 8.8)
          ..lineTo(22.4, 21.5)
          ..lineTo(1.8, 21.5)
          ..close(),
        paint);
    // Die Sahneschicht als Fuge in der Farbe darunter.
    canvas.drawLine(
        const Offset(3.2, 16.6),
        const Offset(22.4, 16.6),
        Paint()
          ..color = cut
          ..strokeWidth = 1.6);
    // Kirsche mit Stiel.
    canvas.drawCircle(const Offset(14.6, 6.0), 2.5, paint);
    canvas.drawLine(
        const Offset(15.4, 3.7),
        const Offset(17.4, 1.2),
        Paint()
          ..color = fill
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(CakeSlicePainter old) => old.fill != fill || old.cut != cut;
}

/// Was man über einen Ort wissen will: Art, Name, Öffnungszeiten — und
/// der Weg zu allem Weiteren auf openstreetmap.org.
Future<void> showPoiSheet(BuildContext context, Poi poi) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        final water = switch ((poi.kind, poi.drinkable)) {
          (_, true) => 'Trinkwasser laut OpenStreetMap.',
          (_, false) => 'Laut OpenStreetMap kein Trinkwasser.',
          (PoiKind.spring || PoiKind.waterPoint, null) =>
            'Ob das Wasser trinkbar ist, steht nicht fest.',
          _ => null,
        };
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  PoiPin(kind: poi.kind),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(poi.name ?? poi.kind.label,
                        style: text.titleLarge),
                  ),
                ]),
                const SizedBox(height: 8),
                if (poi.name != null) Text(poi.kind.label, style: text.bodyMedium),
                if (poi.openingHours != null)
                  Text('Öffnungszeiten: ${poi.openingHours}',
                      style: text.bodyMedium),
                if (water != null) Text(water, style: text.bodyMedium),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Auf OpenStreetMap ansehen'),
                  onPressed: () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/${poi.id}'),
                      mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          ),
        );
      },
    );

/// Der Filter: vier Gruppen zum An- und Ausschalten, darunter je Gruppe
/// ihre Arten als Chips (Detailfilter). Er sagt dazu, ab wann Orte
/// erscheinen und wohin der Ausschnitt dafür geht.
Future<void> showPoiFilterSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Nicht bildschirmhoch: Oben bleibt Karte sichtbar (und zum
      // Schließen antippbar); was nicht passt, scrollt im Blatt.
      builder: (_) => const _PoiFilterSheet(),
    );

class _PoiFilterSheet extends ConsumerWidget {
  const _PoiFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(poiGroupsProvider);
    final hidden = ref.watch(poiHiddenKindsProvider);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Orte auf der Karte', style: text.titleLarge),
            ),
            for (final g in PoiGroup.values) ...[
              SwitchListTile(
                key: ValueKey('poi-group-${g.name}'),
                secondary: CircleAvatar(
                  backgroundColor: g.color,
                  child: PoiGlyph(
                      kind: PoiKind.values.firstWhere((k) => k.group == g),
                      size: 20,
                      background: g.color),
                ),
                title: Text(g.label),
                subtitle: Text(g.examples),
                value: groups.contains(g),
                onChanged: (_) => ref.read(poiGroupsProvider.notifier).toggle(g),
              ),
              // Die Arten nur unter eingeschalteten Gruppen — unter einer
              // ausgeschalteten wären es Schalter ohne Wirkung.
              if (groups.contains(g))
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final k in PoiKind.values)
                        if (k.group == g)
                          FilterChip(
                            key: ValueKey('poi-kind-${k.name}'),
                            // Abgewählt: grau, damit man es ohne Hinsehen
                            // auf den Chip-Hintergrund erkennt.
                            avatar: CircleAvatar(
                              backgroundColor:
                                  hidden.contains(k) ? Colors.grey : g.color,
                              child: PoiGlyph(
                                  kind: k,
                                  size: 14,
                                  background:
                                      hidden.contains(k) ? Colors.grey : g.color),
                            ),
                            label: Text(k.label),
                            selected: !hidden.contains(k),
                            showCheckmark: false,
                            onSelected: (_) =>
                                ref.read(poiHiddenKindsProvider.notifier).toggle(k),
                          ),
                    ],
                  ),
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Orte erscheinen ab Zoomstufe ${kPoiMinZoom.round()}. Sie kommen '
                'aus OpenStreetMap: Dafür geht der sichtbare Kartenausschnitt '
                'an overpass-api.de — keine Trails, keine Fahrten, kein Konto.',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
