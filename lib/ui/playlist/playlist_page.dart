import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../library/add_songs_sheet.dart';
import '../library/pickers.dart';
import '../widgets/artwork.dart';
import '../widgets/name_dialog.dart';
import '../widgets/page_snack_bar.dart';

const double _rowHeight = 64;

/// "N songs · H h M min", e.g. "3 songs · 0 h 10 min".
String playlistSummaryText(int count, int durationMs) {
  final minutes = durationMs ~/ Duration.millisecondsPerMinute;
  final songs = count == 1 ? '1 song' : '$count songs';
  return '$songs · ${minutes ~/ 60} h ${minutes % 60} min';
}

/// "m:ss" for a track length.
String trackDurationText(int durationMs) {
  final seconds = durationMs ~/ Duration.millisecondsPerSecond;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// One playlist: hero, actions and the reorderable track list.
class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({required this.id, super.key});

  final String id;

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  /// The list as the user just left it (after a drop or a swipe), shown until
  /// the database stream catches up so rows do not jump back for a moment.
  List<PlaylistTrack>? _pending;

  String get _id => widget.id;

  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  Widget build(BuildContext context) {
    ref.listen(playlistTracksProvider(_id), (_, _) {
      if (_pending != null) setState(() => _pending = null);
    });
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final playlists = ref.watch(playlistsProvider);
    final streamed = ref.watch(playlistTracksProvider(_id));

    final summary = playlists.value
        ?.where((p) => p.id == _id)
        .cast<PlaylistSummary?>()
        .firstOrNull;
    if (summary == null) {
      return playlists.hasValue
          ? _NotFound(onBack: () => context.go('/library'))
          : const Center(child: CircularProgressIndicator());
    }
    final rows = _pending ?? streamed.value;
    if (rows == null) return const Center(child: CircularProgressIndicator());

    final current = ref.watch(
      playerStateProvider.select(
        (s) => s.value?.sourcePlaylistId == _id ? s.value?.current?.id : null,
      ),
    );
    final bottom = MediaQuery.paddingOf(context).bottom;
    final totalMs = rows.fold<int>(0, (sum, r) => sum + r.track.durationMs);

    return Stack(
      children: [
        // The soft accent wash behind the hero, as in the desktop mockup.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 240,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.accent.withValues(alpha: 0.28),
                  colors.background.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: EdgeInsets.only(bottom: bottom + 16),
            header: _Header(
              summary: summary,
              summaryText: playlistSummaryText(rows.length, totalMs),
              canPlay: rows.isNotEmpty,
              onPlay: () => _play(rows, shuffle: false),
              onShuffle: () => _play(rows, shuffle: true),
              onMenu: (action) => _onMenu(action, summary),
            ),
            footer: rows.isEmpty ? _EmptyPlaylist(onAdd: _addSongs) : null,
            itemCount: rows.length,
            onReorderItem: (from, to) => _reorder(rows, from, to),
            itemBuilder: (context, i) {
              final row = rows[i];
              return Dismissible(
                key: ValueKey(row.entryId),
                background: const _SwipeBackground(Alignment.centerLeft),
                secondaryBackground: const _SwipeBackground(
                  Alignment.centerRight,
                ),
                onDismissed: (_) => _remove(rows, i),
                child: _TrackRow(
                  key: ValueKey('row.${row.entryId}'),
                  row: row,
                  index: i,
                  playing: row.track.id == current,
                  onTap: () => _playFrom(rows, i),
                  onLocate: () => _locate(row),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- playback -------------------------------------------------------------

  Future<void> _playFrom(List<PlaylistTrack> rows, int index) {
    // A missing file would only be skipped; the user has to Locate it first.
    if (rows[index].fileMissing) return Future.value();
    return ref
        .read(playerServiceProvider)
        .playQueue(
          [for (final r in rows) r.track],
          startIndex: index,
          sourcePlaylistId: _id,
        );
  }

  Future<void> _play(List<PlaylistTrack> rows, {required bool shuffle}) {
    final player = ref.read(playerServiceProvider);
    player.setShuffle(shuffle);
    return player.playQueue(
      [for (final r in rows) r.track],
      // Shuffle starts anywhere, not always on the first song.
      startIndex: shuffle ? Random().nextInt(rows.length) : 0,
      sourcePlaylistId: _id,
    );
  }

  // --- editing --------------------------------------------------------------

  /// [target] is the row's new index once it has been taken out of the list.
  Future<void> _reorder(List<PlaylistTrack> rows, int from, int target) async {
    if (target == from) return;
    final moved = rows[from];
    final list = [...rows]..removeAt(from);
    final after = target > 0 ? list[target - 1].entryId : null;
    final before = target < list.length ? list[target].entryId : null;
    list.insert(target, moved);
    setState(() => _pending = list);

    final result = await _repo.moveEntry(
      moved.entryId,
      afterEntryId: after,
      beforeEntryId: before,
    );
    if (result is Err<void> && mounted) {
      setState(() => _pending = null);
      _say('Couldn\'t move that song');
    }
  }

  Future<void> _remove(List<PlaylistTrack> rows, int index) async {
    final removed = rows[index];
    final previous = index > 0 ? rows[index - 1].entryId : null;
    final next = index < rows.length - 1 ? rows[index + 1].entryId : null;
    setState(() => _pending = [...rows]..removeAt(index));

    final snacks = PageSnackBars.of(context);
    final repo = _repo;
    final result = await repo.removeEntry(removed.entryId);
    if (!mounted) return;
    if (result is Err<void>) {
      setState(() => _pending = null);
      _say('Couldn\'t remove that song');
      return;
    }
    snacks
      ..clear()
      ..show(
        content: Text('Removed ${removed.track.title}', maxLines: 1),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoRemove(repo, removed.track.id, previous, next),
        ),
      );
  }

  /// Puts a removed track back between its old neighbours. The track returns
  /// as a new entry (the removed one stays a tombstone for sync).
  Future<void> _undoRemove(
    LibraryRepository repo,
    String trackId,
    String? previous,
    String? next,
  ) async {
    final added = await repo.addTracks(_id, [trackId]);
    if (added is Err<void>) {
      _say('Couldn\'t undo that');
      return;
    }
    final entries = await repo.watchPlaylistTracks(_id).first;
    final live = {for (final e in entries) e.entryId};
    final restored = entries.last.entryId; // appended last
    await repo.moveEntry(
      restored,
      afterEntryId: live.contains(previous) ? previous : null,
      beforeEntryId: live.contains(next) ? next : null,
    );
  }

  Future<void> _locate(PlaylistTrack row) async {
    final path = await ref.read(audioFilePickerProvider)();
    if (path == null || !mounted) return;
    final imported = await ref.read(libraryScannerProvider).importFile(path);
    if (!mounted) return;
    switch (imported) {
      case Err(:final failure):
        AppLog.w('Locate failed for $path: ${failure.message}');
        _say('Couldn\'t use that file');
      case Ok(:final value):
        // The same content is already repaired; a different file is a different
        // track, so the entry has to point at it.
        if (value == row.track.id) return;
        final swapped = await _repo.replaceEntryTrack(row.entryId, value);
        if (swapped is Err<void>) _say('Couldn\'t use that file');
    }
  }

  // --- menu -----------------------------------------------------------------

  Future<void> _onMenu(_MenuAction action, PlaylistSummary summary) async {
    switch (action) {
      case _MenuAction.rename:
        final name = await showPlaylistNameDialog(
          context,
          title: 'Rename playlist',
          initial: summary.name,
        );
        if (name == null) return;
        final result = await _repo.renamePlaylist(_id, name);
        if (result is Err<void>) _say("Couldn't rename the playlist");
      case _MenuAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete playlist?'),
            content: Text(
              '"${summary.name}" will be deleted. Your music files stay '
              'where they are.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        final result = await _repo.deletePlaylist(_id);
        if (!mounted) return;
        if (result is Err<void>) {
          _say('Couldn\'t delete the playlist');
        } else {
          context.go('/library');
        }
      case _MenuAction.addSongs:
        await _addSongs();
    }
  }

  Future<void> _addSongs() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => AddSongsSheet(playlistId: _id),
  );

  void _say(String message) {
    if (!mounted) return;
    showPageSnackBar(context, content: Text(message));
  }
}

enum _MenuAction { rename, delete, addSongs }

class _Header extends StatelessWidget {
  const _Header({
    required this.summary,
    required this.summaryText,
    required this.canPlay,
    required this.onPlay,
    required this.onShuffle,
    required this.onMenu,
  });

  final PlaylistSummary summary;
  final String summaryText;
  final bool canPlay;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final ValueChanged<_MenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final canGoBack = Navigator.canPop(context);
    // Narrow phones must fit Play, Shuffle and the menu on one line.
    const compact = ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canGoBack)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          else
            const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(colors.radius + 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Artwork(
                  summary.coverRef,
                  size: 112,
                  radius: colors.radius + 4,
                  seed: summary.id,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local playlist',
                      style: TextStyle(
                        color: colors.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summaryText,
                      style: TextStyle(color: colors.mutedText, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                style: compact,
                onPressed: canPlay ? onPlay : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: compact,
                onPressed: canPlay ? onShuffle : null,
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Shuffle'),
              ),
              const Spacer(),
              PopupMenuButton<_MenuAction>(
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz),
                onSelected: onMenu,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _MenuAction.rename,
                    child: Text('Rename'),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.addSongs,
                    child: Text('Add songs'),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.row,
    required this.index,
    required this.playing,
    required this.onTap,
    required this.onLocate,
    super.key,
  });

  final PlaylistTrack row;
  final int index;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final track = row.track;
    final missing = row.fileMissing;
    final dim = missing ? 0.45 : 1.0;
    return Material(
      color: colors.background,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: _rowHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Opacity(
                  opacity: dim,
                  child: Artwork(track.artworkRef, size: 44, seed: track.id),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: dim,
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: playing ? colors.accent : colors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (missing) ...[
                            const _MissingTag(),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Opacity(
                              opacity: dim,
                              child: Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.mutedText,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (missing)
                  TextButton(onPressed: onLocate, child: const Text('Locate')),
                Opacity(
                  opacity: dim,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      trackDurationText(track.durationMs),
                      style: TextStyle(color: colors.mutedText, fontSize: 12),
                    ),
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.drag_handle,
                      size: 22,
                      color: colors.mutedText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingTag extends StatelessWidget {
  const _MissingTag();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          'File missing',
          maxLines: 1,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground(this.alignment);

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.error,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  const _EmptyPlaylist({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text(
            'This playlist is empty',
            style: TextStyle(color: colors.mutedText),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onAdd, child: const Text('Add songs')),
        ],
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This playlist no longer exists'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onBack, child: const Text('Back to Library')),
        ],
      ),
    );
  }
}
