import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../innertube/ytm_models.dart';
import '../../providers.dart';
import 'ytm_page_parts.dart';

/// The import link for an album's playlist, or null unless its id is a
/// YouTube Music album playlist (`OLAK5uy_…`); the album parser does not
/// check every path it reads the id from.
String? albumImportUrl(YtmAlbum album) {
  final id = album.playlistId;
  if (id == null || !id.startsWith('OLAK5uy_')) return null;
  return 'https://music.youtube.com/playlist?list=$id';
}

/// A YouTube Music album: cover, title, artist and year, Play, Shuffle and
/// Import as playlist, then the tracklist. A track plays the album from it.
class AlbumPage extends ConsumerWidget {
  const AlbumPage({required this.browseId, super.key});

  final String browseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => YtmAsyncPage(
    value: ref.watch(ytmAlbumProvider(browseId)),
    onRetry: () => ref.invalidate(ytmAlbumProvider(browseId)),
    content: (page) => _content(context, ref, page),
  );

  Widget _content(BuildContext context, WidgetRef ref, YtmAlbumPage page) {
    final album = page.album;
    final tracks = page.tracks;
    final importUrl = albumImportUrl(album);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: YtmHero(
            kind: 'Album',
            title: album.title,
            subtitle: ytmJoin([album.artist, album.year]),
            thumbnailUrl: album.thumbnailUrl,
            seed: album.browseId,
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
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
        ),
      ],
    );
  }
}
