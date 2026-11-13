import 'package:songies/friends/friends_backend.dart';
import 'package:songies/playlists/sharing_backend.dart';
import 'package:songies/room/room_protocol.dart';

/// Shared playlists in memory, following the server's rules
/// (`supabase/migrations/20261116120000_playlist_sharing.sql`). [me] is who
/// acts; [names] are usernames by user id.
class FakeSharingBackend implements SharingBackend {
  FakeSharingBackend({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;
  final _shares = <String, _Share>{};
  final calls = <String>[];
  final names = <String, String>{};
  Object? error;
  String me = '';
  var _next = 0;

  void _check() {
    final e = error;
    if (e != null) throw e;
  }

  /// Codes in use, for tests.
  Iterable<String> get codes => _shares.keys;

  @override
  Future<String> share(String name, List<RoomSong> songs) async {
    calls.add('share');
    _check();
    final code = 'ABCDEFGH${(2345 + _next++).toString().padLeft(4, '2')}'
        .replaceAll('0', 'A')
        .replaceAll('1', 'B');
    _shares[code] = _Share(me, name, songs, now());
    return code;
  }

  @override
  Future<void> update(String code, String name, List<RoomSong> songs) async {
    calls.add('update');
    _check();
    final s = _shares[code];
    if (s == null || s.owner != me) {
      throw const FriendsException(FriendsError.notOwner);
    }
    _shares[code] = _Share(me, name, songs, now());
  }

  @override
  Future<void> stop(String code) async {
    calls.add('stop');
    _check();
    final s = _shares[code];
    if (s == null) return;
    if (s.owner != me) throw const FriendsException(FriendsError.notOwner);
    _shares.remove(code);
  }

  @override
  Future<SharedPlaylist?> get(String code) async {
    calls.add('get');
    _check();
    final s = _shares[code];
    if (s == null) return null;
    return SharedPlaylist(
      name: s.name,
      ownerName: names[s.owner] ?? '',
      songs: s.songs,
      updatedAt: s.updatedAt,
      isMine: s.owner == me,
    );
  }
}

class _Share {
  _Share(this.owner, this.name, this.songs, this.updatedAt);
  final String owner;
  final String name;
  final List<RoomSong> songs;
  final DateTime updatedAt;
}
