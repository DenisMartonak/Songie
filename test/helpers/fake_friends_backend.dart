import 'package:songies/friends/friends_backend.dart';

/// Friendships in memory, following the server's rules
/// (`supabase/migrations/20261114120000_friends.sql`). [me] is the signed-in
/// account; tests switch it to act as someone else.
class FakeFriendsBackend implements FriendsBackend {
  /// Everyone with a profile, by id.
  final users = <String, FriendUser>{};

  /// requester -> addressee -> accepted?
  final _rows = <(String, String), bool>{};

  /// Every call, by name.
  final calls = <String>[];

  /// Thrown by every call while set.
  FriendsException? error;

  String me = '';

  /// Each load waits for the first gate here, if any (taken in turn).
  final loadGates = <Future<void>>[];

  void addUser(String id, String username, {String? avatarUrl}) =>
      users[id] = FriendUser(id: id, username: username, avatarUrl: avatarUrl);

  /// Deletes an account: its profile and its rows.
  void deleteUser(String id) {
    users.remove(id);
    _rows.removeWhere((k, _) => k.$1 == id || k.$2 == id);
  }

  void _check() {
    final e = error;
    if (e != null) throw e;
  }

  (String, String)? _pair(String a, String b) {
    if (_rows.containsKey((a, b))) return (a, b);
    if (_rows.containsKey((b, a))) return (b, a);
    return null;
  }

  @override
  Future<List<FriendRow>> load(String me) async {
    calls.add('load');
    _check();
    // What the server holds when asked, delivered once the gate opens.
    final rows = _rowsFor(me);
    if (loadGates.isNotEmpty) await loadGates.removeAt(0);
    return rows;
  }

  List<FriendRow> _rowsFor(String me) {
    return [
      for (final MapEntry(key: (requester, addressee), value: accepted)
          in _rows.entries)
        if (requester == me || addressee == me)
          if (users[requester == me ? addressee : requester] case final u?)
            FriendRow(
              user: u,
              link: accepted
                  ? FriendLink.friend
                  : requester == me
                  ? FriendLink.outgoing
                  : FriendLink.incoming,
            ),
    ];
  }

  @override
  Future<List<FriendUser>> search(String me, String query) async {
    calls.add('search');
    _check();
    final q = query.toLowerCase();
    final found =
        users.values
            .where((u) => u.id != me && u.username.startsWith(q))
            .toList()
          ..sort((a, b) => a.username.compareTo(b.username));
    return found.take(20).toList();
  }

  @override
  Future<FriendLink?> send(String other) async {
    calls.add('send');
    _check();
    if (other == me) throw const FriendsException(FriendsError.selfRequest);
    if (!users.containsKey(other)) {
      throw const FriendsException(FriendsError.unknownUser);
    }
    final pair = _pair(me, other);
    if (pair == null) {
      _rows[(me, other)] = false;
      return FriendLink.outgoing;
    }
    if (!_rows[pair]! && pair.$2 == me) {
      _rows[pair] = true;
      return FriendLink.friend;
    }
    return _rows[pair]! ? FriendLink.friend : FriendLink.outgoing;
  }

  @override
  Future<void> accept(String other) async {
    calls.add('accept');
    _check();
    if (_rows[(other, me)] != false) {
      throw const FriendsException(FriendsError.notRequested);
    }
    _rows[(other, me)] = true;
  }

  @override
  Future<void> remove(String other) async {
    calls.add('remove');
    _check();
    final pair = _pair(me, other);
    if (pair != null) _rows.remove(pair);
  }
}
