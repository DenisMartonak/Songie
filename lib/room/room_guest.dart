import 'dart:async';
import 'dart:math';

import '../core/log.dart';
import '../data/database.dart';
import '../player/player_service.dart';
import '../remote/player_view.dart';
import 'room_channel.dart';
import 'room_protocol.dart';
import 'room_songs.dart';

/// Why a guest is no longer in the room.
enum RoomLeaveReason { left, ended, removed, hostGone, unreachable, outdated }

/// A room's guest: makes this device's [PlayerService] follow the host's
/// state and sends the guest's requests. It edits its player's queue only by
/// applying state, and when it leaves (for any reason) it leaves the player
/// as it is.
///
/// Positions are extrapolated from this device's own receive time only, never
/// from another device's clock.
class RoomGuest {
  RoomGuest({
    required this._channel,
    required this._player,
    required this._me,
    required this._tracksFor,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const Duration helloEvery = Duration(seconds: 2);
  static const Duration firstStateWait = Duration(seconds: 15);

  final RoomChannel _channel;
  final PlayerService _player;
  final RoomPresence _me;
  final Future<List<Track?>> Function(List<RoomSong>) _tracksFor;
  final DateTime Function() _now;

  final _roles = StreamController<RoomRole>.broadcast();
  final _allRoles = StreamController<Map<String, RoomRole>>.broadcast();
  final _people = StreamController<List<RoomPresence>>.broadcast();
  final _ended = StreamController<RoomLeaveReason>.broadcast();
  final _cantPlay = StreamController<String>.broadcast();

  bool _running = false;
  bool _started = false;
  RoomRole _role = RoomRole.listener;
  Map<String, RoomRole> _roleMap = const {};
  bool _hostSeen = false;
  int _requests = 0;

  StreamSubscription<RoomMessage>? _messageSub;
  StreamSubscription<List<RoomPresence>>? _presenceSub;
  StreamSubscription<PlayerState>? _playerSub;
  Timer? _hello;
  Timer? _unreachable;
  Timer? _hostGone;

  // --- applied state -------------------------------------------------------

  /// The latest state received and when (this device's clock), waiting to be
  /// applied; a newer one replaces it.
  (RoomStateMsg, DateTime)? _pending;

  /// The latest state applied (or being applied).
  (RoomStateMsg, DateTime)? _last;
  bool _applying = false;

  /// The queue the guest follows: the host's window as last loaded.
  int? _epoch;
  List<RoomSong>? _songs;
  int _offset = 0;

  /// The guest's playable tracks, and for each window position the index
  /// into them (null: not playable here).
  var _tracks = const <Track>[];
  var _map = const <int?>[];

  /// Whether the player holds [_tracks] (loaded with `playQueue`).
  bool _loaded = false;

  /// [Track.id]s this guest failed to play in this epoch.
  final _failed = <String>{};

  /// The index into [_tracks] being followed.
  int? _target;

  /// The song `cantPlay` last named, until the guest follows a song again.
  RoomSong? _shown;

  /// The player's [PlayerService.skipUnplayable] before the room.
  bool _skipBefore = true;

  /// The player notice already looked at.
  PlayerNotice? _notice;

  RoomRole get role => _role;
  Stream<RoomRole> get roles => _roles.stream;

  /// Every guest device's role as the host last sent them, by device id
  /// (a device missing from it is a listener).
  Map<String, RoomRole> get allRoles => _roleMap;
  Stream<Map<String, RoomRole>> get allRolesChanges => _allRoles.stream;
  Stream<List<RoomPresence>> get people => _people.stream;
  Stream<RoomLeaveReason> get ended => _ended.stream;

  /// The title of a host song this guest cannot play, once per song.
  Stream<String> get cantPlay => _cantPlay.stream;

  RoomPresence? get host {
    for (final p in _channel.present) {
      if (p.host && p.deviceId != _me.deviceId) return p;
    }
    return null;
  }

  Future<void> start() async {
    if (_started) return;
    _started = _running = true;
    _notice = _player.state.notice;
    // Only the host's song may be started: never a later one in its stead.
    _skipBefore = _player.skipUnplayable;
    _player.skipUnplayable = false;
    _messageSub = _channel.messages.listen(_onMessage);
    _presenceSub = _channel.presences.listen(_onPresence);
    _playerSub = _player.states.listen(_onPlayer);
    _unreachable = Timer(firstStateWait, () {
      _finish(RoomLeaveReason.unreachable);
    });
    try {
      await _player.pause();
      if (!_running) return;
      await _channel.join(_me);
      if (!_running) return;
      _hello = Timer.periodic(helloEvery, (_) => _sendHello());
      await _sendHello();
    } on Object catch (e, st) {
      AppLog.w('room guest: start failed', e, st);
    }
  }

  Future<void> leave() => _finish(RoomLeaveReason.left);

  Future<void> request(
    RoomOp op, [
    Map<String, Object?> args = const {},
    int? epoch,
  ]) async {
    if (!_running) return;
    try {
      await _channel.send(
        RoomRequestMsg(
          from: _me.deviceId,
          id:
              '${_me.deviceId}-${_now().microsecondsSinceEpoch}-'
              '${_requests++}',
          op: op,
          args: args,
          epoch: epoch,
        ),
      );
    } on Object catch (e, st) {
      AppLog.w('room guest: request ${op.name} failed', e, st);
    }
  }

  Future<void> _sendHello() async {
    if (!_running) return;
    try {
      await _channel.send(RoomHelloMsg(from: _me.deviceId));
    } on Object catch (e, st) {
      AppLog.w('room guest: hello failed', e, st);
    }
  }

  Future<void> _finish(RoomLeaveReason reason) async {
    if (!_running) return;
    _running = false;
    _hello?.cancel();
    _unreachable?.cancel();
    _hostGone?.cancel();
    _hello = _unreachable = _hostGone = null;
    _pending = null;
    unawaited(_messageSub?.cancel());
    unawaited(_presenceSub?.cancel());
    unawaited(_playerSub?.cancel());
    _messageSub = _presenceSub = null;
    _playerSub = null;
    _player.skipUnplayable = _skipBefore;
    _ended.add(reason);
    try {
      await _channel.leave();
    } on Object catch (e, st) {
      AppLog.w('room guest: leave failed', e, st);
    }
  }

  // --- channel -------------------------------------------------------------

  void _onPresence(List<RoomPresence> list) {
    if (!_running) return;
    try {
      _people.add(list);
      RoomPresence? h;
      for (final p in list) {
        if (p.host && p.deviceId != _me.deviceId) h = p;
      }
      if (h != null) {
        if (!h.compatible) {
          unawaited(_finish(RoomLeaveReason.outdated));
          return;
        }
        _hostSeen = true;
        _hostGone?.cancel();
        _hostGone = null;
      } else if (_hostSeen && _hostGone == null) {
        _hostGone = Timer(kRoomHostGrace, () {
          _finish(RoomLeaveReason.hostGone);
        });
      }
    } on Object catch (e, st) {
      AppLog.w('room guest: presence failed', e, st);
    }
  }

  void _onMessage(RoomMessage m) {
    if (!_running) return;
    try {
      switch (m) {
        case RoomStateMsg():
          _hello?.cancel();
          _hello = null;
          _unreachable?.cancel();
          _unreachable = null;
          _pending = (m, _now());
          _drain();
        case RoomRolesMsg():
          _roleMap = Map.unmodifiable(m.roles);
          _allRoles.add(_roleMap);
          final r = m.roles[_me.deviceId] ?? RoomRole.listener;
          if (r != _role) {
            _role = r;
            _roles.add(r);
          }
        case RoomKickMsg():
          if (m.deviceId == _me.deviceId) {
            unawaited(_finish(RoomLeaveReason.removed));
          }
        case RoomEndMsg():
          unawaited(_finish(RoomLeaveReason.ended));
        default:
          break;
      }
    } on Object catch (e, st) {
      AppLog.w('room guest: message failed', e, st);
    }
  }

  // --- following -----------------------------------------------------------

  /// Applies pending states one at a time.
  Future<void> _drain() async {
    if (_applying) return;
    _applying = true;
    try {
      while (_running && _pending != null) {
        final next = _pending!;
        _pending = null;
        _last = next;
        try {
          await _apply(next.$1, next.$2);
        } on Object catch (e, st) {
          AppLog.w('room guest: applying state failed', e, st);
        }
      }
    } finally {
      _applying = false;
    }
  }

  /// A notice naming the followed track means this guest failed to play it
  /// (also mid-song): mark it and apply the last state again, which pauses.
  void _onPlayer(PlayerState s) {
    if (!_running) return;
    if (_noteFailure(s)) {
      _pending ??= _last;
      unawaited(_drain());
    }
  }

  /// Whether [s] carries a new notice about the followed track.
  bool _noteFailure(PlayerState s) {
    final n = s.notice;
    if (n == null || identical(n, _notice)) return false;
    _notice = n;
    final t = _target;
    if (!_loaded || t == null || _failed.contains(_tracks[t].id)) return false;
    if (n.trackTitle != _tracks[t].title) return false;
    _failed.add(_tracks[t].id);
    return true;
  }

  static bool _sameSongs(List<RoomSong> a, List<RoomSong> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].videoId != b[i].videoId ||
          a[i].title != b[i].title ||
          a[i].artist != b[i].artist) {
        return false;
      }
    }
    return true;
  }

  bool _playerHoldsQueue() {
    final q = _player.state.queue;
    if (q.length != _tracks.length) return false;
    for (var i = 0; i < q.length; i++) {
      if (q[i].id != _tracks[i].id) return false;
    }
    return true;
  }

  Future<void> _apply(RoomStateMsg m, DateTime receivedAt) async {
    // The decoder does not bound these; nothing negative, at most a window.
    final offset = max(0, m.offset);
    final index = max(0, m.index);
    final songs = m.songs.length > kRoomQueueWindow
        ? m.songs.sublist(0, kRoomQueueWindow)
        : m.songs;

    final known = _songs;
    if (known == null || m.epoch != _epoch || !_sameSongs(songs, known)) {
      final tracks = await _tracksFor(songs);
      if (!_running) return;
      final playable = <Track>[];
      final map = <int?>[];
      for (var i = 0; i < songs.length; i++) {
        final t = i < tracks.length && !songs[i].local ? tracks[i] : null;
        if (t == null) {
          map.add(null);
        } else {
          map.add(playable.length);
          playable.add(t);
        }
      }
      final sameEpoch = m.epoch == _epoch;
      final held = _loaded && _playerHoldsQueue();
      final at = index - offset;
      final next = at >= 0 && at < map.length ? map[at] : null;
      _epoch = m.epoch;
      _songs = songs;
      _tracks = playable;
      _map = map;
      _target = null;
      if (!sameEpoch) _failed.clear();
      // The same queue edited around the song playing: swap the rest in
      // without restarting it (drift is fixed by seeking, never by a restart).
      _loaded =
          sameEpoch &&
          held &&
          next != null &&
          await _player.replaceQueueAroundCurrent(playable, next);
      if (!_running) return;
    }
    _offset = offset;
    _matchRepeat(m.repeat);

    final at = index - offset;
    final song = at >= 0 && at < songs.length ? songs[at] : null;
    final target = song == null ? null : _map[at];
    if (song == null ||
        target == null ||
        _failed.contains(_tracks[target].id)) {
      await _wait(song);
      return;
    }
    _target = target;

    if (!_loaded || !_playerHoldsQueue()) {
      if (_player.state.shuffle) _player.setShuffle(false);
      _loaded = true;
      await _player.playQueue(_tracks, startIndex: target);
      if (!_running) return;
      _checkStarted(target);
    } else if (_player.state.index != target) {
      if (_aheadAtSongEnd(m, receivedAt, target)) return;
      await _player.playAt(target);
      if (!_running) return;
      _checkStarted(target);
    }
    if (_failed.contains(_tracks[target].id)) {
      await _wait(song);
      return;
    }
    _shown = null;

    final expected = Duration(
      milliseconds:
          max(0, m.positionMs) +
          (m.playing ? _now().difference(receivedAt).inMilliseconds : 0),
    );
    if ((_player.state.position - expected).abs() > kRoomDriftLimit) {
      await _player.seek(expected);
      if (!_running) return;
    }
    if (m.playing && !_player.state.playing) {
      await _player.play();
      if (!_running) return;
      _checkStarted(target);
      if (_failed.contains(_tracks[target].id)) await _wait(song);
    } else if (!m.playing && _player.state.playing) {
      await _player.pause();
    }
  }

  /// After asking the player to start [target]: if it landed elsewhere or is
  /// not playing, this guest cannot play it.
  void _checkStarted(int target) {
    final s = _player.state;
    _noteFailure(s);
    if (s.index != target || !s.playing || s.error != null) {
      _failed.add(_tracks[target].id);
    }
  }

  /// The guest's song ended a moment before the host's and its player moved
  /// on to the next one already: leave it there.
  bool _aheadAtSongEnd(RoomStateMsg m, DateTime receivedAt, int target) {
    final duration = m.durationMs;
    if (!m.playing || duration == null) return false;
    if (_player.state.index != target + 1) return false;
    final hostAt = m.positionMs + _now().difference(receivedAt).inMilliseconds;
    return hostAt >= duration - kRoomDriftLimit.inMilliseconds;
  }

  /// The host plays something this guest cannot: stay silent until it moves
  /// on. [song] is named once.
  Future<void> _wait(RoomSong? song) async {
    if (_player.state.playing) await _player.pause();
    if (!_running || song == null || identical(_shown, song)) return;
    final shown = _shown;
    if (shown != null && _sameSongs([shown], [song])) return;
    _shown = song;
    _cantPlay.add(song.title);
  }

  void _matchRepeat(RepeatMode mode) {
    for (var i = 0; i < RepeatMode.values.length; i++) {
      if (_player.state.repeat == mode) return;
      _player.cycleRepeat();
    }
  }

  // --- for the view --------------------------------------------------------

  /// The host's queue index and video id of the guest's queue entry [i], or
  /// null when the guest's player does not hold the room's queue.
  (int, String?)? _hostEntry(int i) {
    final songs = _songs;
    if (songs == null || !_loaded || !_playerHoldsQueue()) return null;
    final at = _map.indexOf(i);
    if (at < 0) return null;
    return (_offset + at, songs[at].videoId);
  }
}

