import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../friends/friends_backend.dart' show FriendsException;
import '../../playlists/sharing_backend.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../friends/user_row.dart' show friendActionError;
import '../island/island_controller.dart';
import '../island/island_host.dart';

/// What a shared playlist link [code] opens: the playlist's name, its owner
/// and first songs, with Follow and Make a copy. A link to the user's own
/// share opens that playlist; a stopped one says so.
Future<void> showSharedPlaylistSheet(BuildContext context, String code) async {
  final container = ProviderScope.containerOf(context);
  final islands = Islands.of(context);
  final router = GoRouter.of(context);
  final SharedPlaylist? shared;
  try {
    shared = await container.read(playlistSharingProvider).preview(code);
  } on FriendsException catch (e) {
    islands.show(friendActionError(e), kind: IslandKind.failure);
    return;
  }
  if (shared == null) {
    islands.show("This playlist isn't shared any more", kind: IslandKind.info);
    return;
  }
  if (shared.isMine) {
    final own = await container
        .read(libraryRepositoryProvider)
        .playlistBySharedCode(code);
    if (own != null) router.go('/library/playlist/${own.id}');
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _SharedDialog(code: code, shared: shared!),
  );
}

class _SharedDialog extends ConsumerStatefulWidget {
  const _SharedDialog({required this.code, required this.shared});

  final String code;
  final SharedPlaylist shared;

  @override
  ConsumerState<_SharedDialog> createState() => _SharedDialogState();
}

class _SharedDialogState extends ConsumerState<_SharedDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<String?> Function() action, String done) async {
    final islands = Islands.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await action();
      navigator.pop();
      if (id != null) {
        islands.show(done, kind: IslandKind.success);
        router.go('/library/playlist/$id');
      } else {
        islands.show(
          "This playlist isn't shared any more",
          kind: IslandKind.info,
        );
      }
    } on FriendsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendActionError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final s = widget.shared;
    final sharing = ref.read(playlistSharingProvider);
    final error = _error;
    return AlertDialog(
      title: Text(s.name),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shared by ${s.ownerName} · ${s.songs.length} '
              '${s.songs.length == 1 ? 'song' : 'songs'}',
              style: TextStyle(color: colors.mutedText),
            ),
            const SizedBox(height: 12),
            for (final song in s.songs.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${song.title} · ${song.artist}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.text),
                ),
              ),
            if (s.songs.length > 5)
              Text(
                'and ${s.songs.length - 5} more',
                style: TextStyle(color: colors.mutedText, fontSize: 12),
              ),
            const SizedBox(height: 12),
            Text(
              'Following keeps it up to date with theirs; a copy is yours to '
              'change.',
              style: TextStyle(color: colors.mutedText, fontSize: 12),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          key: const Key('invite.copy'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => sharing.copy(code: widget.code),
                  'Copied to your library',
                ),
          child: const Text('Make a copy'),
        ),
        FilledButton(
          key: const Key('invite.follow'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => sharing.follow(widget.code),
                  'Following ${s.name}',
                ),
          child: const Text('Follow'),
        ),
      ],
    );
  }
}
