import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../downloads/download_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../settings/storage_usage.dart';
import '../widgets/page_snack_bar.dart';

String _songs(int n) => n == 1 ? '1 song' : '$n songs';

/// The hero's Download switch of a YouTube playlist: a down-arrow in a circle,
/// outlined when off and filled with the accent when on.
class DownloadToggle extends ConsumerStatefulWidget {
  const DownloadToggle({required this.playlistId, super.key});

  final String playlistId;

  @override
  ConsumerState<DownloadToggle> createState() => _DownloadToggleState();
}

class _DownloadToggleState extends ConsumerState<DownloadToggle> {
  bool _busy = false;

  String get _id => widget.playlistId;

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOn() async {
    final snacks = PageSnackBars.of(context);
    final repo = ref.read(downloadRepositoryProvider);
    unawaited(ref.read(notificationPermissionProvider)());
    try {
      final n = await repo.setPlaylistDownload(_id, true);
      if (n > 0) {
        snacks
          ..clear()
          ..show(content: Text('Downloading ${_songs(n)}'));
      }
    } on DownloadDbException catch (e, s) {
      AppLog.w('Turning on downloads failed', e, s);
      snacks.show(content: const Text("Couldn't turn on downloads"));
    }
  }

  Future<void> _turnOff() async {
    final snacks = PageSnackBars.of(context);
    final repo = ref.read(downloadRepositoryProvider);
    final ytDir = ref.read(appPathsProvider).libraryYt;
    try {
      final only = await repo.exclusiveFiles(_id);
      var remove = false;
      if (only.isNotEmpty) {
        final bytes = await repo.doneBytes(only);
        if (!mounted) return;
        remove = await _askRemove(only.length, bytes) ?? false;
      }
      // Off either way; Remove also deletes the files nothing else needs.
      await repo.setPlaylistDownload(_id, false);
      if (remove) await repo.removeFiles(only, ytDir);
    } on DownloadDbException catch (e, s) {
      AppLog.w('Turning off downloads failed', e, s);
      snacks.show(content: const Text("Couldn't turn off downloads"));
    }
  }

  Future<bool?> _askRemove(int count, int bytes) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove downloads?'),
      content: Text(
        '${_songs(count)} (${formatBytes(bytes)}) '
        '${count == 1 ? 'is' : 'are'} only in this playlist. '
        'Remove ${count == 1 ? 'it' : 'them'} from this device?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep files'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final enabled = ref.watch(
      playlistDownloadProvider(_id).select((a) => a.value?.enabled ?? false),
    );
    return IconButton(
      key: const Key('playlist.download'),
      tooltip: enabled ? 'Downloaded' : 'Download',
      isSelected: enabled,
      iconSize: 28,
      color: colors.text,
      selectedIcon: Icon(Icons.arrow_circle_down, color: colors.accent),
      icon: const Icon(Icons.arrow_circle_down_outlined),
      onPressed: _busy ? null : () => _run(enabled ? _turnOff : _turnOn),
    );
  }
}
