import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_version.dart';
import '../../core/log.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../library/library_scanner.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../update/update_controller.dart';
import '../library/add_folder_flow.dart';
import '../motion/motion.dart';
import '../bug_report/bug_report_form.dart';
import '../update/update_dialog.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../shell/adaptive_shell.dart' show phoneBreakpoint;
import 'storage_usage.dart';
import 'discord_settings.dart' show discordSupportedProvider;
import 'settings_categories.dart';

export '../../core/app_version.dart';

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

/// Settings: a list of categories, each with its own page at
/// `/settings/<slug>`. Phones show the list at `/settings` and a category's
/// page on its own; wide windows show the list beside the chosen category
/// (Library at `/settings`).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({this.category, super.key});

  /// The category to show; null at plain `/settings`.
  final SettingsCategory? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = visibleSettingsCategories(
      discordSupported: ref.watch(discordSupportedProvider),
    );
    // A category not listed here (Discord where it can't work) is Library.
    final shown = category != null && visible.contains(category)
        ? category
        : (category == null ? null : SettingsCategory.library);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final wide = MediaQuery.sizeOf(context).width >= phoneBreakpoint;

    if (wide) {
      final current = shown ?? SettingsCategory.library;
      return SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 280,
              child: ListView(
                padding: EdgeInsets.only(bottom: bottom + 16),
                children: [
                  const _Header('Settings', back: false),
                  for (final c in visible)
                    _CategoryTile(
                      c,
                      selected: c == current,
                      onTap: () => context.go('/settings/${c.slug}'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: ValueKey(current),
                padding: EdgeInsets.only(bottom: bottom + 16),
                children: [
                  _Header(current.title, back: false),
                  ...current.sections,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        key: ValueKey(shown),
        padding: EdgeInsets.only(bottom: bottom + 16),
        children: shown == null
            ? [
                // Phones open Settings from Home's gear and need a way back.
                _Header('Settings', back: context.canPop()),
                for (final c in visible)
                  _CategoryTile(
                    c,
                    onTap: () => context.push('/settings/${c.slug}'),
                  ),
              ]
            : [_Header(shown.title, back: true), ...shown.sections],
      ),
    );
  }
}

/// A page title, with a Back arrow when [back]. Back pops, or goes to the
/// category list when there's nothing to pop (the page was opened directly).
class _Header extends StatelessWidget {
  const _Header(this.title, {required this.back});

  final String title;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
      child: Row(
        children: [
          if (back)
            IconButton(
              tooltip: 'Back',
              color: colors.text,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/settings'),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One category in the list: icon, title and what's inside.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile(this.category, {required this.onTap, this.selected});

  final SettingsCategory category;
  final VoidCallback onTap;

  /// Null on phones, where the list has no current category.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final isSelected = selected ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        key: Key('settings.category.${category.slug}'),
        selected: isSelected,
        selectedTileColor: colors.text.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(category.icon, color: colors.text),
        title: Text(
          category.title,
          style: TextStyle(
            color: colors.text,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          category.line,
          style: TextStyle(color: colors.mutedText, fontSize: 12),
        ),
        trailing: selected == null
            ? Icon(Icons.chevron_right_rounded, color: colors.mutedText)
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// A section heading of the Settings page.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {this.trailing, super.key});

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

class FoldersSection extends ConsumerWidget {
  const FoldersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final folders = ref.watch(libraryFoldersProvider).value ?? const [];
    final progress = ref.watch(scanProgressProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(
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

/// Queues a scan of each of [paths] (they run one at a time) and, once all
/// are done, names every one that failed in one message.
Future<void> _rescan(
  BuildContext context,
  WidgetRef ref,
  List<String> paths,
) async {
  final islands = Islands.of(context);
  final queue = ref.read(scanQueueProvider);
  // Queue them all now; ScanQueue has already logged any failure. A folder
  // already queued from this page is skipped until its scan has finished.
  final queued = <String>[];
  final runs = <Future<bool>>[];
  for (final path in paths) {
    if (!_pendingRescans.add(path)) continue;
    queued.add(path);
    runs.add(
      queue
          .enqueue(path)
          .then<bool>((_) => true, onError: (_) => false)
          .whenComplete(() => _pendingRescans.remove(path)),
    );
  }
  final failed = <String>[];
  for (final (i, run) in runs.indexed) {
    if (!await run) failed.add(folderDisplayName(queued[i]));
  }
  if (failed.isEmpty) return;
  islands.show("Couldn't scan ${_listed(failed)}", kind: IslandKind.failure);
}

/// "A", "A and B", "A, B and C".
String _listed(List<String> names) => names.length == 1
    ? names.single
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// Folders queued for a rescan from this page whose scan has not finished.
final Set<String> _pendingRescans = {};

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

/// How the app looks and moves. Each row is one child of the column.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Appearance'),
        ListTile(
          key: const Key('settings.themes'),
          title: Text('Themes', style: TextStyle(color: colors.text)),
          subtitle: Text(
            ref.watch(activeThemeProvider).value?.name ?? '',
            style: TextStyle(color: colors.mutedText, fontSize: 12),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: colors.mutedText),
          onTap: () => context.push('/settings/themes'),
        ),
        SwitchListTile(
          key: const Key('settings.reduceMotion'),
          title: Text(
            'Reduce animations',
            style: TextStyle(color: colors.text),
          ),
          subtitle: Text(
            'Pages, presses and colours change at once',
            style: TextStyle(color: colors.mutedText, fontSize: 12),
          ),
          value: ref.watch(reduceMotionProvider),
          onChanged: (v) =>
              ref.read(settingsRepositoryProvider).setBool(kReduceMotion, v),
        ),
      ],
    );
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

class StorageSection extends ConsumerWidget {
  const StorageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider).value;
    String size(int? bytes) => bytes == null ? '…' : formatBytes(bytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Storage'),
        _InfoRow('Artwork', size(usage?.artBytes)),
        _InfoRow('Database', size(usage?.databaseBytes)),
      ],
    );
  }
}

class LogsSection extends ConsumerWidget {
  const LogsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Logs'),
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
    final islands = Islands.of(context);
    final logs = ref.read(appPathsProvider).logs;
    final save = ref.read(logSaverProvider);

    await AppLog.flush();
    final bytes = readLogFiles(logs);
    if (bytes == null) {
      islands.show('No log yet', kind: IslandKind.failure);
      return;
    }
    try {
      if (await save('songies.log', bytes)) {
        islands.show('Log saved', kind: IslandKind.success);
      }
    } catch (e, s) {
      AppLog.e('Exporting the log failed', e, s);
      islands.show("Couldn't save the log", kind: IslandKind.failure);
    }
  }
}

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceId = ref.watch(deviceIdProvider);
    final shortId = deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('About'),
        const _InfoRow('Version', appVersion),
        _InfoRow('Device ID', shortId),
        if (ref.watch(bugReportsBuiltProvider))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              key: const Key('settings.reportBug'),
              onPressed: () => showBugReportForm(context),
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('Report a bug'),
            ),
          ),
        const _CheckForUpdates(),
      ],
    );
  }
}