/// The player UI's view while this device is a room guest: shows the guest's
/// own player and turns commands the guest's role allows into requests.
class RoomGuestView implements PlayerView {
  RoomGuestView(this._guest);

  static const String localFilesNotice =
      "Local files can't be shared in a room";

  final RoomGuest _guest;
  final _notices = StreamController<String>.broadcast();

  PlayerService get _player => _guest._player;

  /// Messages for the user (local songs left out of a request).
  Stream<String> get notices => _notices.stream;

  @override
  Stream<PlayerState> get states => _player.states;
  @override
  PlayerState get state => _player.state;
  @override
  bool get isRemote => false;

  bool _may(RoomOp op) => roleAllows(_guest.role, op);

  Future<void> _ask(
    RoomOp op, [
    Map<String, Object?> args = const {},
    int? epoch,
  ]) async {
    if (!_may(op)) return;
    await _guest.request(op, args, epoch);
  }

  @override
  Future<void> play() => _ask(RoomOp.play);
  @override
  Future<void> pause() => _ask(RoomOp.pause);
  @override
  Future<void> togglePlay() => _ask(RoomOp.toggle);
  @override
  Future<void> next() => _ask(RoomOp.next);
  @override
  Future<void> previous() => _ask(RoomOp.previous);
  @override
  Future<void> seek(Duration d) =>
      _ask(RoomOp.seek, {'positionMs': d.inMilliseconds});
  @override
  Future<void> setVolume(double v) => _player.setVolume(v);
  @override
  Future<void> setShuffle(bool on) => _ask(RoomOp.shuffle, {'on': on});
  @override
  Future<void> setRepeat(RepeatMode m) => _ask(RoomOp.repeat, {'mode': m.name});

