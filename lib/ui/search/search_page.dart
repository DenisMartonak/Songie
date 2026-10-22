import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../shell/adaptive_shell.dart';
import '../widgets/artwork.dart';

/// How long the query must stay unchanged before the library is searched.
const Duration searchDebounce = Duration(milliseconds: 150);

/// Songs and playlists matching `searchQueryProvider`. On a phone the page has
/// its own field; on desktop the title-bar field writes the query.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  Timer? _debounce;

  /// The query the results are for; trails `searchQueryProvider` by
  /// [searchDebounce].
  late String _searched;

  @override
  void initState() {
    super.initState();
    final query = ref.read(searchQueryProvider);
    _controller = TextEditingController(text: query);
    _searched = query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    if (_controller.text != query) _controller.text = query;
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      // Clearing is immediate: there is nothing to wait for.
      setState(() => _searched = query);
      return;
    }
    _debounce = Timer(searchDebounce, () {
      if (mounted) setState(() => _searched = query);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(searchQueryProvider, (_, query) => _onQueryChanged(query));
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final isPhone = MediaQuery.sizeOf(context).width < phoneBreakpoint;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPhone) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text(
                'Search',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _SearchField(
                controller: _controller,
                onChanged: ref.read(searchQueryProvider.notifier).set,
              ),
            ),
          ],
          Expanded(child: _Results(query: _searched)),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return TextField(
      key: const Key('search.field'),
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Color(0xFF333333), fontSize: 15),
      cursorColor: colors.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        hintText: 'Songs, artists, playlists',
        hintStyle: const TextStyle(color: Color(0xFF777777), fontSize: 15),
        prefixIcon: const Icon(Icons.search, color: Color(0xFF333333)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(colors.radius + 4),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    if (query.trim().isEmpty) {
      return _Message(
        'Search your songs and playlists',
        color: colors.mutedText,
      );
    }
    final tracks = ref.watch(searchTracksProvider(query));
    final playlists = ref.watch(searchPlaylistsProvider(query));
    final songs = tracks.value;
    final lists = playlists.value;
    if (songs == null || lists == null) return const SizedBox.shrink();
    if (songs.isEmpty && lists.isEmpty) {
      return _Message(
        'No results for "${query.trim()}"',
        color: colors.mutedText,
      );
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.only(bottom: bottom + 16),
      children: [
        if (songs.isNotEmpty) ...[
          const _SectionTitle('Songs'),
          for (final track in songs) _SongRow(track: track),
        ],
        if (lists.isNotEmpty) ...[
          const _SectionTitle('Playlists'),
          for (final playlist in lists) _PlaylistRow(playlist: playlist),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 15),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          color: colors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.rowKey,
    required this.artworkRef,
    required this.seed,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key rowKey;
  final String? artworkRef;
  final String seed;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Artwork(artworkRef, size: 44, seed: seed),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
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

class _SongRow extends ConsumerWidget {
  const _SongRow({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ResultRow(
    rowKey: Key('search.song.${track.id}'),
    artworkRef: track.artworkRef,
    seed: track.id,
    title: track.title,
    subtitle: track.artist,
    onTap: () => ref.read(playerServiceProvider).playQueue([track]),
  );
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final songs = playlist.trackCount == 1
        ? '1 song'
        : '${playlist.trackCount} songs';
    return _ResultRow(
      rowKey: Key('search.playlist.${playlist.id}'),
      artworkRef: playlist.coverRef,
      seed: playlist.id,
      title: playlist.name,
      subtitle: 'Playlist · $songs',
      onTap: () => context.push('/search/playlist/${playlist.id}'),
    );
  }
}
