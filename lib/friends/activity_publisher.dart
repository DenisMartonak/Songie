import 'dart:async';

import '../core/log.dart';
import '../player/player_service.dart';
import 'activity_backend.dart';
import 'friends_backend.dart' show FriendsException;

/// Publishes what this account plays now (and the room it hosts) and its top
/// 10, for friends to see, as the account's sharing switches allow. Runs
/// while signed in.
class ActivityPublisher {
  ActivityPublisher({
    required this._backend,
    required this._states,
    required this._current,
    required this._roomCode,
    required this._roomChanges,
    required this._top,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long a change settles before it is published.
  static const Duration settle = Duration(seconds: 2);

  /// How often a song still playing is published again (so it stays fresh)
  /// and the top 10 is checked.
  static const Duration every = Duration(minutes: 5);

  /// How often the top 10 is published at most.
  static const Duration topEvery = Duration(hours: 1);

  final ActivityBackend _backend;
  final Stream<PlayerState> _states;
  final PlayerState Function() _current;
  final String? Function() _roomCode;
  final Stream<Object?> _roomChanges;
  final Future<TopSummary?> Function() _top;
  final DateTime Function() _now;

  bool _running = false;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _debounce;
  Timer? _tick;
  DateTime? _topAt;

  /// What was last published (or scheduled): song id, playing, room code.
  (String?, bool, String?)? _published;

  /// The account's switches, as the server last said.
  Sharing sharing = Sharing.on;

  Future<void> signedIn() async {
    if (_running) return;
    _running = true;
    _subs
      ..add(_states.listen((_) => _changed()))
      ..add(_roomChanges.listen((_) => _changed()));
    _tick = Timer.periodic(every, (_) => unawaited(_onTick()));
    try {
      sharing = await _backend.mySharing();
    } on FriendsException catch (e) {
      AppLog.w('activity: sharing unknown (${e.error.name})');
    }
    if (!_running) return;
    _changed();
    await _publishTop();
  }

  /// Stops, clearing what this account plays now on the server first.
  Future<void> signedOut() async {
    if (!_running) return;
    _stop();
    if (!sharing.listening) return;
    try {
      await _backend.publishNowPlaying(null);
    } on FriendsException catch (e) {
      AppLog.w('activity: clearing failed (${e.error.name})');
    }
  }

  /// Saves the switches given (the others stay as they are); turned back
  /// on, what plays goes out again. The top 10 goes out in the background.
  Future<void> setSharing({bool? listening, bool? top}) async {
    await _backend.setSharing(listening: listening, top: top);
    sharing = Sharing(
      listening: listening ?? sharing.listening,
      top: top ?? sharing.top,
    );
    if (!_running) return;
    _published = null;
    if (listening == true) _changed();
    if (top == true) {
      _topAt = null;
      unawaited(_publishTop());
    }
  }

  void _stop() {
    _running = false;
    _debounce?.cancel();
    _tick?.cancel();
    _debounce = _tick = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _published = null;
  }

  (String?, bool, String?) _key() {
    final s = _current();
    final playing = s.playing && s.current != null;
    return (playing ? s.current!.id : null, playing, _roomCode());
  }

  void _changed() {
    if (!_running || !sharing.listening) return;
    if (_key() == _published) return;
    _published = _key();
    _debounce?.cancel();
    _debounce = Timer(settle, () => unawaited(_publishNow()));
  }

  Future<void> _publishNow() async {
    if (!_running || !sharing.listening) return;
    final s = _current();
    final t = s.playing ? s.current : null;
    _published = _key();
    try {
      await _backend.publishNowPlaying(
        t == null
            ? null
            : NowPlaying(
                title: t.title,
                artist: t.artist,
                videoId: t.source == 'yt' ? t.ytVideoId : null,
              ),
        roomCode: _roomCode(),
      );
    } on FriendsException catch (e) {
      // Tried again at the next change or tick.
      _published = null;
      AppLog.w('activity: publishing failed (${e.error.name})');
    }
  }

  Future<void> _onTick() async {
    if (!_running) return;
    if (_current().playing) await _publishNow();
    await _publishTop();
  }

  Future<void> _publishTop() async {
    if (!_running || !sharing.top) return;
    final at = _topAt;
    if (at != null && _now().difference(at) < topEvery) return;
    _topAt = _now();
    try {
      final top = await _top();
      if (top == null || !_running || !sharing.top) return;
      await _backend.publishTop(top);
    } on FriendsException catch (e) {
      _topAt = null;
      AppLog.w('activity: top failed (${e.error.name})');
    } catch (e) {
      // Working it out failed (the stats): tried again within the hour.
      _topAt = null;
      AppLog.w('activity: top failed (${e.runtimeType})');
    }
  }

  void dispose() => _stop();
}
