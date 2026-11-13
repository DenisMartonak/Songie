import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result.dart';
import '../../data/database.dart';
import '../../innertube/ytm_models.dart';
import '../../innertube/ytm_service.dart';
import '../../providers.dart';
import '../shell/go_tab.dart';
import 'ytm_nav.dart';

/// The Search tab's branch index (see `router.dart`).
const int _searchTab = 1;

/// The first of [artists] with a YouTube Music page, or null.
String? firstArtistId(List<YtmArtistRef> artists) =>
    artists.map((a) => a.browseId).whereType<String>().firstOrNull;

/// Finds the YouTube Music artist page of a library track. Tracks don't
/// keep one, so a YouTube track asks for its radio, whose current song
/// names its artists. Answers (also "none") are kept per video; a failed
/// request is not, so the next try asks again.
class ArtistLookup {
  ArtistLookup(this._ytm);

  final YtmService _ytm;
  // The request in flight or its answer, so concurrent calls share one.
  final _found = <String, Future<String?>>{};

  Future<String?> forTrack(Track t) {
    final videoId = t.ytVideoId;
    if (t.source != 'yt' || videoId == null) return Future.value(null);
    return _found[videoId] ??= _ask(videoId);
  }

  Future<String?> _ask(String videoId) async {
    final result = await _ytm.radio(videoId);
    if (result case Ok(:final value)) {
      return firstArtistId(value.current?.artists ?? []);
    }
    _found.remove(videoId);
    return null;
  }
}

final artistLookupProvider = Provider<ArtistLookup>(
  (ref) => ArtistLookup(ref.watch(ytmServiceProvider)),
);

/// Opens an artist: [browseId] when known, else the one found for [track],
/// else Search for [name].
Future<void> openArtist(
  BuildContext context,
  WidgetRef ref, {
  String? browseId,
  Track? track,
  required String name,
}) async {
  final shell = StatefulNavigationShell.maybeOf(context);
  final router = GoRouter.of(context);
  final query = ref.read(searchQueryProvider.notifier);
  final lookup = ref.read(artistLookupProvider);
  final id = browseId ?? (track == null ? null : await lookup.forTrack(track));
  if (!context.mounted) return;
  if (id != null) {
    context.goYtmArtist(id);
    return;
  }
  query.set(name);
  if (shell != null) {
    goTab(shell.widget, _searchTab);
  } else {
    router.go('/search');
  }
}
