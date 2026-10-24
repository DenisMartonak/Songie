import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../downloads/download_repository.dart';
import '../../downloads/download_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'download_status_line.dart' show downloadPauseLine;

/// The run's progress, counting the running downloads' partial bytes.
double _runFraction(DownloadSnapshot s) {
  if (s.totalThisRun == 0) return 0;
  var partial = 0.0;
  for (final p in s.progress.values) {
    partial += p.fraction ?? 0;
  }
  return ((s.completedThisRun + partial) / s.totalThisRun).clamp(0.0, 1.0);
}

/// Clears the user's pause and any automatic one the user can end.
Future<void> resumeDownloads(DownloadService service) {
  service.resumeByUser();
  return service.resume();
}

Future<void> showDownloadsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => const DownloadsSheet(),
    );

/// The app-wide "Downloading `done` of `total`" row with a thin progress line,
/// shown while songs download or wait to; tapping it opens [DownloadsSheet].
/// [compact] is the collapsed sidebar's icon-only form.
class DownloadsIndicator extends ConsumerWidget {
  const DownloadsIndicator({this.compact = false, super.key});

  static const double height = 36;

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(downloadsActiveProvider)) return const SizedBox.shrink();
    return _Indicator(compact: compact);
  }
}

class _Indicator extends ConsumerWidget {
  const _Indicator({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final s = ref.watch(downloadSnapshotProvider).value;
    if (s == null) return const SizedBox.shrink();
    final text = 'Downloading ${s.completedThisRun} of ${s.totalThisRun}';
    final fraction = _runFraction(s);
    if (compact) {
      return Tooltip(
        message: text,
        child: InkWell(
          key: const Key('downloads.indicator'),
          borderRadius: BorderRadius.circular(colors.radius),
          onTap: () => showDownloadsSheet(context),
          child: SizedBox(
            height: 40,
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return InkWell(
      key: const Key('downloads.indicator'),
      borderRadius: BorderRadius.circular(colors.radius),
      onTap: () => showDownloadsSheet(context),
      child: SizedBox(
        height: DownloadsIndicator.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.downloading, size: 16, color: colors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: fraction, minHeight: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// The running downloads with their progress, the queued count, Pause /
/// Resume and Retry failed.
class DownloadsSheet extends ConsumerWidget {
  const DownloadsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final s =
        ref.watch(downloadSnapshotProvider).value ?? const DownloadSnapshot();
    final service = ref.read(downloadServiceProvider);
    final pause = s.pause;
    // A Wi-Fi only pause ends on Wi-Fi, not on Resume.
    final canResume =
        s.userPaused ||
        (pause != null && pause.reason != DownloadPauseReason.wifiOnly);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloads',
              style: TextStyle(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pause != null
                  ? downloadPauseLine(pause, ref.watch(nowProvider)())
                  : s.userPaused
                  ? 'Paused'
                  : 'Downloading ${s.completedThisRun} of ${s.totalThisRun}',
              style: TextStyle(color: colors.mutedText, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final MapEntry(:key, :value) in s.progress.entries)
                    _ActiveRow(trackId: key, progress: value),
                ],
              ),
            ),
            if (s.queued > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${s.queued} queued',
                  style: TextStyle(color: colors.mutedText, fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!s.userPaused)
                  OutlinedButton(
                    onPressed: service.pauseByUser,
                    child: const Text('Pause downloads'),
                  ),
                if (canResume)
                  FilledButton(
                    onPressed: () => unawaited(resumeDownloads(service)),
                    child: const Text('Resume'),
                  ),
                TextButton(
                  onPressed: () => _retryFailed(ref),
                  child: const Text('Retry failed'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retryFailed(WidgetRef ref) async {
    try {
      await ref.read(downloadRepositoryProvider).retryFailed();
    } on DownloadDbException catch (e, s) {
      AppLog.w('Retrying failed downloads failed', e, s);
    }
  }
}

class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({required this.trackId, required this.progress});

  final String trackId;
  final TrackProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final title = ref.watch(downloadTrackProvider(trackId)).value?.title;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title ?? '…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.text, fontSize: 14),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: progress.fraction, minHeight: 3),
        ],
      ),
    );
  }
}
