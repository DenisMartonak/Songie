import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../data/database.dart';
import '../../innertube/ytm_models.dart';
import '../../library/yt_tracks.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../library/add_to_playlist_sheet.dart';
import '../widgets/page_snack_bar.dart';
import 'ytm_nav.dart';

enum _SongAction { playNext, addToQueue, addToPlaylist, artist, album, radio }

/// A YouTube Music song's ⋯ menu: Play next, Add to queue, Add to playlist,
/// Go to artist, Go to album and Start radio. Go to artist (the first artist
/// with a page) and Go to album are left out without their ids. The queue and
/// playlist actions store the song as a track row first.
Future<void> showYtmSongMenu(
  BuildContext context,
  WidgetRef ref,
  YtmSong song,
) async {
  final artistId = song.artists
      .map((a) => a.browseId)
      .whereType<String>()
      .firstOrNull;
  final albumId = song.albumBrowseId;
  final action = await showModalBottomSheet<_SongAction>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) {
      final colors = Theme.of(sheet).extension<SongiesColors>()!;
      Widget item(_SongAction a, IconData icon, String label) => ListTile(
        key: Key('ytm.menu.${a.name}'),
        leading: Icon(icon, color: colors.text),
        title: Text(label, style: TextStyle(color: colors.text)),
        onTap: () => Navigator.of(sheet).pop(a),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            item(_SongAction.playNext, Icons.playlist_play, 'Play next'),
            item(_SongAction.addToQueue, Icons.queue_music, 'Add to queue'),
            item(
              _SongAction.addToPlaylist,
              Icons.playlist_add,
              'Add to playlist',
            ),
            if (artistId != null)
              item(_SongAction.artist, Icons.person_outline, 'Go to artist'),
            if (albumId != null)
              item(_SongAction.album, Icons.album_outlined, 'Go to album'),
            item(_SongAction.radio, Icons.radio_outlined, 'Start radio'),
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _SongAction.artist:
      context.goYtmArtist(artistId!);
    case _SongAction.album:
      context.goYtmAlbum(albumId!);
    case _SongAction.radio:
      await ref.read(radioControllerProvider).playWithRadio(song);
    case _SongAction.playNext:
      // Read before the first await: ref may be gone once it returns.
      final player = ref.read(playerServiceProvider);
      final track = await _store(context, ref.read(ytTrackStoreProvider), song);
      if (track != null) await player.playNext([track]);
    case _SongAction.addToQueue:
      final player = ref.read(playerServiceProvider);
      final track = await _store(context, ref.read(ytTrackStoreProvider), song);
      if (track != null) await player.addToQueue([track]);
    case _SongAction.addToPlaylist:
      final track = await _store(context, ref.read(ytTrackStoreProvider), song);
      if (track != null && context.mounted) {
        await showAddToPlaylistSheet(context, ref, [track.id]);
      }
  }
}

/// [song]'s track row, or null (with a snack bar) when it cannot be stored.
Future<Track?> _store(
  BuildContext context,
  YtTrackStore store,
  YtmSong song,
) async {
  final snacks = PageSnackBars.of(context);
  switch (await store.upsert(song)) {
    case Ok(:final value):
      return value;
    case Err(:final failure):
      AppLog.w('Storing ${song.videoId} failed: ${failure.message}');
      snacks.show(content: const Text("Couldn't add that song"));
      return null;
  }
}
