import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../downloads/download_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../youtube/yt_import_service.dart';
import '../../youtube/yt_models.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';

/// "just now", "N min ago", "N h ago" or "N d ago".
String relativeTimeText(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// What a finished sync tells the user.
String syncResultText(SyncResult r) {
  if (r.added == 0 && r.flaggedRemoved == 0) return 'Up to date';
  if (r.flaggedRemoved == 0) {
    return r.added == 1 ? 'Added 1 new song' : 'Added ${r.added} new songs';
  }
  return 'Added ${r.added}, ${r.flaggedRemoved} removed on YouTube';
}

/// The hero's small source line of a YouTube playlist:
/// "YouTube playlist · last synced 5 min ago".
class YtHeroSubtitle extends ConsumerWidget {
  const YtHeroSubtitle({
    required this.playlistId,
    required this.style,
    super.key,
  });

  final String playlistId;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final synced = ref
        .watch(playlistRowProvider(playlistId))
        .value
        ?.lastYtSyncAt;
    final now = ref.watch(nowProvider)();
    return Text(
      synced == null
          ? 'YouTube playlist'
          : 'YouTube playlist · last synced ${relativeTimeText(synced, now)}',
      style: style,
    );
  }
}

/// "Sync with YouTube"; shows "Syncing…" (and ignores taps) while running.
class YtSyncButton extends ConsumerStatefulWidget {
  const YtSyncButton({required this.playlistId, super.key});

  final String playlistId;

  @override
  ConsumerState<YtSyncButton> createState() => _YtSyncButtonState();
}

class _YtSyncButtonState extends ConsumerState<YtSyncButton> {
  bool _busy = false;

  Future<void> _sync() async {
    if (_busy) return;
    final islands = Islands.of(context);
    final service = ref.read(ytImportServiceProvider);
    final downloadRepo = ref.read(downloadRepositoryProvider);
    final downloads = ref.read(downloadServiceProvider);
    setState(() => _busy = true);
    final Result<SyncResult> result;
    try {
      result = await service.syncPlaylist(widget.playlistId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    switch (result) {
      case Ok(:final value):
        islands.show(syncResultText(value));
      case Err(:final failure):
        islands.show(ytErrorUserMessage(failure), kind: IslandKind.failure);
    }
    if (result case Ok(:final value) when value.addedTrackIds.isNotEmpty) {
      // New songs of a downloaded playlist are downloaded too.
      try {
        await downloadRepo.queueAdded(widget.playlistId, value.addedTrackIds);
        downloads.kick();
      } on DownloadDbException catch (e, s) {
        AppLog.w('Queueing synced songs failed', e, s);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      ),
      onPressed: _busy ? null : _sync,
      icon: _busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_rounded),
      label: Text(_busy ? 'Syncing…' : 'Sync with YouTube'),
    );
  }
}

/// A small grey tag next to a row's artist ("removed on YT", "unavailable").
class YtRowTag extends StatelessWidget {
  const YtRowTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.mutedText.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            color: colors.text,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Keep / Delete for an entry that was removed from the playlist on YouTube.
class YtRemovedActions extends ConsumerWidget {
  const YtRemovedActions({required this.entryId, super.key});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> run(Future<Result<void>> Function() action, String err) async {
      final islands = Islands.of(context);
      if (await action() is Err<void>) {
        islands.show(err, kind: IslandKind.failure);
      }
    }

    final repo = ref.read(libraryRepositoryProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () =>
              run(() => repo.keepEntry(entryId), "Couldn't keep that song"),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () =>
              run(() => repo.removeEntry(entryId), "Couldn't remove that song"),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