  @override
  Future<void> playAt(int i) => _atEntry(RoomOp.playAt, i);
  @override
  Future<void> removeAt(int i) => _atEntry(RoomOp.remove, i);

  @override
  Future<void> move(int from, int to) async {
    if (!_may(RoomOp.move)) return;
    final a = _guest._hostEntry(from);
    final b = _guest._hostEntry(to);
    if (a == null || b == null) return;
    await _guest.request(RoomOp.move, {
      'from': a.$1,
      'to': b.$1,
      'videoId': a.$2,
    }, _guest._epoch);
  }

  Future<void> _atEntry(RoomOp op, int i) async {
    if (!_may(op)) return;
    final e = _guest._hostEntry(i);
    if (e == null) return;
    await _guest.request(op, {'index': e.$1, 'videoId': e.$2}, _guest._epoch);
  }

  @override
  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    String? sourcePlaylistId,
  }) async {
    if (!_may(RoomOp.playSongs)) return;
    final songs = <Map<String, Object?>>[];
    int? start;
    for (var i = 0; i < tracks.length; i++) {
      final s = roomSongOf(tracks[i]);
      if (s.local) continue;
      if (i >= startIndex) start ??= songs.length;
      songs.add(s.toJson());
    }
    _noticeIfDropped(tracks.length, songs.length);
    if (start == null) return;
    await _guest.request(RoomOp.playSongs, {
      'songs': songs,
      'startIndex': start,
    });
  }

  @override
  Future<void> addNext(List<Track> tracks) => _add(RoomOp.addNext, tracks);
  @override
  Future<void> addToEnd(List<Track> tracks) => _add(RoomOp.addToEnd, tracks);

  Future<void> _add(RoomOp op, List<Track> tracks) async {
    if (!_may(op)) return;
    final songs = [
      for (final t in tracks)
        if (roomSongOf(t) case final s when !s.local) s.toJson(),
    ];
    _noticeIfDropped(tracks.length, songs.length);
    if (songs.isEmpty) return;
    await _guest.request(op, {'songs': songs});
  }

  void _noticeIfDropped(int asked, int kept) {
    if (kept < asked) _notices.add(localFilesNotice);
  }
}
