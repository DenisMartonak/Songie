import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../library/favorites.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/contrast.dart';
import '../motion/pressable.dart';
import '../widgets/name_dialog.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../widgets/playlist_art.dart';

/// At least this wide, the sheet is a centered dialog.
const double _wideWidth = 840;

/// The island after Save: "Added to Rock", "Added to 3 playlists",
/// "Removed from …", both joined with " · "; null when nothing changed.
String? playlistSaveMessage({
  required List<String> added,
  required List<String> removed,
}) {
  String part(String verb, List<String> names) => names.length == 1
      ? '$verb ${names.single}'
      : '$verb ${names.length} playlists';
  final parts = [
    if (added.isNotEmpty) part('Added to', added),
    if (removed.isNotEmpty) part('Removed from', removed),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Shows where song [trackId] is (Favorites first, then the user's own
/// playlists, each ticked when it holds the song) and, on Save, adds it to
/// the newly ticked ones and removes it from the unticked ones. Closing
/// without Save changes nothing. A phone gets a bottom sheet, a wide window
/// a dialog.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  String trackId,
) async {
  final islands = Islands.of(context);
  final repo = ref.read(libraryRepositoryProvider);
  final favorites = ref.read(favoritesRepositoryProvider);
  // Unknown, nothing starts ticked: Save can then only add (never remove
  // what it couldn't see).
  var initial = const <String>{};
  try {
    initial = await repo.playlistIdsContaining(trackId);
  } catch (e, s) {
    AppLog.w('Reading where $trackId is failed', e, s);
  }
  if (!context.mounted) return;
  final sheet = _AddToPlaylistSheet(initial: initial, islands: islands);
  final wide = MediaQuery.sizeOf(context).width >= _wideWidth;
  final _Changes? changes;
  if (wide) {
    changes = await showDialog<_Changes>(
      context: context,
      useRootNavigator: true,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: sheet,
        ),
      ),
    );
  } else {
    changes = await showModalBottomSheet<_Changes>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => sheet,
    );
  }
  if (changes == null) return;

  final added = <String>[];
  final removed = <String>[];
  String? failed;
  for (final (id, name) in changes.add) {
    final Result<Object?> r = id == kFavoritesPlaylistId
        ? await favorites.star(trackId)
        : await repo.addTracks(id, [trackId]);
    if (r is Ok) {
      added.add(name);
    } else {
      failed ??= name;
    }
  }
  for (final (id, name) in changes.remove) {
    final Result<Object?> r = id == kFavoritesPlaylistId
        ? await favorites.unstar(trackId)
        : await repo.removeTrack(id, trackId);
    if (r is Ok) {
      removed.add(name);
    } else {
      failed ??= name;
    }
  }
  if (failed != null) {
    islands.show("Couldn't save to $failed", kind: IslandKind.failure);
    return;
  }
  final message = playlistSaveMessage(added: added, removed: removed);
  if (message != null) islands.show(message, kind: IslandKind.success);
}

/// What Save asks for: (playlist id, name) to add to and to remove from.
class _Changes {
  const _Changes(this.add, this.remove);

