import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../friends/friends_backend.dart';
import '../../friends/friends_service.dart';
import '../../providers.dart';
import '../profile/profile_view.dart';
import 'user_row.dart';

/// One friend's profile ([ProfileView]), with a ⋯ menu holding Remove
/// friend (which asks first, then goes back).
class FriendPage extends ConsumerStatefulWidget {
  const FriendPage({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends ConsumerState<FriendPage> {
  bool _busy = false;

  /// The friend last found, kept while the page pops after Remove friend.
  FriendUser? _user;

  Future<void> _remove(FriendUser user) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${user.username} from your friends?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    final service = ref.read(friendsServiceProvider);
    final router = GoRouter.of(context);
    final done = await runFriendAction(context, () => service.remove(user.id));
    if (!mounted) return;
    setState(() => _busy = false);
    if (done && router.canPop()) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendsStateProvider).value ?? FriendsState.empty;
    for (final u in state.friends) {
      if (u.id == widget.userId) _user = u;
    }
    final user = _user;
    final error = Theme.of(context).colorScheme.error;
    return SafeArea(
      bottom: false,
      child: ProfileView(
        source: FriendProfile(widget.userId),
        actions: const [],
        menu: user == null
            ? null
            : PopupMenuButton<bool>(
                key: const Key('profile.menu'),
                tooltip: 'More',
                enabled: !_busy,
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (_) => _remove(user),
                itemBuilder: (_) => [
                  PopupMenuItem<bool>(
                    key: const Key('friend.remove'),
                    value: true,
                    child: ListTile(
                      iconColor: error,
                      textColor: error,
                      leading: const Icon(Icons.person_remove_outlined),
                      title: const Text('Remove friend'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
