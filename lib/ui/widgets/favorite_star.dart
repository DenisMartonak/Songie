import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../core/result.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'page_snack_bar.dart';
import 'song_menu.dart';

/// The library track id of a YouTube Music song, or null when it isn't in
/// the library yet (so its star is outlined).
final _libraryIdOfVideo = FutureProvider.autoDispose.family<String?, String>(
  (ref, videoId) async =>
      (await ref.watch(ytTrackStoreProvider).find(videoId))?.id,
);

/// The library track id of [song], if it is in the library.
String? _trackIdOf(WidgetRef ref, MenuSong song) {
  if (song.track case final t?) return t.id;
  return ref.watch(_libraryIdOfVideo(song.ytm!.videoId)).value;
}

/// Whether [song] is in Favorites.
bool isFavorite(WidgetRef ref, MenuSong song) {
  final id = _trackIdOf(ref, song);
  final ids = ref.watch(favoriteIdsProvider).value ?? const <String>{};
  return id != null && ids.contains(id);
}

/// Stars or un-stars [song]. A YouTube Music song not in the library is
/// stored first, as Add to playlist does; if that fails, nothing changes
/// and the user is told.
Future<void> toggleFavorite(
  BuildContext context,
  WidgetRef ref,
  MenuSong song,
) async {
  final favorites = ref.read(favoritesRepositoryProvider);
  final store = ref.read(ytTrackStoreProvider);
  final snacks = PageSnackBars.of(context);
  final Track track;
  if (song.track case final t?) {
    track = t;
  } else {
    final s = song.ytm!;
    switch (await store.upsert(s)) {
      case Ok(:final value):
        track = value;
        ref.invalidate(_libraryIdOfVideo(s.videoId));
      case Err(:final failure):
        AppLog.w('Storing ${s.videoId} failed: ${failure.message}');
        snacks.show(content: const Text("Couldn't add that song"));
        return;
    }
  }
  final r = await favorites.toggle(track.id);
  if (r case Err(:final failure)) {
    AppLog.w('Favorites toggle failed: ${failure.message}');
  }
}

/// A star: filled when [song] is a favorite, outlined when not. One tap
/// toggles it; it never opens anything.
class FavoriteStar extends ConsumerWidget {
  const FavoriteStar({required this.song, this.size = 20, super.key});

  final MenuSong song;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final on = isFavorite(ref, song);
    return IconButton(
      tooltip: on ? 'Remove from Favorites' : 'Add to Favorites',
      icon: Icon(
        on ? Icons.star_rounded : Icons.star_outline_rounded,
        size: size,
        color: on ? colors.accent : colors.mutedText,
      ),
      onPressed: () => toggleFavorite(context, ref, song),
    );
  }
}
