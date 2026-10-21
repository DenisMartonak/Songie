import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/result.dart';
import '../../library/library_repository.dart';
import '../../library/library_scanner.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../widgets/artwork.dart';
import '../widgets/name_dialog.dart';
import '../widgets/page_snack_bar.dart';
import 'pickers.dart';

/// Filter chips above the playlist list. YouTube and Downloaded arrive with
/// the YouTube plans.
enum _Filter { all, local }

/// The user's playlists, plus the entry points for creating one and for adding
/// a music folder.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

enum _AddAction { newPlaylist, musicFolder }

class _LibraryPageState extends ConsumerState<LibraryPage> {
  _Filter _filter = _Filter.all;

  Future<void> _onAdd(_AddAction action) => switch (action) {
    _AddAction.newPlaylist => _newPlaylist(),
    _AddAction.musicFolder => _addFolder(),
  };

  Future<void> _newPlaylist() async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'New playlist',
      confirmLabel: 'Save',
    );
    if (name == null) return;
    final result = await ref
        .read(libraryRepositoryProvider)
        .createPlaylist(name);
    if (result is Err<String> && mounted) {
      showPageSnackBar(
        context,
        content: const Text("Couldn't create playlist"),
      );
    }
  }

  Future<void> _addFolder() async {
    final snacks = PageSnackBars.of(context);
    final access = await ref.read(mediaAccessProvider)();
    if (!mounted) return;
    if (!access) {
      await _explainPermission();
      return;
    }
    final path = await ref.read(folderPickerProvider)();
    if (path == null || !mounted) return;

    final folderName = _folderName(path);
    final createPlaylist = await showDialog<bool>(
      context: context,
      builder: (_) => _AddFolderDialog(path: path, folderName: folderName),
    );
    if (createPlaylist == null) return;

    final progress = snacks.show(
      content: _ScanProgressText(folderName: folderName),
      duration: const Duration(days: 1),
    );
    try {
      final result = await ref
          .read(scanQueueProvider)
          .enqueue(
            path,
            createPlaylistNamed: createPlaylist
                ? _playlistNameFor(folderName)
                : null,
          );
      progress.close();
      snacks.show(content: Text(_summary(result, folderName)));
    } catch (_) {
      // ScanQueue has already logged the details.
      progress.close();
      snacks.show(content: Text("Couldn't scan $folderName"));
    }
  }

  Future<void> _explainPermission() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow access to your music'),
        content: const Text(
          'Songies needs permission to read the music files on this device. '
          'Allow it in the app settings, then add the folder again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              openMediaSettings();
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final playlists = ref.watch(playlistsProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Your Library',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PopupMenuButton<_AddAction>(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add),
                  onSelected: _onAdd,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _AddAction.newPlaylist,
                      child: Text('New playlist'),
                    ),
                    PopupMenuItem(
                      value: _AddAction.musicFolder,
                      child: Text('Add music folder'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == _Filter.all,
                  onSelected: (_) => setState(() => _filter = _Filter.all),
                ),
                ChoiceChip(
                  label: const Text('Local'),
                  selected: _filter == _Filter.local,
                  onSelected: (_) => setState(() => _filter = _Filter.local),
                ),
              ],
            ),
          ),
          Expanded(
            child: playlists.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text("Couldn't load your playlists")),
              data: (all) {
                if (all.isEmpty) return _EmptyLibrary(onAdd: _addFolder);
                final shown = _filter == _Filter.local
                    ? [
                        for (final pl in all)
                          if (pl.source == 'local') pl,
                      ]
                    : all;
                return ListView.builder(
                  padding: EdgeInsets.only(bottom: bottom + 16),
                  itemCount: shown.length,
                  itemBuilder: (context, i) =>
                      _PlaylistTile(playlist: shown[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _folderName(String path) {
  final name = p.basename(path);
  return name.isEmpty ? path : name;
}

/// The repository rejects names over 100 characters.
String _playlistNameFor(String folderName) =>
    folderName.length > maxPlaylistNameLength
    ? folderName.substring(0, maxPlaylistNameLength)
    : folderName;

String _summary(ScanProgress? result, String folderName) {
  if (result == null) return 'Scanned $folderName';
  final songs = result.added == 1 ? '1 song' : '${result.added} songs';
  final skipped = result.skipped > 0 ? ' · ${result.skipped} skipped' : '';
  if (result.added == 0) {
    return 'No new songs in $folderName$skipped';
  }
  return 'Added $songs from $folderName$skipped';
}

class _AddFolderDialog extends StatefulWidget {
  const _AddFolderDialog({required this.path, required this.folderName});

  final String path;
  final String folderName;

  @override
  State<_AddFolderDialog> createState() => _AddFolderDialogState();
}

class _AddFolderDialogState extends State<_AddFolderDialog> {
  bool _createPlaylist = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add music folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.path, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _createPlaylist,
            onChanged: (on) => setState(() => _createPlaylist = on ?? false),
            title: Text("Also create playlist '${widget.folderName}'"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_createPlaylist),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// The body of the "scanning" snack bar; follows the scan queue.
class _ScanProgressText extends ConsumerWidget {
  const _ScanProgressText({required this.folderName});

  final String folderName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(scanProgressProvider).value;
    final found = progress?.found ?? 0;
    final text = found == 0
        ? 'Looking for music in $folderName…'
        : 'Scanning $folderName · ${progress!.processed} of $found';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: found == 0 ? null : progress!.processed / found,
        ),
      ],
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final source = playlist.source == 'yt' ? 'YouTube' : 'Local';
    final songs = playlist.trackCount == 1
        ? '1 song'
        : '${playlist.trackCount} songs';
    return InkWell(
      key: Key('library.playlist.${playlist.id}'),
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Artwork(playlist.coverRef, size: 56, seed: playlist.id),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$source · $songs',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 48,
              color: colors.mutedText,
            ),
            const SizedBox(height: 16),
            Text(
              'No playlists yet',
              style: TextStyle(
                color: colors.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a folder with MP3 files to build your first playlist.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.mutedText),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAdd,
              child: const Text('Add a music folder'),
            ),
          ],
        ),
      ),
    );
  }
}
