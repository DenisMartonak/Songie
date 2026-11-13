import 'dart:async';

import '../core/log.dart';
import '../core/result.dart';
import '../data/database.dart';
import '../friends/friends_backend.dart' show FriendsException;
import '../library/library_repository.dart';
import '../room/room_protocol.dart' show RoomSong;
import '../room/room_songs.dart' show roomSongOf;
import 'sharing_backend.dart';

/// Playlist sharing: shares this account's playlists (and keeps their
/// snapshots current), follows others' (and keeps those current), and copies.
class PlaylistSharing {
  PlaylistSharing({
    required this._backend,
    required this._library,
    required this._tracksFor,
    this.every = const Duration(minutes: 15),
    this.settle = const Duration(seconds: 3),
  });

  /// How long an owner's edits settle before the snapshot goes out.
  final Duration settle;

  final SharingBackend _backend;
  final LibraryRepository _library;
  final Future<List<Track?>> Function(List<RoomSong>) _tracksFor;

  /// How often followed playlists are checked while signed in.
  final Duration every;

  bool _running = false;
  Timer? _timer;
  StreamSubscription<List<Playlist>>? _sharedSub;
  final _trackSubs = <String, StreamSubscription<Object?>>{};
  final _debounces = <String, Timer>{};

  // --- owner -------------------------------------------------------------------

  Future<(String, List<RoomSong>)> _snapshot(String playlistId) async {
    final p = await _library.playlistById(playlistId);
    final tracks = await _library.watchPlaylistTracks(playlistId).first;
    final songs = [
      for (final t in tracks)
        if (roomSongOf(t.track) case final s when s.videoId != null) s,
    ];
    return (p?.name ?? '', songs);
  }

  /// How many of [playlistId]'s songs are from the user's own files (never
  /// shared).
  Future<int> localCount(String playlistId) async {
    final tracks = await _library.watchPlaylistTracks(playlistId).first;
    return tracks.where((t) => roomSongOf(t.track).videoId == null).length;
  }

  /// Shares [playlistId] and returns its code; already shared, its code.
  Future<String> share(String playlistId) async {
    final existing = (await _library.playlistById(playlistId))?.shareCode;
    if (existing != null) return existing;
    final (name, songs) = await _snapshot(playlistId);
    final code = await _backend.share(name, songs);
    await _library.setShareCode(playlistId, code);
    return code;
  }

  /// Stops sharing [playlistId]: its link stops working, followers keep
  /// their copy.
  Future<void> stopSharing(String playlistId) async {
    final code = (await _library.playlistById(playlistId))?.shareCode;
    if (code == null) return;
    await _backend.stop(code);
    await _library.setShareCode(playlistId, null);
  }

  Future<void> _publish(String playlistId) async {
    final code = (await _library.playlistById(playlistId))?.shareCode;
    if (code == null || !_running) return;
    final (name, songs) = await _snapshot(playlistId);
    try {
      await _backend.update(code, name, songs);
    } on FriendsException catch (e) {
      AppLog.w('sharing: publishing failed (${e.error.name})');
    }
  }

  void _schedulePublish(String playlistId) {
    _debounces[playlistId]?.cancel();
    _debounces[playlistId] = Timer(
      settle,
      () => unawaited(_publish(playlistId)),
    );
  }

  /// Follows each shared playlist's songs and name; a change goes out after
  /// [settle]. The first sight of each is compared with the server's copy,
  /// so an edit made while it couldn't publish goes out now.
  void _watchShared(List<Playlist> shared) {
    final ids = {for (final p in shared) p.id};
    for (final id in [..._trackSubs.keys]) {
      if (!ids.contains(id)) {
        unawaited(_trackSubs.remove(id)!.cancel());
        _debounces.remove(id)?.cancel();
      }
    }
    for (final p in shared) {
      if (_trackSubs.containsKey(p.id)) continue;
      var first = true;
      _trackSubs[p.id] = _library.watchPlaylistTracks(p.id).listen((_) {
        if (first) {
          first = false;
          unawaited(_publishIfDifferent(p.id, p.shareCode!));
        } else {
          _schedulePublish(p.id);
        }
      });
    }
  }

