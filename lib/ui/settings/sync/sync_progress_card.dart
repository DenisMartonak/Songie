import 'package:flutter/material.dart';

import '../../../sync/sync_progress.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/contrast.dart';
import '../../motion/motion.dart';

/// What a sync step is called on screen.
String syncStageLabel(SyncStage stage, {int done = 0, int total = 0}) =>
    switch (stage) {
      SyncStage.hello => 'Connecting',
      SyncStage.pulling => 'Fetching changes',
      SyncStage.merging || SyncStage.choosing => 'Merging',
      SyncStage.applying => 'Saving',
      SyncStage.files =>
        total > 0 ? 'Copying files $done of $total' : 'Copying files',
      SyncStage.finishing => 'Finishing',
    };

/// How far along the whole run is: each stage an equal share, the current
/// one filled by its counts when known.
double syncStageFraction(SyncStage stage, {int done = 0, int total = 0}) {
  final within = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
  return (stage.index + within) / SyncStage.values.length;
}

/// The line shown after a sync.
String syncSummaryText(SyncSummary s) {
  String n(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';
  return 'Synced with ${s.peerName}: '
      '${n(s.playlistsChanged, 'playlist', 'playlists')} changed, '
      '${n(s.songsAdded, 'song', 'songs')} added, '
      '${n(s.filesCopied, 'file', 'files')} copied.';
}

/// Why a sync with [name] did not finish.
String syncFailureText(SyncFailure failure, String name) => switch (failure) {
  SyncFailure.notFound => 'Not found. Open Sync devices on $name.',
  SyncFailure.schemaMismatch =>
    '$name runs a different version of Songies. '
        'Update both to the same version.',
  SyncFailure.busy =>
    'A sync is already running on one of the devices. '
        'Try again when it finishes.',
  SyncFailure.forgotten =>
    '$name no longer recognises this device. Unpair and pair again.',
  SyncFailure.cancelled => 'Sync cancelled. Nothing changed.',
  SyncFailure.network => 'The connection to $name was lost. Try again.',
};

/// Failures worth a Try again button.
bool syncFailureRetries(SyncFailure f) =>
    f == SyncFailure.notFound ||
    f == SyncFailure.busy ||
    f == SyncFailure.network;

/// The state of the sync on screen: a running step with an optional
/// progress bar and Cancel, or a finished message with an optional
/// Try again.
class SyncProgressCard extends StatelessWidget {
  const SyncProgressCard({
    required this.text,
    this.progress,
    this.onCancel,
    this.onRetry,
    super.key,
  });

  final String text;

  /// 0–1 while running; null for no bar.
  final double? progress;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final progress = this.progress;
    // AA on the card, which is not the page background.
    final textColor = readableOn(colors.surface, preferred: colors.text);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(colors.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  key: const Key('sync.status'),
                  style: TextStyle(color: textColor),
                ),
              ),
              if (onCancel != null)
                TextButton(
                  key: const Key('sync.cancel'),
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              if (onRetry != null)
                TextButton(
                  key: const Key('sync.retry'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
            ],
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: Motion.of(context).standard,
                curve: Motion.standardCurve,
                builder: (context, value, _) =>
                    LinearProgressIndicator(value: value),
              ),
            ),
        ],
      ),
    );
  }
}
