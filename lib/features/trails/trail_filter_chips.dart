// Die Filter-Chips für Trails (#66) — EIN Widget für die Liste und das
// Blatt „Ebenen" der Karte, weil beide denselben Filter setzen
// (`trailListFilterProvider`). Zwei Fassungen wären zwei Meinungen
// darüber, was „bis S2" heißt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/trail.dart';
import 'trail_list.dart';
import 'trail_providers.dart';

class TrailFilterChips extends ConsumerWidget {
  const TrailFilterChips({super.key, required this.showOwner, this.keyPrefix = 'trail'});

  /// „Alle / Meine / Von Buddys" nur, wenn es beides gibt — sonst hätte
  /// eine Hälfte immer „keine Trails".
  final bool showOwner;

  /// Liste und Blatt können zugleich im Baum stehen (der Reiter bleibt
  /// eingehängt); getrennte Schlüssel halten sie auseinander.
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(trailListFilterProvider);
    void set(TrailListFilter f) => ref.read(trailListFilterProvider.notifier).state = f;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showOwner) ...[
          const SizedBox(height: 8),
          SegmentedButton<TrailOwnerFilter>(
            key: ValueKey('$keyPrefix-owner'),
            showSelectedIcon: false,
            segments: [
              for (final v in TrailOwnerFilter.values) ButtonSegment(value: v, label: Text(v.label)),
            ],
            selected: {filter.owner},
            onSelectionChanged: (s) => set(filter.copyWith(owner: s.first)),
          ),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              key: ValueKey('$keyPrefix-filter-easy'),
              label: Text('bis ${gradeLabel(kEasyMaxGrade)}'),
              selected: filter.easyOnly,
              onSelected: (v) => set(filter.copyWith(easyOnly: v)),
            ),
            FilterChip(
              key: ValueKey('$keyPrefix-filter-fresh'),
              label: const Text('Neuer Hinweis'),
              selected: filter.freshNotesOnly,
              onSelected: (v) => set(filter.copyWith(freshNotesOnly: v)),
            ),
            FilterChip(
              key: ValueKey('$keyPrefix-filter-reported'),
              label: const Text('Gemeldet'),
              selected: filter.reportedOnly,
              onSelected: (v) => set(filter.copyWith(reportedOnly: v)),
            ),
          ],
        ),
      ],
    );
  }
}