  final List<(String, String)> add;
  final List<(String, String)> remove;
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.initial, required this.islands});

  final Set<String> initial;
  final Islands islands;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_AddToPlaylistSheet> {
  late final Set<String> _ticked = {...widget.initial};
  bool _searching = false;
  String _query = '';

  bool _matches(String name) =>
      _query.isEmpty || name.toLowerCase().contains(_query.toLowerCase());

  void _toggle(String id) => setState(() {
    if (!_ticked.remove(id)) _ticked.add(id);
  });

  Future<void> _create() async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'New playlist',
      confirmLabel: 'Save',
    );
    if (name == null || !mounted) return;
    switch (await ref.read(libraryRepositoryProvider).createPlaylist(name)) {
      case Ok(:final value):
        if (mounted) setState(() => _ticked.add(value));
      case Err():
        widget.islands.show(
          "Couldn't create playlist",
          kind: IslandKind.failure,
        );
    }
  }

  void _save(List<PlaylistSummary> playlists) {
    String nameOf(String id) => id == kFavoritesPlaylistId
        ? kFavoritesName
        : playlists.firstWhere((p) => p.id == id).name;
    final known = {kFavoritesPlaylistId, for (final p in playlists) p.id};
    Navigator.of(context).pop(
      _Changes(
        [
          for (final id in _ticked)
            if (!widget.initial.contains(id) && known.contains(id))
              (id, nameOf(id)),
        ],
        [
          for (final id in widget.initial)
            if (!_ticked.contains(id) && known.contains(id)) (id, nameOf(id)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    // Followed playlists change only from their owner's: not offered.
    // Favorites is the pinned row, not one of the list's.
    final playlists = <PlaylistSummary>[
      for (final p in ref.watch(playlistsProvider).value ?? const [])
        if (!p.followed && p.id != kFavoritesPlaylistId) p,
    ];
    final shown = [
      for (final p in playlists)
        if (_matches(p.name)) p,
    ];
    // Only the boxes shown count (not a followed playlist that holds it).
    final listed = {kFavoritesPlaylistId, for (final p in playlists) p.id};
    final count = _ticked.where(listed.contains).length;
    final height = MediaQuery.sizeOf(context).height;
    // The keyboard (search, on a phone) pushes the sheet up.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        key: const Key('addToPlaylist.sheet'),
        constraints: BoxConstraints(maxHeight: height * 0.85 - keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _searching
                        ? TextField(
                            autofocus: true,
                            onChanged: (v) => setState(() => _query = v.trim()),
                            style: TextStyle(color: colors.text),
                            decoration: const InputDecoration(
                              hintText: 'Search playlists',
                              border: InputBorder.none,
                            ),
                          )
                        : Text(
                            'Add to playlist',
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  IconButton(
                    key: const Key('addToPlaylist.search'),
                    tooltip: _searching ? 'Close search' : 'Search',
                    color: colors.mutedText,
                    icon: Icon(_searching ? Icons.close : Icons.search),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      _query = '';
                    }),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    key: const Key('addToPlaylist.new'),
                    tooltip: 'New playlist',
                    icon: const Icon(Icons.add),
                    onPressed: _create,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  if (_matches(kFavoritesName))
                    _Row(
                      rowKey: const Key('addToPlaylist.favorites'),
                      checkKey: const Key(
                        'addToPlaylist.check.$kFavoritesPlaylistId',
                      ),
                      art: _FavoritesArt(colors: colors),
                      name: kFavoritesName,
                      checked: _ticked.contains(kFavoritesPlaylistId),
                      onTap: () => _toggle(kFavoritesPlaylistId),
                    ),
                  for (final p in shown)
                    _Row(
                      rowKey: Key('addToPlaylist.${p.id}'),
                      checkKey: Key('addToPlaylist.check.${p.id}'),
                      art: PlaylistArt(
                        playlistId: p.id,
                        coverRef: p.coverRef,
                        size: 48,
                      ),
                      name: p.name,
                      checked: _ticked.contains(p.id),
                      onTap: () => _toggle(p.id),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.mutedText.withValues(alpha: 0.3)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      count == 0 ? 'None selected' : '$count selected',
                      style: TextStyle(color: colors.mutedText),
                    ),
                  ),
                  FilledButton(
                    key: const Key('addToPlaylist.save'),
                    onPressed: () => _save(playlists),
                    child: const Text('Save'),
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

/// Favorites' square: the accent with a star.
class _FavoritesArt extends StatelessWidget {
  const _FavoritesArt({required this.colors});

  final SongiesColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(colors.radius),
      ),
      child: Icon(Icons.star_rounded, color: readableOn(colors.accent)),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rowKey,
    required this.checkKey,
    required this.art,
    required this.name,
    required this.checked,
    required this.onTap,
  });

  final Key rowKey;
  final Key checkKey;
  final Widget art;
  final String name;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Pressable(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            art,
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.text, fontSize: 16),
              ),
            ),
            Checkbox(key: checkKey, value: checked, onChanged: (_) => onTap()),
          ],
        ),
      ),
    );
  }
}
