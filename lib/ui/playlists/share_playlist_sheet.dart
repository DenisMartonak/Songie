import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../friends/friends_backend.dart' show FriendsException;
import '../../playlists/playlist_links.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../friends/user_row.dart' show friendActionError;
import '../island/island_controller.dart';
import '../island/island_host.dart';

/// Shares playlist [playlistId] (or shows its link when already shared):
/// Copy link, and Stop sharing.
Future<void> showSharePlaylistSheet(BuildContext context, String playlistId) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ShareDialog(playlistId: playlistId),
    );

/// "3 songs from your files aren't shared" (they can't be).
String localSongsText(int n) => n == 1
    ? "1 song from your files isn't shared"
    : "$n songs from your files aren't shared";

class _ShareDialog extends ConsumerStatefulWidget {
  const _ShareDialog({required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<_ShareDialog> {
  String? _code;
  int _local = 0;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _share();
  }

  Future<void> _share() async {
    final sharing = ref.read(playlistSharingProvider);
    try {
      final code = await sharing.share(widget.playlistId);
      final local = await sharing.localCount(widget.playlistId);
      if (!mounted) return;
      setState(() {
        _code = code;
        _local = local;
        _busy = false;
      });
    } on FriendsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendActionError(e);
        _busy = false;
      });
    }
  }

  Future<void> _copy(String link) async {
    final islands = Islands.of(context);
    await Clipboard.setData(ClipboardData(text: link));
    islands.show('Link copied', kind: IslandKind.success);
  }

  Future<void> _stop() async {
    final islands = Islands.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(playlistSharingProvider).stopSharing(widget.playlistId);
      islands.show('Stopped sharing', kind: IslandKind.success);
      navigator.pop();
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
    final code = _code;
    final link = code == null ? null : playlistLink(code);
    final error = _error;
    return AlertDialog(
      title: const Text('Share playlist'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (link != null) ...[
              Text(
                'Anyone with this link can follow the playlist or copy it.',
                style: TextStyle(color: colors.mutedText),
              ),
              const SizedBox(height: 12),
              SelectableText(
                link,
                key: const Key('share.link'),
                style: TextStyle(color: colors.text),
              ),
              if (_local > 0) ...[
                const SizedBox(height: 8),
                Text(
                  localSongsText(_local),
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
              ],
            ],
            if (error != null)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy && link == null)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
      actions: [
        if (link != null)
          TextButton(
            key: const Key('share.stop'),
            onPressed: _busy ? null : _stop,
            child: const Text('Stop sharing'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (link != null)
          FilledButton(
            key: const Key('share.copyLink'),
            onPressed: _busy ? null : () => _copy(link),
            child: const Text('Copy link'),
          ),
      ],
    );
  }
}
