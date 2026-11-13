import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../innertube/ytm_models.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../shell/player_bar.dart' show formatDuration;
import '../widgets/artist_link.dart';
import '../widgets/song_menu.dart';
import '../widgets/favorite_star.dart';
import 'artist_lookup.dart' show firstArtistId;
import 'ytm_result_tiles.dart';

/// A YouTube Music song (or video): art, title, artists and album, duration
/// and a ⋯ button for the song menu ([showSongMenu]), which long-press and
/// right-click open too. A tap runs [onTap], or without one plays the song
/// with its radio queued after it.
class YtmSongRow extends ConsumerWidget {
  const YtmSongRow({required this.song, this.onTap, super.key});

  final YtmSong song;
  final VoidCallback? onTap;

  /// The artists (a link to the first one's page), then the album.
  Widget? _subtitle(SongiesColors colors, String? album) {
    final style = TextStyle(color: colors.mutedText, fontSize: 12);
    final artists = song.artistLine;
    final hasAlbum = album != null && album.trim().isNotEmpty;
    if (artists.trim().isEmpty && !hasAlbum) return null;
    if (artists.trim().isEmpty) {
      return Text(
        album!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return ArtistLink(
      text: artists,
      browseId: firstArtistId(song.artists),
      style: style,
      suffix: hasAlbum ? ' · $album' : null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final duration = song.durationMs;
    final album = song.album;
    final menu = songMenuOpeners(context, ref, MenuSong.ytm(song));
    return YtmTile(
      rowKey: Key('ytm.song.${song.videoId}'),
      art: YtmArtwork(song.thumbnailUrl, seed: song.videoId),
      title: song.title,
      subtitleWidget: _subtitle(colors, album),
      onTap:
          onTap ?? () => ref.read(radioControllerProvider).playWithRadio(song),
      onLongPress: menu.onLongPress,
      onSecondaryTapUp: menu.onSecondaryTapUp,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (duration != null && duration > 0)
            Text(
              formatDuration(Duration(milliseconds: duration)),
              style: TextStyle(color: colors.mutedText, fontSize: 12),
            ),
          FavoriteStar(song: MenuSong.ytm(song)),
          SongMenuButton(
            key: Key('ytm.song.menu.${song.videoId}'),
            song: MenuSong.ytm(song),
          ),
        ],
      ),
    );
  }
}
