import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../friends/friends_backend.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../account/avatar.dart' show PersonAvatar;
import '../island/island_controller.dart';
import '../island/island_host.dart';

/// What to say when a friends change failed.
String friendActionError(FriendsException e) => switch (e.error) {
  FriendsError.offline => "You're offline",
  _ => "Couldn't update that friend",
};

/// Runs a friends change; a failure goes on an island. Returns whether it
/// worked.
Future<bool> runFriendAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final islands = Islands.of(context);
  try {
    await action();
    return true;
  } on FriendsException catch (e) {
    islands.show(friendActionError(e), kind: IslandKind.failure);
    return false;
  }
}

/// A Songies user: picture, name, and what can be done with them now (Add
/// friend, Requested to cancel, Accept, or Friends).
class UserRow extends ConsumerStatefulWidget {
  const UserRow({required this.user, this.onTap, super.key});

  final FriendUser user;

  /// Opens the person (on a friends list).
  final VoidCallback? onTap;

  @override
  ConsumerState<UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<UserRow> {
  bool _busy = false;

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _busy = true);
    await runFriendAction(context, action);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final user = widget.user;
    final service = ref.read(friendsServiceProvider);
    final link = ref.watch(
      friendsStateProvider.select((s) => s.value?.linkOf(user.id)),
    );
    final (label, onPressed) = switch (link) {
      null => ('Add friend', () => _act(() => service.send(user.id))),
      FriendLink.outgoing => (
        'Requested',
        () => _act(() => service.remove(user.id)),
      ),
      FriendLink.incoming => (
        'Accept',
        () => _act(() => service.accept(user.id)),
      ),
      FriendLink.friend => ('Friends', null),
    };
    final button = link == null || link == FriendLink.incoming
        ? FilledButton(
            key: Key('friends.action.${user.id}'),
            onPressed: _busy ? null : onPressed,
            child: Text(label),
          )
        : OutlinedButton(
            key: Key('friends.action.${user.id}'),
            onPressed: _busy ? null : onPressed,
            child: Text(label),
          );
    return InkWell(
      key: Key('friends.user.${user.id}'),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            PersonAvatar(name: user.username, url: user.avatarUrl, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                user.username,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            button,
          ],
        ),
      ),
    );
  }
}
