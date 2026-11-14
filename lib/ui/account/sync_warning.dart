import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../sync/cloud/sync_status.dart';
import '../../theme/app_theme.dart';

/// Why cloud sync can't keep up, on your profile: a wrong clock (in the
/// error color) or a newer app on another device. Nothing otherwise.
class SyncWarning extends ConsumerWidget {
  const SyncWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final phase =
        (ref.watch(cloudSyncStatusProvider).value ??
                ref.read(cloudSyncProvider).current)
            .phase;
    final (text, color) = switch (phase) {
      SyncPhase.clockWrong => (
        "Can't sync: this device's date and time are wrong.",
        Theme.of(context).colorScheme.error,
      ),
      SyncPhase.updateNeeded => (
        'Update Songies to keep syncing',
        colors.mutedText,
      ),
      _ => (null, null),
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        key: const Key('profile.syncWarning'),
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 13),
      ),
    );
  }
}
