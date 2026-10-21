import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/log.dart';
import '../../data/database.dart';
import '../../library/library_scanner.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../library/add_folder_flow.dart';
import '../widgets/page_snack_bar.dart';
import 'storage_usage.dart';

/// The app version shown in About. Keep in sync with `version:` in
/// pubspec.yaml (a test checks it).
const String appVersion = '1.0.0';

/// Saves the exported log: returns true once saved, false if the user
/// cancelled. Throws if saving fails.
typedef LogSaver = Future<bool> Function(String fileName, Uint8List bytes);

/// A provider so tests can replace the native save dialog.
final logSaverProvider = Provider<LogSaver>(
  (ref) => (fileName, bytes) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Export log',
      fileName: fileName,
      bytes: bytes,
      mimeType: 'text/plain',
    );
    return saved != null;
  },
);

/// Music folders, storage, the log and About.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(bottom: bottom + 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
            child: Row(
              children: [
                if (context.canPop())
                  IconButton(
                    tooltip: 'Back',
                    color: colors.text,
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.pop(),
                  )
                else
                  const SizedBox(width: 8),
                Text(
                  'Settings',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const _FoldersSection(),
          const _StorageSection(),
          const _LogsSection(),
          const _AboutSection(),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _FoldersSection extends ConsumerWidget {
  const _FoldersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final folders = ref.watch(libraryFoldersProvider).value ?? const [];
    final progress = ref.watch(scanProgressProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Music folders',
          trailing: TextButton(
            key: const Key('settings.rescanAll'),
            onPressed: folders.isEmpty
                ? null
                : () =>
                      _rescan(context, ref, [for (final f in folders) f.path]),
            child: const Text('Rescan all'),
          ),
        ),
        if (progress != null) _ScanProgress(progress),
        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'No music folders yet',
              style: TextStyle(color: colors.mutedText),
            ),
          ),
        for (final (i, folder) in folders.indexed)
          _FolderRow(index: i, folder: folder),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: TextButton.icon(
            key: const Key('settings.addFolder'),
            onPressed: () => addMusicFolder(context, ref),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add folder'),
          ),
        ),
      ],
    );
  }
}

/// Queues a scan of each of [paths] (they run one at a time) and reports
/// every one that fails.
Future<void> _rescan(
  BuildContext context,
  WidgetRef ref,
  List<String> paths,
) async {
  final snacks = PageSnackBars.of(context);
  final queue = ref.read(scanQueueProvider);
  // Queue them all now; ScanQueue has already logged any failure.
  final runs = [
    for (final path in paths)
      queue.enqueue(path).then<bool>((_) => true, onError: (_) => false),
  ];
  for (final (i, run) in runs.indexed) {
    if (!await run) {
      snacks.show(
        content: Text("Couldn't scan ${folderDisplayName(paths[i])}"),
      );
    }
  }
}

class _ScanProgress extends StatelessWidget {
  const _ScanProgress(this.progress);

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final found = progress.found;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            found == 0
                ? 'Looking for music…'
                : 'Scanning · ${progress.processed} of $found',
            style: TextStyle(color: colors.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: found == 0 ? null : progress.processed / found,
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends ConsumerWidget {
  const _FolderRow({required this.index, required this.folder});

  final int index;
  final LibraryFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final scanned = folder.lastScanAt;
    return Padding(
      key: Key('settings.folder.row.$index'),
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  scanned == null
                      ? 'Not scanned yet'
                      : 'Last scanned ${_dateTimeText(scanned)}',
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('settings.rescan.${folder.path}'),
            tooltip: 'Rescan',
            color: colors.text,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _rescan(context, ref, [folder.path]),
          ),
          IconButton(
            key: Key('settings.remove.${folder.path}'),
            tooltip: 'Remove',
            color: colors.text,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _confirmRemove(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(libraryRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove folder?'),
        content: Text(
          '${folder.path} will no longer be rescanned. '
          'Songs already in your library stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await repo.removeFolder(folder.path);
  }
}

/// "2026-10-21 09:05" in local time.
String _dateTimeText(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// A label with a value on the right.
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: colors.text)),
          ),
          Text(value, style: TextStyle(color: colors.mutedText)),
        ],
      ),
    );
  }
}

class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider).value;
    String size(int? bytes) => bytes == null ? '…' : formatBytes(bytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Storage'),
        _InfoRow('Artwork', size(usage?.artBytes)),
        _InfoRow('Database', size(usage?.databaseBytes)),
      ],
    );
  }
}

class _LogsSection extends ConsumerWidget {
  const _LogsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Logs'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            key: const Key('settings.exportLog'),
            onPressed: () => _exportLog(context, ref),
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Export log'),
          ),
        ),
      ],
    );
  }

  Future<void> _exportLog(BuildContext context, WidgetRef ref) async {
    final snacks = PageSnackBars.of(context);
    final logs = ref.read(appPathsProvider).logs;
    final save = ref.read(logSaverProvider);

    await AppLog.flush();
    final bytes = _readLog(logs);
    if (bytes == null) {
      snacks.show(content: const Text('No log yet'));
      return;
    }
    try {
      if (await save('songies.log', bytes)) {
        snacks.show(content: const Text('Log saved'));
      }
    } catch (e, s) {
      AppLog.e('Exporting the log failed', e, s);
      snacks.show(content: const Text("Couldn't save the log"));
    }
  }

  /// The rotated log followed by the current one; null when both are empty
  /// or missing. Small (at most 2 MB each), so read in one go.
  static Uint8List? _readLog(Directory logs) {
    final builder = BytesBuilder(copy: false);
    for (final name in ['songies.log.1', 'songies.log']) {
      final file = File('${logs.path}/$name');
      if (file.existsSync()) builder.add(file.readAsBytesSync());
    }
    return builder.isEmpty ? null : builder.takeBytes();
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceId = ref.watch(deviceIdProvider);
    final shortId = deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('About'),
        const _InfoRow('Version', appVersion),
        _InfoRow('Device ID', shortId),
      ],
    );
  }
}
