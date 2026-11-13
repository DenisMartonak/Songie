import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database.dart';
import '../../innertube/ytm_models.dart';
import '../../library/library_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/contrast.dart';
import '../motion/fade_slide_in.dart';
import '../motion/motion.dart';
import '../motion/pressable.dart';
import '../shell/adaptive_shell.dart';
import '../friends/user_search_results.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';
import '../ytm/ytm_result_tiles.dart';
import '../ytm/ytm_song_row.dart';
import '../widgets/favorite_star.dart';

/// How long the query must stay unchanged before the library and YouTube
/// Music are searched.
const Duration searchDebounce = Duration(milliseconds: 150);

/// How many library songs and playlists show above the YouTube Music tabs
/// before "Show all". Small enough that the library section plus the tab row
/// (about 5 rows at 56 px, plus headers) fit on the first screen of a small
/// phone, so the tabs are always visible without scrolling; large enough to
/// show the obvious owned match or two.
const int librarySongsShown = 3;
const int libraryPlaylistsShown = 2;

/// The YouTube Music result tabs, in order, with their labels.
const Map<YtmSearchKind, String> ytmSearchTabs = {
  YtmSearchKind.songs: 'Songs',
  YtmSearchKind.videos: 'Videos',
  YtmSearchKind.albums: 'Albums',
  YtmSearchKind.artists: 'Artists',
  YtmSearchKind.playlists: 'Playlists',
};

/// Songs and playlists matching `searchQueryProvider`: matches in the library
/// first ("In your library"), then YouTube Music results in tabs. On a phone
/// the page has its own field; on desktop the title-bar field writes the
/// query.
///
/// Only the selected tab is fetched, once per query: tabs already opened for
/// the query keep their results, and a new query starts over on the selected
/// tab. Results are only ever shown for the latest query, so a slow answer
/// for an older one is never seen.
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

  /// The selected YouTube Music tab (kept across queries).
  YtmSearchKind _kind = YtmSearchKind.songs;

  /// Whether the Songies Users tab is selected instead of [_kind].
  bool _users = false;

  /// The tabs opened for [_searched], whose results are kept.
  Set<YtmSearchKind> _opened = {YtmSearchKind.songs};

  /// Whether "Show all" expanded the library section for [_searched].
  bool _libraryExpanded = false;

  void _search(String query) {
    if (query.trim() != _searched.trim()) {
      // On Songies Users nothing of YouTube Music is asked for the new query.
      _opened = _users ? {} : {_kind};
      _libraryExpanded = false;
    }
    _searched = query;
  }

  void _select(YtmSearchKind kind) => setState(() {
    _users = false;
    _kind = kind;
    _opened = {..._opened, kind};
  });

  void _selectUsers() => setState(() => _users = true);

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
      setState(() => _search(query));
      return;
    }
    _debounce = Timer(searchDebounce, () {
      if (mounted) setState(() => _search(query));
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
          Expanded(
            child: _Results(
              query: _searched,
              kind: _kind,
              users: _users,
              opened: _opened,
              onSelect: _select,
              onSelectUsers: _selectUsers,
              libraryExpanded: _libraryExpanded,
              onExpandLibrary: () => setState(() => _libraryExpanded = true),
            ),
          ),
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
  const _Results({
    required this.query,
    required this.kind,
    required this.users,
    required this.opened,
    required this.onSelect,
    required this.onSelectUsers,
    required this.libraryExpanded,
    required this.onExpandLibrary,
  });

  final String query;
  final YtmSearchKind kind;

  /// The Songies Users tab is selected (YouTube Music is not asked).
  final bool users;
  final Set<YtmSearchKind> opened;
  final ValueChanged<YtmSearchKind> onSelect;
  final VoidCallback onSelectUsers;
  final bool libraryExpanded;
  final VoidCallback onExpandLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final q = query.trim();
    if (q.isEmpty) {
      return _Message(
        'Search your library and YouTube Music',
        color: colors.mutedText,
        icon: Icon(
          Icons.manage_search_rounded,
          key: const Key('search.emptyIcon'),
          size: 56,
          color: colors.mutedText.withValues(alpha: 0.6),
        ),
      );
    }
    final songs = ref.watch(searchTracksProvider(query)).value ?? const [];
    final lists = ref.watch(searchPlaylistsProvider(query)).value ?? const [];
    // Tabs opened for this query stay subscribed, so switching back shows
    // their results without asking again.
    for (final k in opened) {
      if (users || k != kind) ref.watch(ytmSearchProvider((q, k)));
    }
    final remote = users ? null : ref.watch(ytmSearchProvider((q, kind)));
    // A short section, so the tabs stay on the first screen.
    final shownSongs = libraryExpanded
        ? songs
        : songs.take(librarySongsShown).toList();
    final shownLists = libraryExpanded
        ? lists
        : lists.take(libraryPlaylistsShown).toList();
    final hidden =
        songs.length + lists.length - shownSongs.length - shownLists.length;

    final bottom = MediaQuery.paddingOf(context).bottom;
    final children = <Widget>[
      if (songs.isNotEmpty || lists.isNotEmpty) ...[
        const _SectionTitle('In your library', key: ValueKey('library')),
        for (final track in shownSongs)
          _SongRow(track: track, key: ValueKey('song.${track.id}')),
        for (final playlist in shownLists)
          _PlaylistRow(
            playlist: playlist,
            key: ValueKey('playlist.${playlist.id}'),
          ),
        if (hidden > 0)
          _ShowAll(
            hidden: hidden,
            onTap: onExpandLibrary,
            key: const ValueKey('library.showAll'),
          ),
      ],
      _Tabs(
        selected: users ? null : kind,
        onSelect: onSelect,
        usersSelected: users,
        onSelectUsers: onSelectUsers,
        key: const ValueKey('tabs'),
      ),
      if (remote == null)
        UserSearchResults(query: q, key: const ValueKey('users'))
      else
        ..._remote(context, ref, q, remote, colors),
    ];
    // A new query is a new list, so its results fade in again.
    return ListView(
      key: ValueKey(q),
      padding: EdgeInsets.only(bottom: bottom + 16),
      children: [
        for (final (i, child) in children.indexed)
          FadeSlideIn(index: i, id: child.key, child: child),
      ],
    );
  }

  /// The selected tab's rows, or its loading, empty or failed state. Keys are
  /// unique per tab, so rows of a tab seen before appear without fading in.
  List<Widget> _remote(
    BuildContext context,
    WidgetRef ref,
    String q,
    AsyncValue<YtmSearchPage> remote,
    SongiesColors colors,
  ) {
    final tab = kind.name;
    if (remote.isLoading) {
      return [YtmSkeletonRows(key: ValueKey('ytm.$tab.loading'))];
    }
    if (remote.hasError) {
      return [
        YtmLoadProblem(
          key: ValueKey('ytm.$tab.problem'),
          offline: remote.error is YtmOffline,
          onRetry: () => ref.invalidate(ytmSearchProvider((q, kind))),
        ),
      ];
    }
    final items = remote.value?.items ?? const [];
    if (items.isEmpty) {
      return [
        Padding(
          key: ValueKey('ytm.$tab.empty'),
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: _Message("Nothing matches '$q'", color: colors.mutedText),
        ),
      ];
    }
    return [
      for (final (i, item) in items.indexed)
        ?switch (item) {
          YtmSong s => YtmSongRow(
            song: s,
            key: ValueKey('ytm.$tab.$i.${s.videoId}'),
          ),
          YtmAlbum a => YtmAlbumTile(
            album: a,
            key: ValueKey('ytm.$tab.$i.${a.browseId}'),
          ),
          YtmArtist a => YtmArtistTile(
            artist: a,
            key: ValueKey('ytm.$tab.$i.${a.browseId}'),
          ),
          YtmPlaylist p => YtmPlaylistTile(
            playlist: p,
            key: ValueKey('ytm.$tab.$i.${p.browseId}'),
          ),
          _ => null,
        },
    ];
  }
}

