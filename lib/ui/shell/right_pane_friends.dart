import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_service.dart';
import '../../friends/friends_backend.dart' hide FriendRow;
import '../../friends/friends_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../friends/friend_row.dart';
import '../room/join_room_dialog.dart' show joinRoomAsking;
import '../room/room_panel.dart';

/// The Friends view of the desktop right pane: the room panel, then your
/// friends with what they play now and a Join button for those hosting.
class RightPaneFriends extends ConsumerStatefulWidget {
  const RightPaneFriends({super.key});

  @override
  ConsumerState<RightPaneFriends> createState() => _RightPaneFriendsState();
}

class _RightPaneFriendsState extends ConsumerState<RightPaneFriends> {
  late final FriendsService _service;

  /// The close-watch lease, held while signed in.
  Object? _watch;

  @override
  void initState() {
    super.initState();
    _service = ref.read(friendsServiceProvider);
    _follow(ref.read(accountStateProvider).value is SignedIn);
  }

  @override
  void dispose() {
    _follow(false);
    super.dispose();
  }

  void _follow(bool signedIn) {
    if (signedIn) {
      _watch ??= _service.watchClosely();
    } else if (_watch case final lease?) {
      _service.stopWatching(lease);
      _watch = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      accountStateProvider,
      (_, next) => _follow(next.value is SignedIn),
    );
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final signedIn = ref.watch(accountStateProvider).value is SignedIn;
    final state = ref.watch(friendsStateProvider).value ?? FriendsState.empty;
    final now = ref.read(nowProvider)();
    final showFriends = signedIn && state.loaded;

    return ListView(
      key: const Key('rightPane.friends'),
      children: [
        const RoomPanel(embedded: true),
        if (signedIn) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Friends',
              style: TextStyle(
                color: colors.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (showFriends) ...[
            for (final u in state.friends) _friend(context, state, u, now),
            if (state.incoming.isNotEmpty)
              _Link(
                key: const Key('rightPane.requests'),
                label: state.incoming.length == 1
                    ? '1 request'
                    : '${state.incoming.length} requests',
              ),
            if (state.friends.isEmpty)
              const _Link(
                key: Key('rightPane.findFriends'),
                label: 'Find friends',
              ),
          ],
        ],
      ],
    );
  }

  Widget _friend(
    BuildContext context,
    FriendsState state,
    FriendUser u,
    DateTime now,
  ) {
    final listening = state.listening(u.id, now);
    final activity = state.activity[u.id];
    final code = listening ? activity?.roomCode : null;
    return FriendRow(
      key: Key('rightPane.friend.${u.id}'),
      user: u,
      avatarSize: 36,
      chevron: false,
      listening: listening ? activity!.nowPlaying : null,
      actions: [
        if (code != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: OutlinedButton(
              key: Key('rightPane.join.${u.id}'),
              onPressed: () => joinRoomAsking(
                context,
                ProviderScope.containerOf(context),
                code,
              ),
              child: const Text('Join'),
            ),
          ),
      ],
      onTap: () => context.push('/profile/friends/${u.id}'),
    );
  }
}

/// A text link that opens the Friends page.
class _Link extends StatelessWidget {
  const _Link({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return InkWell(
      onTap: () => context.push('/profile/friends'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(label, style: TextStyle(color: colors.accent)),
      ),
    );
  }
}
