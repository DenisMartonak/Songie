import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../motion/pressable.dart';
import '../widgets/name_dialog.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../widgets/playlist_art.dart';

/// Lets the user pick a playlist (or make a new one) and appends [trackIds]
/// to it, saying so on the island. Songs the
/// playlist already holds are left out; when that is all of them it says
/// "Already in" the playlist and adds nothing.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<String> trackIds,
) async {
  final islands = Islands.of(context);
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => const _AddToPlaylistSheet(),
  );
  if (choice == null || !context.mounted) return;
  final repo = ref.read(libraryRepositoryProvider);

  var id = choice.playlist?.id;
  var name = choice.playlist?.name;
  if (choice.isNew) {
    name = await showPlaylistNameDialog(
      context,
      title: 'New playlist',
      confirmLabel: 'Save',
    );
    if (name == null) return;
    switch (await repo.createPlaylist(name)) {
      case Ok(:final value):
        id = value;
      case Err():
        islands.show("Couldn't create playlist", kind: IslandKind.failure);
        return;
    }
  }
  // Songs the playlist already holds are not added again.
  var present = const <String>{};
  if (!choice.isNew) {
    try {
      present = await repo.trackIdsIn(id!);
    } catch (e, s) {
      // Add anyway rather than not at all.
      AppLog.w('Reading playlist $id before adding failed', e, s);
    }
  }
  final fresh = [
    for (final t in trackIds)
      if (!present.contains(t)) t,
  ];
  if (fresh.isEmpty) {
    islands.show('Already in $name');
    return;
  }
  final added = await repo.addTracks(id!, fresh);
  if (added is Ok<void>) {
    islands.show('Added to $name', kind: IslandKind.success);
  } else {
    islands.show("Couldn't add to $name", kind: IslandKind.failure);
  }
}

class _Choice {
  const _Choice.playlist(PlaylistSummary this.playlist) : isNew = false;
  const _Choice.create() : playlist = null, isNew = true;

  final PlaylistSummary? playlist;
  final bool isNew;
}

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    // Followed playlists change only from their owner's: not offered.
    final playlists = [
      for (final p in ref.watch(playlistsProvider).value ?? const [])
        if (!p.followed) p,
    ];
    final height = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      key: const Key('addToPlaylist.sheet'),
      constraints: BoxConstraints(maxHeight: height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Add to playlist',
              style: TextStyle(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                ListTile(
                  key: const Key('addToPlaylist.new'),
                  leading: Icon(Icons.add, color: colors.text),
                  title: Text(
                    'New playlist',
                    style: TextStyle(color: colors.text),
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(const _Choice.create()),
                ),
                for (final p in playlists)
                  Pressable(
                    key: Key('addToPlaylist.${p.id}'),
                    onTap: () => Navigator.of(context).pop(_Choice.playlist(p)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          PlaylistArt(
                            playlistId: p.id,
                            coverRef: p.coverRef,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
