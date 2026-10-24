import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../downloads/download_notifier.dart';
import '../../downloads/download_repository.dart';
import '../../downloads/download_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../settings/storage_usage.dart';

/// [downloadPauseText] as a line of its own: "Waiting for Wi-Fi", …
String downloadPauseLine(DownloadPause p, DateTime now) {
  final t = downloadPauseText(p, now);
  return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}

/// Whether a Resume button can end [s]'s pause: the user's own, or one that
/// [DownloadService.resume] clears (a Wi-Fi only pause ends on Wi-Fi).
bool canResumeDownloads(DownloadSnapshot s) {
  final pause = s.pause;
  return s.userPaused ||
      (pause != null && pause.reason != DownloadPauseReason.wifiOnly);
}

/// Clears the user's pause and any automatic one the user can end.
Future<void> resumeDownloads(DownloadService service) {
  service.resumeByUser();
  return service.resume();
}

/// The line under a YouTube playlist's hero: its download progress, the
/// queue's pause, its failures or that it is all downloaded. Nothing while
/// the download is off.
class DownloadStatusLine extends ConsumerWidget {
  const DownloadStatusLine({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(playlistDownloadProvider(playlistId)).value;
    if (status == null || !status.enabled) return const SizedBox.shrink();
    final Widget line;
    if (status.queued + status.downloading > 0) {
      line = _InFlight(playlistId: playlistId, status: status);
    } else if (status.failed > 0) {
      line = _Failed(playlistId: playlistId, failed: status.failed);
    } else if (status.total > 0 && status.done >= status.total) {
      final songs = status.total == 1 ? '1 song' : '${status.total} songs';
      line = _Text('Downloaded · $songs · ${formatBytes(status.bytes)}');
    } else {
      return const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.only(top: 8), child: line);
  }
}

class _Text extends StatelessWidget {
  const _Text(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: colors.mutedText, fontSize: 12),
    );
  }
}

/// Progress, or why the queue is paused.
class _InFlight extends ConsumerWidget {
  const _InFlight({required this.playlistId, required this.status});

  final String playlistId;
  final PlaylistDownloadStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pause = ref.watch(
      downloadSnapshotProvider.select((a) => a.value?.pause),
    );
    if (pause != null) {
      final text = _Text(downloadPauseLine(pause, ref.watch(nowProvider)()));
      if (pause.reason != DownloadPauseReason.diskFull &&
          pause.reason != DownloadPauseReason.user) {
        return text;
      }
      return Row(
        children: [
          Flexible(child: text),
          TextButton(
            onPressed: () => resumeDownloads(ref.read(downloadServiceProvider)),
            child: const Text('Resume'),
          ),
        ],
      );
    }
    final progress =
        ref.watch(downloadSnapshotProvider.select((a) => a.value?.progress)) ??
        const {};
    final states =
        ref.watch(trackDownloadStatesProvider(playlistId)).value ?? const {};
    var partial = 0.0;
    for (final MapEntry(:key, :value) in progress.entries) {
      if (states.containsKey(key)) partial += value.fraction ?? 0;
    }
    final total = status.total;
    final fraction = total == 0
        ? 0.0
        : ((status.done + partial) / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Text(
          'Downloading ${status.done} of $total · '
          '${formatBytes(status.bytes)}',
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: fraction),
      ],
    );
  }
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.playlistId, required this.failed});

  final String playlistId;
  final int failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _Text('$failed failed ·'),
        TextButton(onPressed: () => _retry(ref), child: const Text('Retry')),
      ],
    );
  }

  Future<void> _retry(WidgetRef ref) async {
    try {
      await ref
          .read(downloadRepositoryProvider)
          .retryFailed(playlistId: playlistId);
    } on DownloadDbException catch (e, s) {
      AppLog.w('Retrying failed downloads failed', e, s);
    }
  }
}
