import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../models/trail.dart';
import '../map/map_screen.dart' show formatCachedAt;
import 'trail_filter_chips.dart';
import 'trail_list.dart';
import 'trail_providers.dart';
import 'trail_sheet.dart';

/// Die Karte als Liste: erst die eigenen Trails, dann die, die nur Buddys
/// belegt haben. Antippen öffnet das Blatt; von dort geht es auf die Karte.
/// Darüber Suche, Filter und Sortierung (#66, `trail_list.dart`).
class TrailsScreen extends ConsumerStatefulWidget {
  const TrailsScreen({super.key});

  @override
  ConsumerState<TrailsScreen> createState() => _TrailsScreenState();
}

class _TrailsScreenState extends ConsumerState<TrailsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trailsAsync = ref.watch(trailsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trails'),
        actions: [
          IconButton(
            tooltip: 'GPX importieren',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => context.push('/profile/import'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(trailsProvider.future),
        child: trailsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(friendlyError(e)),
            ),
          ]),
          data: (trails) {
            if (trails.isEmpty) {
              return ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Noch keine Trails. Importiere deine GPX-Dateien (Symbol '
                    'oben rechts) oder verbinde dich mit Buddys.',
                  ),
                ),
              ]);
            }
            final seen = ref.watch(seenNotesProvider);
            final cachedAt = ref.watch(trailsCachedAtProvider);
            final sort = ref.watch(trailSortProvider);
            final filter = ref.watch(trailListFilterProvider);
            final query = _search.text;
            final result = trailListOf(trails,
                query: query, filter: filter, sort: sort, seenNotes: seen);
            final shown = result.trails;
            final pending = shown.where((t) => t.pending).toList();
            final own = shown.where((t) => t.isOwn && !t.pending).toList();
            final buddies = shown.where((t) => !t.isOwn).toList();
            // Der Dreier-Schalter nur, wenn es beides gibt — sonst hätte
            // eine Hälfte immer „keine Trails".
            final mixed = trails.any((t) => t.isOwn) && trails.any((t) => !t.isOwn);
            final searching = query.trim().isNotEmpty || filter.isActive;
            return ListView(
              children: [
                _Controls(
                  search: _search,
                  onSearch: () => setState(() {}),
                  filter: filter,
                  showOwner: mixed,
                  sort: sort,
                ),
                if (searching)
                  _Summary(
                    count: shown.length,
                    isGuess: result.isGuess,
                    hiddenUngraded: result.hiddenUngraded,
                  ),
                if (cachedAt != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'Kein Empfang — Stand vom ${formatCachedAt(cachedAt)}. '
                      'Neue Beiträge deiner Buddys kommen mit dem nächsten Netz.',
                      key: const ValueKey('cached-notice-list'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                // Der Ausgangskorb (#30) zuerst: Was wartet, soll man
                // sehen — sonst steuert man dieselbe Datei zweimal bei.
                if (pending.isNotEmpty) _Header('Wartet auf Übertragung (${pending.length})'),
                for (final t in pending) _TrailTile(t, fresh: false),
                if (own.isNotEmpty) _Header('Meine Trails (${own.length})'),
                for (final t in own) _TrailTile(t, fresh: t.hasFreshNote(seen: seen)),
                if (buddies.isNotEmpty) _Header('Von Buddys (${buddies.length})'),
                for (final t in buddies) _TrailTile(t, fresh: t.hasFreshNote(seen: seen)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Suchfeld, Filter und Sortierung über der Liste.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.search,
    required this.onSearch,
    required this.filter,
    required this.showOwner,
    required this.sort,
  });

  final TextEditingController search;
  final VoidCallback onSearch;
  final TrailListFilter filter;
  final bool showOwner;
  final TrailSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Die Sortierung neben der Suche, nicht bei den Chips: Dort
          // schnitt sie auf 360 dp den dritten Chip ab.
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('trail-search'),
                  controller: search,
                  onChanged: (_) => onSearch(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Trail oder Buddy',
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Suche leeren',
                            onPressed: () {
                              search.clear();
                              onSearch();
                            },
                          ),
                  ),
                ),
              ),
              PopupMenuButton<TrailSort>(
                key: const ValueKey('trail-sort'),
                tooltip: 'Sortieren: ${sort.label}',
                icon: const Icon(Icons.sort),
                initialValue: sort,
                onSelected: (v) => ref.read(trailSortProvider.notifier).state = v,
                itemBuilder: (_) => [
                  for (final v in TrailSort.values)
                    CheckedPopupMenuItem(
                      key: ValueKey('trail-sort-${v.name}'),
                      value: v,
                      checked: v == sort,
                      child: Text(v.label),
                    ),
                ],
              ),
            ],
          ),
          TrailFilterChips(showOwner: showOwner),
        ],
      ),
    );
  }
}

