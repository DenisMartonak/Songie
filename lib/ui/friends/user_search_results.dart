import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../friends/friends_backend.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'user_row.dart';

/// Songies users whose name starts with a query (2 letters or more).
final userSearchProvider = FutureProvider.autoDispose
    .family<List<FriendUser>, String>(
      (ref, query) => ref.watch(friendsServiceProvider).search(query),
    );

/// The Songies Users tab: people found for [query], each with what can be
/// done with them; or why there are none.
class UserSearchResults extends ConsumerWidget {
  const UserSearchResults({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    Widget message(String text, String key) => Padding(
      key: Key(key),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.mutedText),
      ),
    );
    if (ref.watch(accountStateProvider).value is! SignedIn) {
      return message('Log in to find friends', 'users.signedOut');
    }
    final q = query.trim();
    if (q.length < 2) return message('Type at least 2 letters', 'users.short');
    final found = ref.watch(userSearchProvider(q));
    return found.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => message(
        e is FriendsException
            ? friendActionError(e)
            : "Couldn't search Songies users",
        'users.problem',
      ),
      data: (users) => users.isEmpty
          ? message('No Songies users found', 'users.none')
          : Column(
              children: [
                for (final u in users) UserRow(user: u, key: ValueKey(u.id)),
              ],
            ),
    );
  }
}
