import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../widgets/artwork.dart';
import '../widgets/name_dialog.dart';
import '../widgets/page_snack_bar.dart';
import 'add_folder_flow.dart';

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

  Future<void> _addFolder() => addMusicFolder(context, ref);

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