/// Was die Suche gefunden hat — und ob geraten wurde.
class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.isGuess, required this.hiddenUngraded});

  final int count;
  final bool isGuess;
  final int hiddenUngraded;

  @override
  Widget build(BuildContext context) {
    final text = count == 0
        ? 'Keine Trails für diese Suche.'
        : isGuess
            ? 'Kein Trail heißt so. Meintest du …?'
            : count == 1
                ? 'Ein Trail gefunden.'
                : '$count Trails gefunden.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: text),
          if (hiddenUngraded > 0)
            TextSpan(
              text: hiddenUngraded == 1
                  ? ' Ein Trail ohne Einschätzung ist nicht dabei.'
                  : ' $hiddenUngraded Trails ohne Einschätzung sind nicht dabei.',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
        ]),
        key: const ValueKey('trail-search-summary'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _TrailTile extends StatelessWidget {
  const _TrailTile(this.trail, {required this.fresh});
  final Trail trail;

  /// Neuer, noch nicht gesehener Hinweis eines Buddys (#7).
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      formatLength(trail.lengthM),
      if (trail.elevation != null) '↓ ${trail.elevation!.lossM.round()} Hm',
      if (trail.grade != null) gradeLabel(trail.grade!),
      if (trail.buddyIds.isNotEmpty)
        '${trail.buddyIds.length} ${trail.buddyIds.length == 1 ? 'Buddy' : 'Buddys'}',
    ];
    // Neuer Hinweis eines Buddys (#7): die Zeile getönt, ein Symbol am
    // Ende und das Wort dazu — Farbe allein wäre nicht für alle lesbar.
    final failure = trail.pendingFailure;
    return ListTile(
      tileColor: fresh ? AppPalette.of(context).map.note.withValues(alpha: 0.18) : null,
      trailing: fresh
          ? const Icon(Icons.mark_chat_unread_outlined,
              semanticLabel: 'neuer Hinweis')
          : null,
      // Wartend (#30): Uhr statt Route, verblasst — derselbe Spot, nur
      // noch nicht auf dem Server.
      leading: Icon(
        trail.pending
            ? (failure == null ? Icons.schedule : Icons.error_outline)
            : trail.status.warns
                ? Icons.warning_amber
                : Icons.route,
        color: trail.pending
            ? (failure == null
                ? AppPalette.of(context).map.mine.withValues(alpha: 0.55)
                : Theme.of(context).colorScheme.error)
            : trail.status.warns
                ? AppPalette.of(context).map.warning
                : (trail.isOwn
                    ? AppPalette.of(context).map.mine
                    : AppPalette.of(context).map.buddy),
      ),
      title: Text(trail.displayName),
      subtitle: Text([
        parts.join(' · '),
        if (trail.pending) failure ?? 'wartet auf Übertragung',
        if (trail.pendingDetails) 'Beitrag wartet auf Übertragung',
        if (trail.status.warns) trail.status.label,
        if (fresh) 'neuer Hinweis',
      ].join(' — ')),
      onTap: () => showTrailSheet(context, trail, showOnMapButton: true),
    );
  }
}