/// "Check for updates", with the result below it; an update opens the
/// update dialog.
class _CheckForUpdates extends ConsumerStatefulWidget {
  const _CheckForUpdates();

  @override
  ConsumerState<_CheckForUpdates> createState() => _CheckForUpdatesState();
}

class _CheckForUpdatesState extends ConsumerState<_CheckForUpdates> {
  /// The result shows only after a tap on this page.
  bool _asked = false;

  Future<void> _check() async {
    setState(() => _asked = true);
    final ctl = ref.read(updateControllerProvider.notifier);
    await ctl.checkNow();
    if (!mounted) return;
    switch (ref.read(updateControllerProvider)) {
      case Idle() || Checking() || NoUpdate() || CheckError():
        break;
      default:
        await showUpdateDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(updateControllerProvider);
    final checking = state is Checking;
    final result = !_asked
        ? null
        : switch (state) {
            Checking() => 'Checking…',
            NoUpdate() => 'No updates found.',
            CheckError() =>
              "Couldn't check for updates. Check your connection.",
            _ => null,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            key: const Key('settings.checkForUpdates'),
            onPressed: checking ? null : _check,
            icon: const Icon(Icons.system_update_alt_rounded),
            label: const Text('Check for updates'),
          ),
        ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              result,
              style: TextStyle(color: colors.mutedText, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
