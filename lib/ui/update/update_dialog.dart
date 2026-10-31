import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../update/update_controller.dart';
import '../motion/motion.dart';
import '../settings/storage_usage.dart' show formatBytes;

/// Mounted update dialogs; set by the dialog itself, so a dialog torn down
/// with its navigator can't leave it stuck.
int _mounted = 0;

/// Whether the update dialog is on screen (only one is shown at a time).
bool get updateDialogOpen => _mounted > 0;

/// Shows the update dialog for the controller's current state. It can be
/// closed at any time; a download carries on in the background.
Future<void> showUpdateDialog(BuildContext context) async {
  if (updateDialogOpen) return;
  await showDialog<void>(
    context: context,
    builder: (_) => const UpdateDialog(),
  );
}

/// The release notes, cut to about [max] characters.
String shortNotes(String notes, {int max = 600}) {
  final t = notes.trim().characters;
  if (t.length <= max) return t.toString();
  // By grapheme, so an emoji is never cut in half.
  return '${t.take(max).toString().trimRight()}…';
}

class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key});

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  @override
  void initState() {
    super.initState();
    _mounted++;
  }

  @override
  void dispose() {
    _mounted--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);
    final ctl = ref.read(updateControllerProvider.notifier);
    final release = ctl.release;
    final isAndroid = ref.watch(isAndroidProvider);
    void close() => Navigator.of(context).pop();

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget notes() {
      final text = shortNotes(release?.notes ?? '');
      if (text.isEmpty) return const SizedBox.shrink();
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(child: Text(text)),
      );
    }

    final (Widget body, List<Widget> actions) = switch (state) {
      Available() => (
        notes(),
        [
          TextButton(
            onPressed: () {
              ctl.notNow();
              close();
            },
            child: const Text('Not now'),
          ),
          FilledButton(onPressed: ctl.accept, child: const Text('Update now')),
        ],
      ),
      ManualOnly() => (
        notes(),
        [
          TextButton(
            onPressed: () {
              ctl.notNow();
              close();
            },
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              ctl.openDownloadPage();
              close();
            },
            child: const Text('Open download page'),
          ),
        ],
      ),
      WaitingForWifi() => (
        const Text(
          "You're on mobile data, and downloads are set to Wi-Fi only.",
        ),
        [
          TextButton(onPressed: close, child: const Text('Close')),
          FilledButton(
            onPressed: ctl.downloadAnyway,
            child: const Text('Download anyway'),
          ),
        ],
      ),
      Downloading(:final received, :final total) => (
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
            ),
            const SizedBox(height: 8),
            Text(
              total > 0
                  ? 'Downloading · ${formatBytes(received)} of '
                        '${formatBytes(total)}'
                  : 'Downloading · ${formatBytes(received)}',
              style: muted,
            ),
          ],
        ),
        [
          TextButton(onPressed: ctl.cancel, child: const Text('Cancel')),
          TextButton(onPressed: close, child: const Text('Hide')),
        ],
      ),
      ReadyToInstall() => (
        Text(
          isAndroid
              ? 'The update is downloaded and checked. Android will ask you '
                    'to confirm.'
              : 'The update is downloaded and checked. Songies will close '
                    'to install it and open again.',
        ),
        [
          TextButton(onPressed: close, child: const Text('Later')),
          FilledButton(
            onPressed: ctl.installNow,
            child: const Text('Install now'),
          ),
        ],
      ),
      Installing() => (
        Text(
          isAndroid
              ? 'Finish installing on the Android screen.'
              : 'Installing the update…',
        ),
        [TextButton(onPressed: close, child: const Text('Close'))],
      ),
      NeedsPermission() => (
        const Text(
          'To install updates, allow Songies to install unknown apps, '
          'then tap Install now.',
        ),
        [
          TextButton(
            onPressed: ctl.openPermissionSettings,
            child: const Text('Open settings'),
          ),
          FilledButton(
            onPressed: ctl.installNow,
            child: const Text('Install now'),
          ),
        ],
      ),
      Failed(:final message) => (
        Text(message),
        [
          TextButton(
            onPressed: () {
              ctl.openDownloadPage();
              close();
            },
            child: const Text('Open download page'),
          ),
          TextButton(onPressed: close, child: const Text('Close')),
        ],
      ),
      Idle() || Checking() || NoUpdate() || CheckError() => (
        const SizedBox.shrink(),
        [TextButton(onPressed: close, child: const Text('Close'))],
      ),
    };

    return AlertDialog(
      title: Text(
        release == null
            ? 'Update Songies'
            : 'Songies ${release.version} is available',
      ),
      content: AnimatedSize(
        duration: Motion.of(context).standard,
        curve: Motion.standardCurve,
        alignment: Alignment.topCenter,
        child: SizedBox(width: 400, child: body),
      ),
      actions: actions,
    );
  }
}
