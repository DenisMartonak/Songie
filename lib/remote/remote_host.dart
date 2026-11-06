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

  /// A position change larger than this between two player states is a
  /// seek (worth a state message), not playback ticking along.
  static const Duration _seekJump = Duration(seconds: 2);

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
  bool? _presencePlaying;
  String? _presenceTrack;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final s = _player.state;
    final me = _presence(s);
    _me = me.deviceId;
    _last = s;
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
      _last = s;
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
      if (previous == null || _differs(previous, s)) _schedule();
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

  /// Whether [b] says something a controller can't work out from [a]
  /// (position ticks and buffer progress are left to its own clock).
  static bool _differs(PlayerState a, PlayerState b) {
    if (!identical(a.queue, b.queue)) {
      if (a.queue.length != b.queue.length) return true;
      for (var i = 0; i < a.queue.length; i++) {
        if (a.queue[i].id != b.queue[i].id) return true;
      }
    }
    final jump = (a.position - b.position).abs();
    return a.index != b.index ||
        a.playing != b.playing ||
        a.buffering != b.buffering ||
        a.duration != b.duration ||
        a.volume != b.volume ||
        a.shuffle != b.shuffle ||
        a.repeat != b.repeat ||
        a.notice != b.notice ||
        jump > _seekJump;
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
      epoch: _player.queueEpoch,
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
      case RemoteOp.playAt:
        final index = a['index']! as int;
        if (_holds(c, index)) await p.playAt(index);
      case RemoteOp.remove:
        final index = a['index']! as int;
        if (_holds(c, index)) await p.removeAt(index);
      case RemoteOp.move:
        final from = a['from']! as int;
        final to = a['to']! as int;
        if (_holds(c, from) && to >= 0 && to < p.state.queue.length) {
          p.move(from, to);
        }
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

  /// Whether the queue the controller saw is still the one playing and
  /// still has the id it saw at [index].
  bool _holds(RemoteCommand c, int index) {
    final q = _player.state.queue;
    return c.epoch == _player.queueEpoch &&
        index >= 0 &&
        index < q.length &&
        q[index].id == c.args['track'];
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
  Future<Map<String, Track>> _lookupAll(List<String> ids) async {
    final want = ids.toSet();
    final found = <String, Track>{};
    final tries = retryFor.inMilliseconds ~/ retryEvery.inMilliseconds;
    for (var attempt = 0; ; attempt++) {
      final missing = [
        for (final id in want)
          if (!found.containsKey(id)) id,
      ];
      final got = await _lookup(missing);
      for (final id in missing) {
        final t = got[id];
        if (t != null) found[id] = t;
      }
      if (found.length == want.length || attempt >= tries || !_running) {
        return found;
      }
      await Future<void>.delayed(retryEvery);
    }
  }
}
