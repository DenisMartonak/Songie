import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/log.dart';
import 'friends_backend.dart';

/// The signed-in user's friends and requests, as last loaded.
@immutable
class FriendsState {
  const FriendsState({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.loaded = false,
  });

  /// Nothing loaded (signed out, or not yet).
  static const empty = FriendsState();

  final List<FriendUser> friends;

  /// Requests waiting for the user.
  final List<FriendUser> incoming;

  /// Requests the user sent.
  final List<FriendUser> outgoing;
  final bool loaded;

  FriendLink? linkOf(String userId) {
    bool has(List<FriendUser> l) => l.any((u) => u.id == userId);
    if (has(friends)) return FriendLink.friend;
    if (has(incoming)) return FriendLink.incoming;
    if (has(outgoing)) return FriendLink.outgoing;
    return null;
  }
}

/// Keeps [FriendsState] for the signed-in account: loads on sign-in, again
/// every [every] and after each change, and clears on sign-out. Changes go
/// to the server; their failures are rethrown as [FriendsException]s.
class FriendsService {
  FriendsService(this._backend, {this.every = const Duration(minutes: 5)});

  final FriendsBackend _backend;
  final Duration every;

  final _states = StreamController<FriendsState>.broadcast();
  FriendsState _state = FriendsState.empty;
  String? _me;
  Timer? _timer;

  /// Grows on every sign-in and sign-out: a load started under an older one
  /// is dropped.
  int _session = 0;

  FriendsState get state => _state;
  Stream<FriendsState> get states => _states.stream;

  void _set(FriendsState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  Future<void> signedIn(String me) async {
    if (_me == me) return;
    _session++;
    _me = me;
    _set(FriendsState.empty);
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(_refreshQuietly()));
    await _refreshQuietly();
  }

  void signedOut() {
    _session++;
    _me = null;
    _timer?.cancel();
    _timer = null;
    _set(FriendsState.empty);
  }

  /// Loads again; a failure leaves the last state and is rethrown.
  Future<void> refresh() async {
    final me = _me;
    if (me == null) return;
    final session = _session;
    final rows = await _backend.load(me);
    if (session != _session) return;
    List<FriendUser> of(FriendLink link) => [
      for (final r in rows)
        if (r.link == link) r.user,
    ]..sort((a, b) => a.username.compareTo(b.username));
    _set(
      FriendsState(
        friends: of(FriendLink.friend),
        incoming: of(FriendLink.incoming),
        outgoing: of(FriendLink.outgoing),
        loaded: true,
      ),
    );
  }

  Future<void> _refreshQuietly() async {
    try {
      await refresh();
    } on FriendsException catch (e) {
      AppLog.w('friends: refresh failed (${e.error.name})');
    }
  }

  /// Users whose name starts with [query]; none under 2 letters.
  Future<List<FriendUser>> search(String query) async {
    final me = _me;
    final q = query.trim();
    if (me == null || q.length < 2) return const [];
    return _backend.search(me, q);
  }

  Future<void> send(String userId) => _change(() => _backend.send(userId));
  Future<void> accept(String userId) => _change(() => _backend.accept(userId));
  Future<void> remove(String userId) => _change(() => _backend.remove(userId));

  Future<void> _change(Future<Object?> Function() call) async {
    if (_me == null) return;
    await call();
    await _refreshQuietly();
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_states.close());
  }
}
