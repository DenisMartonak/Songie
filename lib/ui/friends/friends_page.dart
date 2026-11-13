import 'dart:async';

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

/// Your friends: requests waiting for you (Accept / Decline), the ones you
/// sent (Cancel), then your friends (tap to open). Loads again when opened.
class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({super.key});

  static const double _maxContentWidth = 720;

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(friendsServiceProvider).refresh().catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(friendsStateProvider).value ?? FriendsState.empty;
    final service = ref.read(friendsServiceProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final nothing =
        state.friends.isEmpty &&
        state.incoming.isEmpty &&
        state.outgoing.isEmpty;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: FriendsPage._maxContentWidth,
          ),
          child: ListView(
            padding: EdgeInsets.only(bottom: bottom + 24),
            children: [
              const PageBar('Friends'),
              if (state.incoming.isNotEmpty) ...[
                const _Section('Requests'),
                for (final u in state.incoming)
                  _PersonRow(
                    key: Key('friends.incoming.${u.id}'),
                    user: u,
                    actions: [
                      _Action(
                        key: Key('friends.accept.${u.id}'),
                        label: 'Accept',
                        filled: true,
                        onPressed: () => service.accept(u.id),
                      ),
                      _Action(
                        key: Key('friends.decline.${u.id}'),
                        label: 'Decline',
                        onPressed: () => service.remove(u.id),
                      ),
                    ],
                  ),
              ],
              if (state.outgoing.isNotEmpty) ...[
                const _Section('Sent'),
                for (final u in state.outgoing)
                  _PersonRow(
                    key: Key('friends.outgoing.${u.id}'),
                    user: u,
                    actions: [
                      _Action(
                        key: Key('friends.cancel.${u.id}'),
                        label: 'Cancel',
                        onPressed: () => service.remove(u.id),
                      ),
                    ],
                  ),
              ],
              if (state.friends.isNotEmpty) ...[
                const _Section('Friends'),
                for (final u in state.friends)
                  _PersonRow(
                    key: Key('friends.friend.${u.id}'),
                    user: u,
                    onTap: () => context.push('/profile/friends/${u.id}'),
                  ),
              ],
              if (nothing && state.loaded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Text(
                    'No friends yet. Find people in Search under Songies '
                    'Users.',
                    key: const Key('friends.empty'),
                    style: TextStyle(color: colors.mutedText),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: colors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A button whose change runs once at a time; a failure goes on an island.
class _Action extends StatefulWidget {
  const _Action({
    required this.label,
    required this.onPressed,
    this.filled = false,
    super.key,
  });

  final String label;
  final Future<void> Function() onPressed;
  final bool filled;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    await runFriendAction(context, widget.onPressed);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final child = Text(widget.label);
    final onPressed = _busy ? null : _run;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: widget.filled
          ? FilledButton(onPressed: onPressed, child: child)
          : OutlinedButton(onPressed: onPressed, child: child),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.user,
    this.actions = const [],
    this.onTap,
    super.key,
  });

  final FriendUser user;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return InkWell(
      onTap: onTap,
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
            ...actions,
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: colors.mutedText),
          ],
        ),
      ),
    );
  }
}