  Future<void> _publishIfDifferent(String playlistId, String code) async {
    try {
      final remote = await _backend.get(code);
      final (name, songs) = await _snapshot(playlistId);
      if (remote == null) return;
      final same =
          remote.name == name &&
          remote.songs.length == songs.length &&
          [
            for (var i = 0; i < songs.length; i++)
              remote.songs[i].videoId == songs[i].videoId,
          ].every((x) => x);
      if (!same) await _publish(playlistId);
    } on FriendsException catch (e) {
      AppLog.w('sharing: checking a share failed (${e.error.name})');
    }
  }

  // --- follower ----------------------------------------------------------------

  /// What the link [code] shares; null when it's gone.
  Future<SharedPlaylist?> preview(String code) => _backend.get(code);

  /// Follows the share [code] and returns the playlist's id (an existing
  /// one when already followed); null when the share is gone.
  Future<String?> follow(String code) async {
    for (final p in await _library.followedPlaylists()) {
      if (p.followCode == code) return p.id;
    }
    final shared = await _backend.get(code);
    if (shared == null) return null;
    final created = await _library.createFollowedPlaylist(
      code: code,
      name: shared.name,
      owner: shared.ownerName,
    );
    final id = switch (created) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError(failure.message),
    };
    await _apply(id, shared);
    return id;
  }

  Future<void> _apply(String playlistId, SharedPlaylist shared) async {
    final tracks = await _tracksFor(shared.songs);
    await _library.applySnapshot(
      playlistId,
      name: shared.name,
      trackIds: [for (final t in tracks) ?t?.id],
      updatedAt: shared.updatedAt,
    );
  }

  /// Checks followed playlists ([playlistId] only, when given): a newer
  /// snapshot is applied, a gone share ends the follow (the songs stay).
  Future<void> refresh([String? playlistId]) async {
    for (final p in await _library.followedPlaylists()) {
      if (playlistId != null && p.id != playlistId) continue;
      final code = p.followCode!;
      try {
        final shared = await _backend.get(code);
        if (shared == null) {
          await _library.endFollow(p.id);
          continue;
        }
        // Applied only when it differs from what the playlist has: an
        // unchanged share is not written (and synced) again. Compared by
        // content, not time (the library keeps whole seconds).
        if (!await _matches(p, shared)) await _apply(p.id, shared);
      } on FriendsException catch (e) {
        AppLog.w(
          'sharing: refreshing a followed playlist failed (${e.error.name})',
        );
      }
    }
  }

  /// Whether followed playlist [p] already has [shared]'s name and songs.
  Future<bool> _matches(Playlist p, SharedPlaylist shared) async {
    if (p.name != shared.name) return false;
    final have = [
      for (final t in await _library.watchPlaylistTracks(p.id).first)
        t.track.ytVideoId,
    ];
    final want = [for (final s in shared.songs) s.videoId];
    if (have.length != want.length) return false;
    for (var i = 0; i < have.length; i++) {
      if (have[i] != want[i]) return false;
    }
    return true;
  }

  /// Stops following [playlistId]: it leaves the library.
  Future<void> stopFollowing(String playlistId) =>
      _library.deletePlaylist(playlistId);

  /// A new, editable playlist with the songs of the share [code] or of the
  /// playlist [playlistId]; returns its id.
  Future<String> copy({String? code, String? playlistId}) async {
    final String name;
    final List<String> trackIds;
    if (code != null) {
      final shared = await _backend.get(code);
      if (shared == null) throw StateError('share $code is gone');
      name = shared.name;
      trackIds = [for (final t in await _tracksFor(shared.songs)) ?t?.id];
    } else {
      final p = await _library.playlistById(playlistId!);
      name = p?.name ?? 'Playlist';
      trackIds = [
        for (final t in await _library.watchPlaylistTracks(playlistId).first)
          t.track.id,
      ];
    }
    final created = await _library.createPlaylist(name);
    final id = switch (created) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError(failure.message),
    };
    await _library.addTracks(id, trackIds);
    return id;
  }

  // --- lifecycle -----------------------------------------------------------------

  /// Starts keeping shares and follows current (signed in).
  void signedIn() {
    if (_running) return;
    _running = true;
    _sharedSub = _library.watchSharedPlaylists().listen(_watchShared);
    _timer = Timer.periodic(every, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void signedOut() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_sharedSub?.cancel());
    _sharedSub = null;
    for (final s in _trackSubs.values) {
      unawaited(s.cancel());
    }
    _trackSubs.clear();
    for (final t in _debounces.values) {
      t.cancel();
    }
    _debounces.clear();
  }

  void dispose() => signedOut();
}
