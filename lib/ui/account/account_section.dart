import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../account/avatar_image.dart' show ImageTooBigException;
import '../../core/log.dart';
import '../../providers.dart';
import '../../sync/cloud/sync_status.dart';
import '../../theme/app_theme.dart';
import '../playlist/yt_playlist_actions.dart' show relativeTimeText;

/// A picked picture's size and bytes; [bytes] is null when the file is over
/// [maxAvatarSourceBytes]: it is not read.
typedef AvatarPick = ({int size, Uint8List? bytes});

/// The biggest image file accepted as a picture (before shrinking).
const int maxAvatarSourceBytes = 10 * 1024 * 1024;

/// Asks the user for an image; null when cancelled. A provider so tests can
/// replace the native dialog.
final avatarPickerProvider = Provider<Future<AvatarPick?> Function()>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a picture',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final path = file?.path;
    if (path == null) return null;
    final f = File(path);
    final size = await f.length();
    return (
      size: size,
      bytes: size > maxAvatarSourceBytes ? null : await f.readAsBytes(),
    );
  },
);

/// What to tell the user when an account action failed with [e]; an
/// unexpected failure is logged.
String accountActionError(Object e) {
  switch (e) {
    case AccountException(:final error):
      return error.message;
    case ImageTooBigException():
      return 'That image is too big';
    case FormatException():
      return "Couldn't read that image";
    default:
      AppLog.w('Account action failed: ${e.runtimeType}');
      return AccountError.unknown.message;
  }
}

/// The sync status line's main text.
String syncPhaseText(SyncPhase phase) => switch (phase) {
  SyncPhase.idle => 'Synced',
  SyncPhase.syncing => 'Syncing…',
  SyncPhase.offline => 'Waiting for internet',
  SyncPhase.error => "Couldn't sync. Will try again.",
  SyncPhase.clockWrong => "Can't sync: this device's date and time are wrong.",
  SyncPhase.updateNeeded => 'Update Songies to keep syncing',
};

/// Cloud sync's state ("Synced", "Syncing…", …), when it last synced, and
/// Sync now.
class SyncStatusLine extends ConsumerWidget {
  const SyncStatusLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final status =
        ref.watch(cloudSyncStatusProvider).value ??
        ref.read(cloudSyncProvider).current;
    final syncing = status.phase == SyncPhase.syncing;
    final last = status.lastSynced;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  syncPhaseText(status.phase),
                  key: const Key('account.syncStatus'),
                  style: TextStyle(
                    color: switch (status.phase) {
                      SyncPhase.error || SyncPhase.clockWrong => Theme.of(
                        context,
                      ).colorScheme.error,
                      _ => colors.text,
                    },
                    fontSize: 13,
                  ),
                ),
                if (last != null && !syncing)
                  Text(
                    'Last synced ${relativeTimeText(last, ref.read(nowProvider)())}',
                    key: const Key('account.lastSynced'),
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
                  ),
              ],
            ),
          ),
          TextButton(
            key: const Key('account.syncNow'),
            onPressed: syncing
                ? null
                : () => unawaited(ref.read(cloudSyncProvider).syncNow()),
            child: const Text('Sync now'),
          ),
        ],
      ),
    );
  }
}
