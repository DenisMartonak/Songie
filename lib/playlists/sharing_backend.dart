import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../friends/friends_backend.dart' show FriendsRpc, guardFriendsCall;
import '../room/room_protocol.dart' show RoomSong;

/// A shared playlist as anyone with its code sees it.
@immutable
class SharedPlaylist {
  const SharedPlaylist({
    required this.name,
    required this.ownerName,
    required this.songs,
    required this.updatedAt,
    required this.isMine,
  });

  final String name;

  /// The owner's username.
  final String ownerName;

  /// Its YouTube songs, in order.
  final List<RoomSong> songs;
  final DateTime updatedAt;

  /// Whether the signed-in account shared it.
  final bool isMine;
}

/// The shared playlists on the server
/// (`supabase/migrations/20261116120000_playlist_sharing.sql`). Failures are
/// `FriendsException`s.
abstract interface class SharingBackend {
  /// Shares a snapshot; returns its code.
  Future<String> share(String name, List<RoomSong> songs);

  /// Replaces the snapshot of a share this account owns.
  Future<void> update(String code, String name, List<RoomSong> songs);

  /// Stops a share this account owns; an unknown code is fine.
  Future<void> stop(String code);

  /// The share [code]; null when it's unknown or stopped.
  Future<SharedPlaylist?> get(String code);
}

class SupabaseSharingBackend implements SharingBackend {
  /// [client] is read only when a call is made.
  SupabaseSharingBackend(SupabaseClient Function() client)
    : _rpc = ((fn, params) => client().rpc<dynamic>(fn, params: params));

  @visibleForTesting
  SupabaseSharingBackend.withRpc(this._rpc);

  final FriendsRpc _rpc;

  static List<Object?> _json(List<RoomSong> songs) => [
    for (final s in songs) s.toJson(),
  ];

  @override
  Future<String> share(String name, List<RoomSong> songs) => guardFriendsCall(
    () async =>
        await _rpc('share_playlist', {'p_name': name, 'p_songs': _json(songs)})
            as String,
  );

  @override
  Future<void> update(String code, String name, List<RoomSong> songs) =>
      guardFriendsCall(
        () => _rpc('update_shared_playlist', {
          'p_code': code,
          'p_name': name,
          'p_songs': _json(songs),
        }),
      );

  @override
  Future<void> stop(String code) =>
      guardFriendsCall(() => _rpc('stop_sharing_playlist', {'p_code': code}));

  @override
  Future<SharedPlaylist?> get(String code) => guardFriendsCall(() async {
    final rows = await _rpc('get_shared_playlist', {'p_code': code});
    if (rows is! List || rows.isEmpty) return null;
    final r = rows.first as Map;
    final songs = r['songs'];
    return SharedPlaylist(
      name: r['name'] as String? ?? '',
      ownerName: r['owner_name'] as String? ?? '',
      songs: [
        if (songs is List)
          for (final s in songs) ?RoomSong.fromJson(s),
      ],
      updatedAt:
          DateTime.tryParse(r['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      isMine: r['is_mine'] == true,
    );
  });
}
