import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/read_after_write.dart';
import '../../data/providers.dart';
import '../../models/profile.dart';

class MyProfileNotifier extends AsyncNotifier<Profile?>
    with ReadAfterWrite<Profile?> {
  @override
  Future<Profile?> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value(null);
    return ref.read(profileRepositoryProvider).fetchMyProfile();
  }

  Future<void> updateAvatar(int avatar) async {
    await ref.read(profileRepositoryProvider).updateAvatar(avatar);
    await reloadAfterWrite('Profil neu laden');
  }

  Future<void> updateUsername(String username) async {
    await ref.read(profileRepositoryProvider).updateUsername(username);
    await reloadAfterWrite('Profil neu laden');
  }
}

final myProfileProvider =
    AsyncNotifierProvider<MyProfileNotifier, Profile?>(MyProfileNotifier.new);
