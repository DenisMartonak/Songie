import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../innertube/ytm_models.dart';
import '../../providers.dart';
import '../../youtube/yt_links.dart';
import 'ytm_page_parts.dart';
import 'ytm_result_tiles.dart';

/// Rows from the end at which the next page of a long playlist is fetched.
const int _loadMoreAhead = 5;

/// The import link for a YouTube Music playlist (its browse id without the
/// `VL` prefix), or null for one the import does not take (a personal mix).
String? ytmPlaylistImportUrl(String browseId) {
  final id = browseId.startsWith('VL') ? browseId.substring(2) : browseId;
  return parsePlaylistLink('https://music.youtube.com/playlist?list=$id');
}

/// A YouTube Music playlist, laid out like an album: Play, Shuffle and
/// Import as playlist, then the tracklist. Longer playlists load their next
/// page when scrolled near the end (each page once).
class YtmPlaylistScreen extends ConsumerStatefulWidget {
  const YtmPlaylistScreen({required this.browseId, super.key});

  final String browseId;

  @override
  ConsumerState<YtmPlaylistScreen> createState() => _YtmPlaylistScreenState();
}

class _YtmPlaylistScreenState extends ConsumerState<YtmPlaylistScreen> {
  /// The first page the extra pages below belong to.
  YtmPlaylistPage? _first;
  final List<YtmSong> _more = [];

  /// The next page's token; null when there is none or it is being fetched.
  String? _next;
  bool _loading = false;
  bool _failed = false;

  /// Starts over when the first page is (re)loaded.
  void _adopt(YtmPlaylistPage first) {
    if (identical(first, _first)) return;
    _first = first;
    _more.clear();
    _next = first.continuation;
    _loading = false;
    _failed = false;
  }

  Future<void> _loadMore() async {
    final token = _next;
    final first = _first;
    if (token == null || first == null || _loading || !mounted) return;
    setState(() {
      _next = null;
      _loading = true;
      _failed = false;
    });
    final res = await ref
        .read(ytmServiceProvider)
        .playlist(widget.browseId, continuation: token);
    if (!mounted || !identical(first, _first)) return;
    setState(() {
      _loading = false;
      switch (res) {
        case Ok(:final value):
          _more.addAll(value.tracks);
          // A token that comes back again would load the same page forever.
          _next = value.continuation == token ? null : value.continuation;
        case Err(:final failure):
          AppLog.w('ytm playlist continuation failed: ${failure.message}');
          _failed = true;
          _next = token;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = ytmPlaylistProvider(widget.browseId);
    return YtmAsyncPage(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      content: _content,
    );
  }

  Widget _content(YtmPlaylistPage first) {
    _adopt(first);
    final playlist = first.playlist;
    final tracks = [...first.tracks, ..._more];
    final importUrl = ytmPlaylistImportUrl(widget.browseId);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: YtmHero(
            kind: 'Playlist',
            title: playlist.title,
            subtitle: playlist.author,
            thumbnailUrl: playlist.thumbnailUrl,
            seed: playlist.browseId,
            actions: [
              YtmPlayButton(
                onPressed: tracks.isEmpty
                    ? null
                    : () => playYtmList(ref, tracks),
              ),
              YtmHeroAction(
                key: const Key('ytm.shuffle'),
                icon: Icons.shuffle_rounded,
                label: 'Shuffle',
                onPressed: tracks.isEmpty
                    ? null
                    : () => playYtmList(ref, tracks, shuffle: true),
              ),
              if (importUrl != null) YtmImportButton(url: importUrl),
            ],
          ),
        ),
        YtmSongsSliver(
          songs: tracks,
          onTap: (song) => playYtmList(ref, tracks, from: song),
          onBuild: (i) {
            // Rows are built as they scroll into view: near the end, fetch
            // the next page (after this frame: not while building).
            if (_next != null &&
                !_loading &&
                !_failed &&
                i >= tracks.length - _loadMoreAhead) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
            }
          },
        ),
        if (_loading)
          const SliverToBoxAdapter(child: YtmSkeletonRows(count: 2))
        else if (_failed)
          SliverToBoxAdapter(
            child: YtmLoadProblem(offline: false, onRetry: _loadMore),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
        ),
      ],
    );
  }
}
