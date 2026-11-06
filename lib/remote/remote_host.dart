import 'dart:async';
import 'dart:math';

import '../core/log.dart';
import '../data/database.dart';
import '../player/player_service.dart';
import 'remote_channel.dart';
import 'remote_protocol.dart';

/// Publishes this device's [PlayerService] on the remote channel and applies
/// the commands addressed to it. Runs on every signed-in device.
///
/// Commands are applied one at a time, in arrival order (a command waiting
/// for unknown ids holds the ones after it). Queue edits by index act only
/// when both the controller's epoch and the id it saw at that index still
/// match; otherwise nothing changes and fresh state goes out.
class RemoteHost {
  RemoteHost({
    required this._channel,
    required this._player,
    required this._presence,
    required this._lookup,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const Duration debounce = Duration(milliseconds: 250);
  static const Duration heartbeat = Duration(seconds: 5);
  static const Duration retryEvery = Duration(milliseconds: 500);
  static const Duration retryFor = Duration(seconds: 5);

  /// How far the position may stray from where playback alone would have
  /// taken it (since the previous player state, by the wall clock) before it
  /// counts as a seek worth a state message. Covers engine tick jitter.
  static const Duration seekTolerance = Duration(milliseconds: 400);

  final RemoteChannel _channel;
  final PlayerService _player;
  final RemotePresence Function(PlayerState s) _presence;
  final Future<Map<String, Track>> Function(List<String> ids) _lookup;
  final int Function() _nowMs;

  String? _me;
  bool _running = false;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  Timer? _debounce;
  Timer? _heartbeat;
  Future<void> _tail = Future<void>.value();

  PlayerState? _last;
  int _lastAtMs = 0;
  bool? _presencePlaying;
  String? _presenceTrack;

  Future<void> start() async {
    if (_running) return;
    final s = _player.state;
    final RemotePresence me;
    try {
      me = _presence(s);
    } on Object catch (e, st) {
      // Stay stopped; a later start() can try again.
      AppLog.w('remote host: presence failed, not starting', e, st);
      return;
    }
    _running = true;
    _me = me.deviceId;
    _last = s;
    _lastAtMs = _nowMs();
    _presencePlaying = s.playing;
    _presenceTrack = s.current?.id;
    _stateSub = _player.states.listen(_onPlayer);
    _messageSub = _channel.messages.listen(_onMessage);
    if (s.playing) _armHeartbeat();
    try {
      await _channel.join(me);
    } on Object catch (e, st) {
      AppLog.w('remote host: join failed', e, st);
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _debounce?.cancel();
    _debounce = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    // Not awaited: nothing depends on it, and [_running] already makes the
    // listeners inert.
    unawaited(_stateSub?.cancel());
    unawaited(_messageSub?.cancel());
    _stateSub = null;
    _messageSub = null;
    try {
      await _channel.leave();
    } on Object catch (e, st) {
      AppLog.w('remote host: leave failed', e, st);
    }
  }

  // --- player side ---------------------------------------------------------

  void _onPlayer(PlayerState s) {
    if (!_running) return;
    try {
      final previous = _last;
      final now = _nowMs();
      final elapsed = Duration(milliseconds: now - _lastAtMs);
      _last = s;
      _lastAtMs = now;
      final trackId = s.current?.id;
      if (s.playing != _presencePlaying || trackId != _presenceTrack) {
        _presencePlaying = s.playing;
        _presenceTrack = trackId;
        unawaited(_updatePresence(s));
      }
      if (!s.playing) {
        _heartbeat?.cancel();
        _heartbeat = null;
      } else if (_heartbeat == null) {
        _armHeartbeat();
      }
      if (previous == null || _differs(previous, s, elapsed)) _schedule();
    } on Object catch (e, st) {
      AppLog.w('remote host: player change failed', e, st);
    }
  }

  Future<void> _updatePresence(PlayerState s) async {
    try {
      await _channel.updatePresence(_presence(s));
    } on Object catch (e, st) {
      AppLog.w('remote host: presence update failed', e, st);
    }
  }

  /// Whether [b], [elapsed] after [a], says something a controller can't
  /// work out from [a]: position ticks and buffer progress are left to its
  /// own clock, but a seek (any jump away from where playback would be) is
  /// not.
  static bool _differs(PlayerState a, PlayerState b, Duration elapsed) {
    if (!identical(a.queue, b.queue)) {
      if (a.queue.length != b.queue.length) return true;
      for (var i = 0; i < a.queue.length; i++) {
        if (a.queue[i].id != b.queue[i].id) return true;
      }
    }
    final advancing = a.playing && !a.buffering;
    final expected = a.position + (advancing ? elapsed : Duration.zero);
    final jump = (b.position - expected).abs();
    return a.index != b.index ||
        a.playing != b.playing ||
        a.buffering != b.buffering ||
        a.duration != b.duration ||
        a.volume != b.volume ||
        a.shuffle != b.shuffle ||
        a.repeat != b.repeat ||
        a.notice != b.notice ||
        jump > seekTolerance;
  }

  // --- sending -------------------------------------------------------------

  /// Sends state within [debounce], at most once per [debounce].
  void _schedule() {
    if (!_running || _debounce != null) return;
    _debounce = Timer(debounce, () {
      _debounce = null;
      unawaited(_sendState());
    });
  }

  void _armHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer(heartbeat, () {
      _heartbeat = null;
      unawaited(_sendState());
    });
  }

  bool get _othersPresent => _channel.present.any((p) => p.deviceId != _me);

  /// Sends state now (only while another device is present, unless
  /// [always]) and restarts the heartbeat while playing.
  Future<void> _sendState({bool always = false}) async {
    if (!_running) return;
    _debounce?.cancel();
    _debounce = null;
    try {
      if (_player.state.playing) {
        _armHeartbeat();
      } else {
        _heartbeat?.cancel();
        _heartbeat = null;
      }
      if (!always && !_othersPresent) return;
      await _channel.send(_build());
    } on Object catch (e, st) {
      AppLog.w('remote host: sending state failed', e, st);
    }
  }

  RemoteState _build() {
    final s = _player.state;
    final len = s.queue.length;
    final offset = max(
      0,
      min(s.index - kRemoteQueueWindow ~/ 2, len - kRemoteQueueWindow),
    );
    final end = min(len, offset + kRemoteQueueWindow);
    final notice = s.notice;
    return RemoteState(
      from: _me!,
      // The epoch of the queue in this snapshot, not one still waiting to
      // land, so a controller never pairs a new epoch with old indexes.
      epoch: _player.stateEpoch,
      offset: offset,
      index: s.index,
      queue: [for (var i = offset; i < end; i++) s.queue[i].id],
      playing: s.playing,
      buffering: s.buffering,
      shuffle: s.shuffle,
      positionMs: s.position.inMilliseconds,
      atMs: _nowMs(),
      durationMs: s.duration?.inMilliseconds,
      volume: s.volume,
      repeat: s.repeat,
      notice: notice == null
          ? null
          : (title: notice.trackTitle, reason: notice.reason),
    );
  }

  // --- commands ------------------------------------------------------------

  void _onMessage(RemoteMessage m) {
    if (!_running) return;
    try {
      switch (m) {
        case RemoteHello(:final to) when to == _me:
          unawaited(_sendState(always: true));
        case RemoteCommand(:final to) when to == _me:
          _tail = _tail.then((_) => _run(m));
        default:
          break;
      }
    } on Object catch (e, st) {
      AppLog.w('remote host: message failed', e, st);
    }
  }

  Future<void> _run(RemoteCommand c) async {
    if (!_running) return;
    try {
      await _apply(c);
    } on Object catch (e, st) {
      AppLog.w('remote host: command ${c.op.name} failed', e, st);
    }
    // Every command is answered: a no-op or failure corrects the
    // controller's optimistic view; a change is reported anyway.
    _schedule();
  }

  Future<void> _apply(RemoteCommand c) async {
    final a = c.args;
    final p = _player;
    // Present for playAt/remove/move (decode requires it there).
    final epoch = c.epoch ?? -1;
    switch (c.op) {
      case RemoteOp.play:
        await p.play();
      case RemoteOp.pause:
        await p.pause();
      case RemoteOp.toggle:
        await p.togglePlay();
      case RemoteOp.next:
        await p.next();
      case RemoteOp.previous:
        await p.previous();
      case RemoteOp.seek:
        await p.seek(Duration(milliseconds: a['ms']! as int));
      case RemoteOp.volume:
        await p.setVolume((a['v']! as num).toDouble());
      case RemoteOp.shuffle:
        p.setShuffle(a['on']! as bool);
      case RemoteOp.repeat:
        final mode = RepeatMode.values.byName(a['mode']! as String);
        for (var i = 0; i < RepeatMode.values.length; i++) {
          if (p.state.repeat == mode) break;
          p.cycleRepeat();
        }
      // Checked by the player when the edit's turn comes (inside its lock),
      // so an edit still queued there can't shift the index under it. On a
      // mismatch nothing changes; fresh state follows as for any command.
      case RemoteOp.playAt:
        await p.playAtIf(a['index']! as int, a['track']! as String, epoch);
      case RemoteOp.remove:
        await p.removeAtIf(a['index']! as int, a['track']! as String, epoch);
      case RemoteOp.move:
        p.moveIf(
          a['from']! as int,
          a['to']! as int,
          a['track']! as String,
          epoch,
        );
      case RemoteOp.playTracks:
        await _playTracks(
          a['ids']! as List<String>,
          a['start']! as int,
          a['playlist'] as String?,
        );
      case RemoteOp.addNext:
        final tracks = await _tracks(a['ids']! as List<String>);
        if (_running && tracks.isNotEmpty) await p.addToQueue(tracks);
      case RemoteOp.addToEnd:
        final tracks = await _tracks(a['ids']! as List<String>);
        if (_running && tracks.isNotEmpty) await p.appendToQueue(tracks);
    }
  }

  Future<void> _playTracks(
    List<String> ids,
    int start,
    String? playlist,
  ) async {
    if (start < 0 || start >= ids.length) return;
    final found = await _lookupAll(ids);
    if (!_running) return;
    final tracks = <Track>[];
    int? startAt;
    for (var i = 0; i < ids.length; i++) {
      final t = found[ids[i]];
      if (t == null) continue;
      if (i >= start) startAt ??= tracks.length;
      tracks.add(t);
    }
    if (startAt == null) return;
    await _player.playQueue(
      tracks,
      startIndex: startAt,
      sourcePlaylistId: playlist,
    );
  }

  Future<List<Track>> _tracks(List<String> ids) async {
    final found = await _lookupAll(ids);
    return [
      for (final id in ids)
        if (found[id] != null) found[id]!,
    ];
  }

  /// Looks [ids] up, retrying the unknown ones every [retryEvery] for up to
  /// [retryFor] (a song the controller just stored may not have synced yet).
  /// A lookup that throws counts as finding nothing on that try.
  Future<Map<String, Track>> _lookupAll(List<String> ids) async {
    final want = ids.toSet();
    final found = <String, Track>{};
    final tries = retryFor.inMilliseconds ~/ retryEvery.inMilliseconds;
    for (var attempt = 0; ; attempt++) {
      final missing = [
        for (final id in want)
          if (!found.containsKey(id)) id,
      ];
      try {
        final got = await _lookup(missing);
        for (final id in missing) {
          final t = got[id];
          if (t != null) found[id] = t;
        }
      } on Object catch (e, st) {
        // A transient failure (e.g. the database busy): keep retrying.
        AppLog.w('remote host: lookup failed (try ${attempt + 1})', e, st);
      }
      if (found.length == want.length || attempt >= tries || !_running) {
        return found;
      }
      await Future<void>.delayed(retryEvery);
    }
  }
}
