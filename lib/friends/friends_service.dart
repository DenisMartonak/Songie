import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/log.dart';
import 'activity_backend.dart';
import 'friends_backend.dart';

/// The signed-in user's friends and requests, as last loaded.
@immutable
class FriendsState {
  const FriendsState({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.activity = const {},
    this.loaded = false,
  });

  /// Nothing loaded (signed out, or not yet).
  static const empty = FriendsState();

  final List<FriendUser> friends;

  /// Requests waiting for the user.
  final List<FriendUser> incoming;

  /// Requests the user sent.
  final List<FriendUser> outgoing;

  /// What each friend shares, by user id.
  final Map<String, FriendActivity> activity;
  final bool loaded;

  /// Whether friend [userId] is listening to something, as of [now].
  bool listening(String userId, DateTime now) =>
      activity[userId]?.listeningAt(now) ?? false;

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
  FriendsService(
    this._backend, {
    this._activity,
    this.every = const Duration(minutes: 5),
    this.closely = const Duration(minutes: 1),
  });

  final FriendsBackend _backend;
  final ActivityBackend? _activity;
  final Duration every;

  /// How often it refreshes while a page watches closely.
  final Duration closely;
  final _watchers = <Object>{};
  Timer? _closeTimer;

  final _states = StreamController<FriendsState>.broadcast();
  FriendsState _state = FriendsState.empty;
  String? _me;
  Timer? _timer;

  /// Grows on every sign-in and sign-out: a load started under an older one
  /// is dropped.
  int _session = 0;

  /// Numbers loads as they start; one that lands after a newer one was
  /// applied is dropped (it holds older rows).
  int _loads = 0;
  int _applied = 0;

  FriendsState get state => _state;

  /// The current state, then each change (subscribed at once, so none is
  /// missed in between).
  Stream<FriendsState> get states => Stream<FriendsState>.multi((c) {
    c.add(_state);
    final sub = _states.stream.listen(c.add, onDone: c.close);
    c.onCancel = sub.cancel;
  });

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
    final load = ++_loads;
    final rows = await _backend.load(me);
    var activity = _state.activity;
    final source = _activity;
    if (source != null) {
      try {
        activity = await source.friendActivity();
      } on FriendsException catch (e) {
        // The friends still update; their activity stays as it was.
        AppLog.w('friends: activity failed (${e.error.name})');
      }
    }
    if (session != _session || load < _applied) return;
    _applied = load;
    List<FriendUser> of(FriendLink link) =>
        [
          for (final r in rows)
            if (r.link == link) r.user,
        ]..sort(
          (a, b) =>
              a.username.toLowerCase().compareTo(b.username.toLowerCase()),
        );
    _set(
      FriendsState(
        friends: of(FriendLink.friend),
        incoming: of(FriendLink.incoming),
        outgoing: of(FriendLink.outgoing),
        activity: activity,
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

  /// Refreshes every [closely] until [stopWatching] is called with the
  /// returned token (a page showing friends' activity).
  Object watchClosely() {
    final token = Object();
    _watchers.add(token);
    _closeTimer ??= Timer.periodic(
      closely,
      (_) => unawaited(_refreshQuietly()),
    );
    return token;
  }

  void stopWatching(Object token) {
    _watchers.remove(token);
    if (_watchers.isEmpty) {
      _closeTimer?.cancel();
      _closeTimer = null;
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
    _closeTimer?.cancel();
    unawaited(_states.close());
  }
}