/// Expands the library section in place; the rows it reveals fade in.
class _ShowAll extends StatelessWidget {
  const _ShowAll({required this.hidden, required this.onTap, super.key});

  final int hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Pressable(
      key: const Key('search.library.showAll'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          'Show all ($hidden more)',
          style: TextStyle(
            color: colors.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The result tabs: YouTube Music's Songs · Videos · Albums · Artists ·
/// Playlists, then Songies Users.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.onSelect,
    required this.usersSelected,
    required this.onSelectUsers,
    super.key,
  });

  /// The selected YouTube Music tab; null while Songies Users is.
  final YtmSearchKind? selected;
  final ValueChanged<YtmSearchKind> onSelect;
  final bool usersSelected;
  final VoidCallback onSelectUsers;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('search.tabs'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Row(
        children: [
          for (final MapEntry(key: kind, value: label) in ytmSearchTabs.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _Tab(
                label: label,
                selected: kind == selected,
                onTap: () => onSelect(kind),
                key: Key('search.tab.${kind.name}'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _Tab(
              label: 'Songies Users',
              selected: usersSelected,
              onTap: onSelectUsers,
              key: const Key('search.tab.users'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final background = selected ? colors.accent : colors.surface;
    final foreground = readableOn(
      background,
      preferred: selected ? Colors.white : colors.text,
    );
    final radius = BorderRadius.circular(999);
    return Semantics(
      container: true,
      selected: selected,
      button: true,
      child: Pressable(
        onTap: selected ? null : onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: Motion.of(context).quick,
          curve: Motion.standardCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: background, borderRadius: radius),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {required this.color, this.icon});

  final String text;
  final Color color;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[icon, const SizedBox(height: 12)],
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 15),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {super.key});

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
    this.onLongPress,
    this.onSecondaryTapUp,
    this.trailing,
  });

  final Key rowKey;
  final String? artworkRef;
  final String seed;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Long-press and right-click (a song's menu).
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;

  /// After the text (a song row's star).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Pressable(
      key: rowKey,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapUp: onSecondaryTapUp,
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
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _SongRow extends ConsumerWidget {
  const _SongRow({required this.track, super.key});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = songMenuOpeners(context, ref, MenuSong.track(track));
    return _ResultRow(
      rowKey: Key('search.song.${track.id}'),
      artworkRef: track.artworkRef,
      seed: track.id,
      title: track.title,
      subtitle: track.artist,
      onTap: () => ref.read(playerInputsProvider).playQueue([track]),
      onLongPress: menu.onLongPress,
      onSecondaryTapUp: menu.onSecondaryTapUp,
      trailing: FavoriteStar(song: MenuSong.track(track)),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, super.key});

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
