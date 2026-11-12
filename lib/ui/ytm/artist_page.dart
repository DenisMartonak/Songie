import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../innertube/ytm_models.dart';
import '../../providers.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import 'ytm_page_parts.dart';
import 'ytm_shelf_row.dart';

/// Top songs shown before Show all.
const int kArtistTopSongs = 5;

/// A YouTube Music artist: picture and name, Play (the top songs) and Radio
/// (the artist's radio), then Top songs, Albums, Singles and Fans also like.
/// Sections YouTube left out are not shown.
class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({required this.browseId, super.key});

  final String browseId;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
  bool _allTopSongs = false;

  @override
  Widget build(BuildContext context) {
    final provider = ytmArtistProvider(widget.browseId);
    return YtmAsyncPage(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      content: _content,
    );
  }

  Widget _content(YtmArtistPage page) {
    final artist = page.artist;
    final top = page.topSongs;
    final radio = page.radioPlaylistId;
    final shown = _allTopSongs ? top : top.take(kArtistTopSongs).toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: YtmHero(
            kind: 'Artist',
            title: artist.name,
            subtitle: page.monthlyListeners == null
                ? null
                : '${page.monthlyListeners} monthly listeners',
            thumbnailUrl: artist.thumbnailUrl,
            seed: artist.browseId,
            circle: true,
            actions: [
              YtmPlayButton(
                onPressed: top.isEmpty ? null : () => playYtmList(ref, top),
              ),
              // The radio starts from the first top song.
              if (radio != null && top.isNotEmpty)
                YtmHeroAction(
                  key: const Key('ytm.radio'),
                  icon: Icons.radio_outlined,
                  label: 'Radio',
                  onPressed: () => _startRadio(top.first, radio),
                ),
            ],
          ),
        ),
        if (top.isNotEmpty) ...[
          const SliverToBoxAdapter(child: YtmSectionTitle('Top songs')),
          YtmSongsSliver(
            songs: shown,
            onTap: (song) => playYtmList(ref, top, from: song),
          ),
          if (shown.length < top.length)
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton(
                    key: const Key('ytm.showAll'),
                    onPressed: () => setState(() => _allTopSongs = true),
                    child: const Text('Show all'),
                  ),
                ),
              ),
            ),
        ],
        for (final (title, items) in [
          ('Albums', page.albums),
          ('Singles', page.singles),
          ('Fans also like', page.similar),
        ])
          if (items.isNotEmpty)
            SliverToBoxAdapter(
              child: YtmShelfRow(shelf: YtmShelf(title, items)),
            ),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
        ),
      ],
    );
  }

  Future<void> _startRadio(YtmSong first, String playlistId) async {
    final islands = Islands.of(context);
    final radio = ref.read(radioControllerProvider);
    switch (await ref.read(ytTrackStoreProvider).upsert(first)) {
      case Ok(:final value):
        await radio.startRadio(value, playlistId: playlistId);
      case Err(:final failure):
        AppLog.w(
          'Artist radio: storing ${first.videoId} failed: '
          '${failure.message}',
        );
        islands.show("Couldn't start the radio", kind: IslandKind.failure);
    }
  }
}
