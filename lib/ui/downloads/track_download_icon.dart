import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../downloads/download_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';

/// A track row's download state: queued, a progress ring, done or failed (tap
/// for the error and Retry). Nothing when the track has no download.
///
/// Reads its playlist's one state map; only the ring follows the progress.
class TrackDownloadIcon extends ConsumerWidget {
  const TrackDownloadIcon({
    required this.playlistId,
    required this.trackId,
    super.key,
  });

  final String playlistId;
  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(
      trackDownloadStatesProvider(playlistId).select((a) => a.value?[trackId]),
    );
    final Widget icon;
    switch (state) {
      case 'queued':
        icon = Icon(Icons.schedule, size: 16, color: colors.mutedText);
      case 'downloading':
        icon = _ProgressRing(trackId: trackId);
      case 'done':
        icon = Icon(Icons.download_done, size: 16, color: colors.accent);
      case 'failed':
        return IconButton(
          tooltip: 'Download failed',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          color: colors.mutedText,
          icon: const Icon(Icons.error_outline),
          onPressed: () => _showFailure(context, ref),
        );
      default:
        return const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.all(4), child: icon);
  }

  Future<void> _showFailure(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(downloadRepositoryProvider);
    String? error;
    try {
      error = await repo.downloadError(trackId);
    } on Exception catch (e, s) {
      AppLog.w('Reading a download error failed', e, s);
    }
    if (!context.mounted) return;
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Couldn't download this song"),
        content: Text(error ?? 'The download failed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (retry != true) return;
    try {
      await repo.retryFailed(trackId: trackId);
    } on DownloadDbException catch (e, s) {
      AppLog.w('Retrying a download failed', e, s);
    }
  }
}

class _ProgressRing extends ConsumerWidget {
  const _ProgressRing({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fraction = ref.watch(
      downloadSnapshotProvider.select(
        (a) => a.value?.progress[trackId]?.fraction,
      ),
    );
    return SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(value: fraction, strokeWidth: 2),
    );
  }
}
