import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../core/log.dart';
import '../data/database.dart';
import '../player/player_service.dart';
import 'remote_channel.dart';
import 'remote_protocol.dart';

/// The `source` of the placeholder [Track] shown for a queue id this device
/// doesn't have (P5).
const kRemoteUnknownSource = 'remote';

enum RemoteLinkStatus { connecting, connected, lost }

/// The device being controlled and how the link to it stands.
class RemoteLink {
  const RemoteLink(this.device, this.status);

  final RemotePresence device;
  final RemoteLinkStatus status;

  @override
  String toString() => 'RemoteLink(${device.deviceId}, ${status.name})';
}

/// Why a link ended (the view goes back to This device).
enum RemoteEndReason { deselected, noAnswer, lost, signedOut }

/// Controls another device: while one is selected, holds its latest state
/// as a [PlayerState] the player UI can show, runs the position on between
/// state messages and sends commands, updating [state] at once where it can
/// guess the outcome. The next state from the host replaces the guess.
///
/// Indexes passed to [playAt], [removeAt] and [move] are relative to the
/// window of the queue the host sent ([state]`.queue`); they are made
/// absolute before sending.
class RemoteController {
  RemoteController({
    required this._channel,
    required this._deviceId,
    required this._lookup,
    int Function()? nowMs,
    String Function()? newId,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _newId = newId ?? (() => const Uuid().v4());

  static const Duration helloTimeout = Duration(seconds: 5);
  static const Duration lostTimeout = Duration(seconds: 15);
  static const Duration tick = Duration(milliseconds: 250);

  /// The most a state's `at_ms` may lie behind this device's clock and
  /// still count as transit time; beyond it (or ahead of it) the clocks
  /// disagree and the position runs on from when the state arrived.
  static const int _maxLagMs = 2000;

  final RemoteChannel _channel;
  final String _deviceId;
  final Future<Map<String, Track>> Function(List<String> ids) _lookup;
  final int Function() _nowMs;
  final String Function() _newId;

  final _links = StreamController<RemoteLink?>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  final _ended = StreamController<RemoteEndReason>.broadcast();

  RemoteLink? _link;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<List<RemotePresence>>? _presenceSub;
  Timer? _helloTimer;
  Timer? _lostTimer;
  Timer? _ticker;

  /// Bumped on every state received and on every link change, so a lookup
  /// that finishes late can tell it has been overtaken.
  int _generation = 0;

  /// The last state the host sent (for its epoch and window offset).
  RemoteState? _remote;

  /// The view, with [PlayerState.position] as of [_viewAtMs] (local clock).
  PlayerState _view = const PlayerState();
  int _viewAtMs = 0;

  /// Tracks of the current window this device has, by id.
  Map<String, Track> _known = const {};

  Stream<RemoteLink?> get links => _links.stream;
  RemoteLink? get link => _link;

  Stream<PlayerState> get states => _states.stream;
  Stream<RemoteEndReason> get ended => _ended.stream;

  /// The view now, the position run on while the host plays.
  PlayerState get state {
    if (!_advancing) return _view;
    final elapsed = max(0, _nowMs() - _viewAtMs);
    return _view.copyWith(
      position: _capped(
        _view.position + Duration(milliseconds: elapsed),
        _view.duration,
      ),
    );
  }

  bool get _advancing =>
      _link?.status == RemoteLinkStatus.connected &&
      _view.playing &&
      !_view.buffering;

  static Duration _capped(Duration p, Duration? duration) =>
      duration != null && p > duration ? duration : p;

  // --- link ----------------------------------------------------------------

  /// Starts controlling [device]: asks it for its state and waits up to
  /// [helloTimeout] for it.
  /// This device itself can't be selected.
  Future<void> select(RemotePresence device) async {
    if (device.deviceId == _deviceId) return;
    _teardown();
    _setLink(RemoteLink(device, RemoteLinkStatus.connecting));
    _messageSub = _channel.messages.listen(_onMessage);
    _presenceSub = _channel.presences.listen(_onPresences);
    await _hello();
  }

  /// Stops controlling; [ended] reports [reason]. Nothing happens without a
  /// link.
  void deselect([RemoteEndReason reason = RemoteEndReason.deselected]) {
    if (_link == null) return;
    _teardown();
    _setLink(null);
    if (!_ended.isClosed) _ended.add(reason);
  }

  /// Ends any link without reporting it and closes the streams.
  void dispose() {
    _teardown();
    _link = null;
    _links.close();
    _states.close();
    _ended.close();
  }

  void _teardown() {
    _generation++;
    _helloTimer?.cancel();
    _helloTimer = null;
    _lostTimer?.cancel();
    _lostTimer = null;
    _ticker?.cancel();
    _ticker = null;
    unawaited(_messageSub?.cancel());
    unawaited(_presenceSub?.cancel());
    _messageSub = null;
    _presenceSub = null;
    _remote = null;
    _view = const PlayerState();
    _viewAtMs = 0;
    _known = const {};
  }

  void _setLink(RemoteLink? l) {
    _link = l;
    if (!_links.isClosed) _links.add(l);
    _syncTicker();
  }

  void _setStatus(RemoteLinkStatus status) {
    final l = _link;
    if (l == null || l.status == status) return;
    _setLink(RemoteLink(l.device, status));
  }

  Future<void> _hello() async {
    final l = _link;
    if (l == null) return;
    _helloTimer?.cancel();
    _helloTimer = Timer(helloTimeout, () {
      _helloTimer = null;
      deselect(RemoteEndReason.noAnswer);
    });
    await _send(RemoteHello(to: l.device.deviceId));
  }

  void _onPresences(List<RemotePresence> list) {
    try {
      final l = _link;
      if (l == null) return;
      RemotePresence? found;
      for (final p in list) {
        if (p.deviceId == l.device.deviceId) found = p;
      }
      if (found == null) {
        if (l.status == RemoteLinkStatus.lost) return;
        _freeze();
        _helloTimer?.cancel();
        _helloTimer = null;
        _lostTimer = Timer(lostTimeout, () {
          _lostTimer = null;
          deselect(RemoteEndReason.lost);
        });
        _setStatus(RemoteLinkStatus.lost);
        _emit();
      } else {
        // Follow name or title changes without announcing them.
        _link = RemoteLink(found, l.status);
        if (l.status != RemoteLinkStatus.lost) return;
        _lostTimer?.cancel();
        _lostTimer = null;
        _setStatus(RemoteLinkStatus.connecting);
        unawaited(_hello());
      }
    } on Object catch (e, s) {
      AppLog.w('remote controller: presence failed', e, s);
    }
  }

  // --- state ---------------------------------------------------------------

  void _onMessage(RemoteMessage m) {
    try {
      final l = _link;
      if (l == null) return;
      if (m is RemoteState && m.from == l.device.deviceId) {
        unawaited(_onState(m));
      }
    } on Object catch (e, s) {
      AppLog.w('remote controller: message failed', e, s);
    }
  }

  Future<void> _onState(RemoteState s) async {
    try {
      final generation = ++_generation;
      final arrivedMs = _nowMs();
      final missing = <String>{
        for (final id in s.queue)
          if (!_known.containsKey(id)) id,
      }.toList();
      var found = const <String, Track>{};
      if (missing.isNotEmpty) {
        try {
          found = await _lookup(missing);
        } on Object catch (e, st) {
          AppLog.w('remote controller: lookup failed', e, st);
        }
        if (generation != _generation || _link == null) return;
      }
      final known = <String, Track>{};
      final queue = <Track>[];
      for (final id in s.queue) {
        final t = _known[id] ?? found[id];
        if (t != null) known[id] = t;
        queue.add(t ?? _unknown(id));
      }
      _known = known;
      _remote = s;

      final advancing = s.playing && !s.buffering;
      var lag = arrivedMs - s.atMs;
      if (lag < 0 || lag > _maxLagMs) lag = 0;
      final duration = s.durationMs == null
          ? null
          : Duration(milliseconds: s.durationMs!);
      final index = s.index < 0 ? -1 : s.index - s.offset;
      final notice = s.notice;
      _view = PlayerState(
        queue: List.unmodifiable(queue),
        index: index >= 0 && index < queue.length ? index : -1,
        playing: s.playing,
        buffering: s.buffering,
        position: _capped(
          Duration(milliseconds: s.positionMs + (advancing ? lag : 0)),
          duration,
        ),
        duration: duration,
        shuffle: s.shuffle,
        repeat: s.repeat,
        volume: s.volume,
        notice: notice == null
            ? null
            : PlayerNotice(trackTitle: notice.title, reason: notice.reason),
      );
      _viewAtMs = arrivedMs;
      if (_link?.status == RemoteLinkStatus.connecting) {
        _helloTimer?.cancel();
        _helloTimer = null;
        _setStatus(RemoteLinkStatus.connected);
      }
      _emit();
    } on Object catch (e, st) {
      AppLog.w('remote controller: state failed', e, st);
    }
  }

  static Track _unknown(String id) => Track(
    id: id,
    clock: '',
    originDevice: '',
    deleted: false,
    localSeq: 0,
    source: kRemoteUnknownSource,
    title: 'Unknown song',
    artist: '',
    durationMs: 0,
    unavailable: false,
    searchText: '',
  );

  /// Pins the run-on position into the view, as of now.
  void _freeze() {
    _view = state;
    _viewAtMs = _nowMs();
  }

  void _emit() {
    _syncTicker();
    if (!_states.isClosed) _states.add(state);
  }

  void _syncTicker() {
    if (!_advancing) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      _ticker ??= Timer.periodic(tick, (_) {
        if (!_states.isClosed) _states.add(state);
      });
    }
  }

  /// Applies an optimistic change to the view (as of now) and shows it.
  void _guess(PlayerState Function(PlayerState s) change) {
    _freeze();
    _view = change(_view);
    _emit();
  }

  // --- commands ------------------------------------------------------------

  Future<void> _send(RemoteMessage m) async {
    try {
      await _channel.send(m);
    } on Object catch (e, s) {
      AppLog.w('remote controller: send failed', e, s);
    }
  }

  Future<void> _command(
    RemoteOp op, [
    Map<String, Object?> args = const {},
    int? epoch,
  ]) async {
    final l = _link;
    if (l == null) return;
    await _send(
      RemoteCommand(
        to: l.device.deviceId,
        id: _newId(),
        op: op,
        args: args,
        epoch: epoch,
      ),
    );
  }

  static Duration? _durationOf(Track t) =>
      t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null;

  /// The view moved to window entry [i] from its start.
  static PlayerState _startAt(PlayerState s, int i) => s.copyWith(
    index: i,
    position: Duration.zero,
    duration: _durationOf(s.queue[i]),
  );

  Future<void> play() {
    if (_link == null) return Future.value();
    _guess((s) => s.copyWith(playing: true));
    return _command(RemoteOp.play);
  }

  Future<void> pause() {
    if (_link == null) return Future.value();
    _guess((s) => s.copyWith(playing: false));
    return _command(RemoteOp.pause);
  }

  Future<void> togglePlay() {
    if (_link == null) return Future.value();
    _guess((s) => s.copyWith(playing: !s.playing));
    return _command(RemoteOp.toggle);
  }

  Future<void> next() {
    if (_link == null) return Future.value();
    final s = _view;
    if (s.index >= 0 && s.index + 1 < s.queue.length) {
      _guess((s) => _startAt(s, s.index + 1));
    }
    return _command(RemoteOp.next);
  }

  Future<void> previous() {
    if (_link == null) return Future.value();
    final s = _view;
    if (s.index > 0 && s.index < s.queue.length) {
      _guess((s) => _startAt(s, s.index - 1));
    }
    return _command(RemoteOp.previous);
  }

  Future<void> seek(Duration d) {
    if (_link == null) return Future.value();
    final p = d.isNegative ? Duration.zero : d;
    _guess((s) => s.copyWith(position: _capped(p, s.duration)));
    return _command(RemoteOp.seek, {'ms': p.inMilliseconds});
  }

  Future<void> setVolume(double volume) {
    if (_link == null || volume.isNaN) return Future.value();
    final v = volume.clamp(0.0, 1.0);
    _guess((s) => s.copyWith(volume: v));
    return _command(RemoteOp.volume, {'v': v});
  }

  Future<void> setShuffle(bool on) {
    if (_link == null) return Future.value();
    _guess((s) => s.copyWith(shuffle: on));
    return _command(RemoteOp.shuffle, {'on': on});
  }

  Future<void> setRepeat(RepeatMode mode) {
    if (_link == null) return Future.value();
    _guess((s) => s.copyWith(repeat: mode));
    return _command(RemoteOp.repeat, {'mode': mode.name});
  }

  /// Plays window entry [index].
  Future<void> playAt(int index) {
    final r = _remote;
    final q = _view.queue;
    if (_link == null || r == null || index < 0 || index >= q.length) {
      return Future.value();
    }
    final id = q[index].id;
    _guess((s) => _startAt(s, index).copyWith(playing: true));
    return _command(RemoteOp.playAt, {
      'index': r.offset + index,
      'track': id,
    }, r.epoch);
  }

  /// Removes window entry [index].
  Future<void> removeAt(int index) {
    final r = _remote;
    final q = _view.queue;
    if (_link == null || r == null || index < 0 || index >= q.length) {
      return Future.value();
    }
    final id = q[index].id;
    _guess((s) {
      final queue = [...s.queue]..removeAt(index);
      final current = s.index;
      if (index != current) {
        return s.copyWith(
          queue: List.unmodifiable(queue),
          index: index < current ? current - 1 : current,
        );
      }
      // The current one goes: the next takes its place (as on the host).
      final i = min(current, queue.length - 1);
      return s.copyWith(
        queue: List.unmodifiable(queue),
        index: i,
        position: Duration.zero,
        duration: i < 0 ? null : _durationOf(queue[i]),
      );
    });
    return _command(RemoteOp.remove, {
      'index': r.offset + index,
      'track': id,
    }, r.epoch);
  }

  /// Moves window entry [from] to window position [to].
  Future<void> move(int from, int to) {
    final r = _remote;
    final n = _view.queue.length;
    if (_link == null ||
        r == null ||
        from < 0 ||
        from >= n ||
        to < 0 ||
        to >= n) {
      return Future.value();
    }
    final id = _view.queue[from].id;
    _guess((s) {
      final queue = [...s.queue];
      final order = [for (var i = 0; i < n; i++) i];
      queue.insert(to, queue.removeAt(from));
      order.insert(to, order.removeAt(from));
      return s.copyWith(
        queue: List.unmodifiable(queue),
        index: s.index < 0 ? -1 : order.indexOf(s.index),
      );
    });
    return _command(RemoteOp.move, {
      'from': r.offset + from,
      'to': r.offset + to,
      'track': id,
    }, r.epoch);
  }

  /// Plays [ids] on the host from [startIndex]; the view follows its state.
  Future<void> playTracks(
    List<String> ids, {
    int startIndex = 0,
    String? sourcePlaylistId,
  }) {
    if (ids.isEmpty) return Future.value();
    return _command(RemoteOp.playTracks, {
      'ids': ids,
      'start': startIndex,
      'playlist': sourcePlaylistId,
    });
  }

  Future<void> addNext(List<String> ids) {
    if (ids.isEmpty) return Future.value();
    return _command(RemoteOp.addNext, {'ids': ids});
  }

  Future<void> addToEnd(List<String> ids) {
    if (ids.isEmpty) return Future.value();
    return _command(RemoteOp.addToEnd, {'ids': ids});
  }
}
