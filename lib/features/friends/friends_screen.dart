import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_colors.dart';
import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../core/widgets/letter_avatar.dart';
import '../../data/providers.dart';
import '../../models/friendship.dart';
import '../profile/profile_providers.dart';
import 'buddy_alias.dart';
import 'buddy_alias_dialog.dart';
import 'friend_providers.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _searchController = TextEditingController();
  List<ProfileSearchResult> _results = [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await ref.read(friendRepositoryProvider).search(query);
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (e, stackTrace) {
      logError('Buddy-Suche', e, stackTrace);
      _showMessage(friendlyError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Einladung teilen; wo das System-Teilen nicht verfügbar ist
  /// (z. B. Desktop-Browser), landet der Text in der Zwischenablage.
  Future<void> _invite() async {
    final username = ref.read(myProfileProvider).valueOrNull?.username;
    final text = AppInfo.inviteText(username);
    try {
      final result = await SharePlus.instance.share(ShareParams(text: text));
      if (result.status == ShareResultStatus.unavailable) {
        throw StateError('share unavailable');
      }
    } catch (_) {
      // Kein Fehlerfall: Desktop-Browser haben kein System-Teilen.
      await Clipboard.setData(ClipboardData(text: text));
      _showMessage('Einladungstext in die Zwischenablage kopiert.');
    }
  }

  /// Annehmen — und danach sagen, was sich auf der Karte tut (Konzept 6):
  /// „14 Trails gemeinsam, 8 neu von Jan, 5 neu für Jan". Erst nach dem
  /// Annehmen, nie davor. Kommen die Zahlen nicht (Neuladen gescheitert),
  /// bleibt es beim Annehmen; die Liste zeigt den Buddy ohnehin.
  Future<void> _accept(FriendshipEntry f) async {
    final messenger = ScaffoldMessenger.of(context);
    final uid = ref.read(currentUserIdProvider) ?? '';
    final name = f.otherUsername(uid);
    final summary = await ref.read(friendshipsProvider.notifier).accept(f.id);
    if (!mounted || summary == null) return;
    messenger.showSnackBar(SnackBar(
      key: const ValueKey('connect-summary'),
      content: Text(summary.sentence(name)),
      duration: const Duration(seconds: 8),
    ));
  }

  Future<void> _sendRequest(ProfileSearchResult result) async {
    try {
      await ref.read(friendshipsProvider.notifier).sendRequest(result.id);
      _showMessage('Anfrage an ${result.username} gesendet.');
      setState(
          () => _results = _results.where((r) => r.id != result.id).toList());
    } catch (e, stackTrace) {
      logError('Freundschaftsanfrage', e, stackTrace);
      // Unique-Verletzung = Paar existiert schon — die häufigste Ursache.
      _showMessage(
          'Anfrage nicht möglich – vielleicht seid ihr schon verbunden?');
    }
  }

  Future<void> _confirmRemove(FriendshipEntry f, String shownName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$shownName als Buddy entfernen?'),
        content: const Text(
            'Ihr seht danach gegenseitig keine geteilten Trails mehr.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Entfernen')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(friendshipsProvider.notifier).remove(f.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserIdProvider) ?? '';
    final friendshipsAsync = ref.watch(friendshipsProvider);
    final friendships = friendshipsAsync.valueOrNull ?? [];

    final incoming = friendships.where((f) => f.isIncomingFor(uid)).toList();
    final outgoing = friendships.where((f) => f.isOutgoingFor(uid)).toList();
    final accepted = friendships.where((f) => f.isAccepted).toList();
    final names = ref.watch(buddyNamesViewProvider);

    final requestedIds = {
      for (final f in friendships) ...[f.requesterId, f.addresseeId]
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Buddys')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(friendshipsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: _invite,
              icon: const Icon(Icons.share),
              label: const Text('Buddys zu TrailBuddy einladen'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Buddy finden',
                hintText: 'Benutzername oder genaue E-Mail',
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        onPressed: _search, icon: const Icon(Icons.search)),
              ),
            ),
            if (_searched) ...[
              const SizedBox(height: 8),
              if (_results.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Niemanden gefunden.'),
                )
              else
                for (final result in _results)
                  ListTile(
                    leading: LetterAvatar(name: result.username),
                    title: Text(result.username),
                    subtitle: result.displayName != null
                        ? Text(result.displayName!)
                        : null,
                    trailing: requestedIds.contains(result.id)
                        ? const Text('Verbunden')
                        : FilledButton.tonal(
                            onPressed: () => _sendRequest(result),
                            child: const Text('Anfragen'),
                          ),
                  ),
            ],
            if (incoming.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Anfragen an dich',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final f in incoming)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: LetterAvatar(name: f.otherUsername(uid)),
                  title: Text(f.otherUsername(uid)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _accept(f),
                        icon: const Icon(Icons.check_circle,
                            color: AppColors.trailGreen),
                        tooltip: 'Annehmen',
                      ),
                      IconButton(
                        onPressed: () =>
                            ref.read(friendshipsProvider.notifier).remove(f.id),
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Ablehnen',
                      ),
                    ],
                  ),
                ),
            ],
            if (outgoing.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Gesendete Anfragen',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final f in outgoing)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: LetterAvatar(name: f.otherUsername(uid)),
                  title: Text(f.otherUsername(uid)),
                  subtitle: const Text('Ausstehend'),
                  trailing: IconButton(
                    onPressed: () =>
                        ref.read(friendshipsProvider.notifier).remove(f.id),
                    icon: const Icon(Icons.cancel_outlined),
                    tooltip: 'Zurückziehen',
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text('Meine Buddys',
                style: Theme.of(context).textTheme.titleMedium),
            if (friendshipsAsync.isLoading && friendships.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (accepted.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Noch keine Buddys verbunden. Suche oben nach '
                    'Benutzername oder E-Mail!'),
              )
            else
              for (final f in accepted)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: LetterAvatar(name: f.otherUsername(uid)),
                  // Mit Alias steht er oben und der Name darunter — genau
                  // dafür ist er da: wissen, wer „klabuster 2" eigentlich
                  // ist.
                  title: Text(names.of(f.otherId(uid), f.otherUsername(uid))),
                  subtitle: names.aliasOf(f.otherId(uid)) == null
                      ? null
                      : Text(f.otherUsername(uid)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AliasButton(
                          friendId: f.otherId(uid),
                          username: f.otherUsername(uid)),
                      IconButton(
                        onPressed: () => _confirmRemove(
                            f, names.of(f.otherId(uid), f.otherUsername(uid))),
                        icon: const Icon(Icons.person_remove_outlined),
                        tooltip: 'Buddy entfernen',
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
