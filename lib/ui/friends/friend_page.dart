import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../friends/friends_backend.dart';
import '../../friends/friends_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../account/avatar.dart' show PersonAvatar;
import 'page_bar.dart';
import 'user_row.dart';

/// One friend: their picture and name, and Remove friend (which asks
/// first). Their listening comes here later (SON-35).
class FriendPage extends ConsumerStatefulWidget {
  const FriendPage({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends ConsumerState<FriendPage> {
  bool _busy = false;

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
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(friendsStateProvider).value ?? FriendsState.empty;
    FriendUser? user;
    for (final u in state.friends) {
      if (u.id == widget.userId) user = u;
    }
    final found = user;
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            children: [
              const PageBar('Friend'),
              if (found == null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    state.loaded ? 'Not in your friends' : '',
                    style: TextStyle(color: colors.mutedText),
                  ),
                )
              else ...[
                const SizedBox(height: 16),
                Center(
                  child: PersonAvatar(
                    name: found.username,
                    url: found.avatarUrl,
                    size: 120,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    found.username,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: OutlinedButton.icon(
                    key: const Key('friend.remove'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _busy ? null : () => _remove(found),
                    icon: const Icon(Icons.person_remove_outlined),
                    label: const Text('Remove friend'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
