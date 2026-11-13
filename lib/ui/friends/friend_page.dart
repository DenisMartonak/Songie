import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../friends/activity_backend.dart';
import '../../friends/friends_backend.dart';
import '../../friends/friends_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../account/avatar.dart' show PersonAvatar;
import 'page_bar.dart';
import '../room/join_room_dialog.dart' show joinRoomAsking;
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

  /// Keeps their listening fresh while the page is open.
  late final FriendsService _service;
  late final Object _watch;

  @override
  void initState() {
    super.initState();
    _service = ref.read(friendsServiceProvider);
    _watch = _service.watchClosely();
    unawaited(_service.refresh().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _service.stopWatching(_watch);
    super.dispose();
  }

  Future<void> _join(String code) async {
    final container = ProviderScope.containerOf(context);
    await joinRoomAsking(context, container, code);
  }

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
                const SizedBox(height: 20),
                _NowPlayingCard(
                  song: state.listening(found.id, ref.read(nowProvider)())
                      ? state.activity[found.id]!.nowPlaying
                      : null,
                  roomCode: state.listening(found.id, ref.read(nowProvider)())
                      ? state.activity[found.id]!.roomCode
                      : null,
                  onJoin: _join,
                ),
                if (state.activity[found.id]?.top case final top?
                    when !top.isEmpty) ...[
                  if (top.artists.isNotEmpty) ...[
                    const _Heading('Top artists'),
                    for (final (i, name) in top.artists.indexed)
                      _Ranked(rank: i + 1, title: name),
                  ],
                  if (top.songs.isNotEmpty) ...[
                    const _Heading('Top songs'),
                    for (final (i, song) in top.songs.indexed)
                      _Ranked(
                        rank: i + 1,
                        title: song.title,
                        subtitle: song.artist,
                      ),
                  ],
                ],
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

/// What they play now, with Join while they host a room; or that they are
/// not listening (or don't share it).
class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.song,
    required this.roomCode,
    required this.onJoin,
  });

  final NowPlaying? song;
  final String? roomCode;
  final void Function(String code) onJoin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final s = song;
    if (s == null) {
      return Padding(
        key: const Key('friend.notListening'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Not listening right now',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.mutedText),
        ),
      );
    }
    final cover = s.coverUrl;
    final code = roomCode;
    return Card(
      key: const Key('friend.nowPlaying'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(colors.radius),
              child: SizedBox.square(
                dimension: 56,
                child: cover == null
                    ? ColoredBox(
                        color: colors.surface,
                        child: Icon(
                          Icons.music_note_rounded,
                          color: colors.mutedText,
                        ),
                      )
                    : Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: colors.surface,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: colors.mutedText,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    s.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.mutedText, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (code != null)
              FilledButton.icon(
                key: const Key('friend.join'),
                onPressed: () => onJoin(code),
                icon: const Icon(Icons.headphones_rounded),
                label: const Text('Join'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          color: colors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Ranked extends StatelessWidget {
  const _Ranked({required this.rank, required this.title, this.subtitle});

  final int rank;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                color: colors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.text, fontSize: 15),
                ),
                if (sub != null)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
