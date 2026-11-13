import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;

import '../core/log.dart';
import '../data/database.dart';
import '../player/player_service.dart';
import 'room_channel.dart';
import 'room_protocol.dart';
import 'room_songs.dart';

/// Something that happened in the room, for the host's UI to show.
sealed class RoomHostEvent {
  const RoomHostEvent();
}

class GuestJoined extends RoomHostEvent {
  const GuestJoined(this.name);
  final String name;
}

class GuestLeft extends RoomHostEvent {
  const GuestLeft(this.name);
  final String name;
}

class GuestAdded extends RoomHostEvent {
  const GuestAdded(this.name, this.title);
  final String name;
  final String title;
}

/// Runs a room: owns its one queue (the host's [PlayerService]), broadcasts
/// the room state while a guest is present and applies guests' requests after
/// checking their role. Requests are applied one at a time, in arrival order.
///
/// The server cannot say who sent a message, so a request's `from` is
/// trusted, but only from a device currently in Presence.
class RoomHost {
  RoomHost({
    required this._channel,
    required this._player,
    required this._me,
    required this._tracksFor,
    this._removeMember,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const Duration debounce = Duration(milliseconds: 250);
  static const Duration heartbeat = Duration(seconds: 2);
  static const Duration seekTolerance = Duration(milliseconds: 400);

  final RoomChannel _channel;
  final PlayerService _player;
  final RoomPresence _me;
  final Future<List<Track?>> Function(List<RoomSong>) _tracksFor;
  final Future<void> Function(String userId)? _removeMember;
  final int Function() _nowMs;

  final _roles = <String, RoomRole>{};
  final _events = StreamController<RoomHostEvent>.broadcast();
  final _people = StreamController<List<RoomPresence>>.broadcast();

  bool _running = false;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<RoomMessage>? _messageSub;
  StreamSubscription<List<RoomPresence>>? _presenceSub;
  Timer? _debounce;
  Timer? _heartbeat;
  Future<void> _tail = Future<void>.value();
  var _known = <String, RoomPresence>{};
  PlayerState? _last;
  int _lastAtMs = 0;

  /// The window last sent in full, and its revision: a send whose window is
  /// the same can be a [RoomBeatMsg].
  int _rev = 0;
  int? _sentEpoch;
  int _sentOffset = 0;
  List<Track> _sentWindow = const [];
  List<String> _sentBys = const [];
  Map<String, RoomFace> _sentFaces = const {};

  /// Everyone who has been in this room, the host included, by user id:
  /// their songs keep their face after they leave.
  late final _faces = <String, RoomFace>{
    _me.userId: RoomFace(name: _me.name, avatarUrl: _me.avatarUrl),
  };
  final _facesChanges = StreamController<Map<String, RoomFace>>.broadcast();

  Map<String, RoomRole> get roles => Map.unmodifiable(_roles);
  Stream<RoomHostEvent> get events => _events.stream;
  Stream<List<RoomPresence>> get people => _people.stream;

  /// See [_faces].
  Map<String, RoomFace> get faces => Map.unmodifiable(_faces);
  Stream<Map<String, RoomFace>> get facesChanges => _facesChanges.stream;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final s = _player.state;
    _last = s;
    _lastAtMs = _nowMs();
    _stateSub = _player.states.listen(_onPlayer);
    _messageSub = _channel.messages.listen(_onMessage);
    _presenceSub = _channel.presences.listen(_onPresence);
    if (s.playing) _armHeartbeat();
    try {
      await _channel.join(_me);
    } on Object catch (e, st) {
      AppLog.w('room host: join failed', e, st);
    }
  }

  /// Stops hosting; with [end] the guests are told the room is over.
  Future<void> stop({bool end = true}) async {
    if (!_running) return;
    _running = false;
    _debounce?.cancel();
    _debounce = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    unawaited(_stateSub?.cancel());
    unawaited(_messageSub?.cancel());
    unawaited(_presenceSub?.cancel());
    _stateSub = _messageSub = _presenceSub = null;
    try {
      if (end) await _channel.send(const RoomEndMsg());
      await _channel.leave();
    } on Object catch (e, st) {
      AppLog.w('room host: stop failed', e, st);
    }
  }

  Future<void> setRole(String deviceId, RoomRole role) async {
    _roles[deviceId] = role;
    await _sendRoles();
  }

  /// Kicks [guest] and removes its account from the room, unless another
  /// present device (the host's included) is the same account.
  Future<void> removeGuest(RoomPresence guest) async {
    _roles.remove(guest.deviceId);
    try {
      await _channel.send(RoomKickMsg(deviceId: guest.deviceId));
    } on Object catch (e, st) {
      AppLog.w('room host: kick failed', e, st);
    }
    final shared =
        guest.userId == _me.userId ||
        _channel.present.any(
          (p) => p.deviceId != guest.deviceId && p.userId == guest.userId,
        );
    if (shared) return;
    try {
      await _removeMember?.call(guest.userId);
    } on Object catch (e, st) {
      AppLog.w('room host: removing member failed', e, st);
    }
  }

  // --- presence ------------------------------------------------------------

  bool get _guestPresent =>
      _channel.present.any((p) => p.deviceId != _me.deviceId);

  void _onPresence(List<RoomPresence> list) {
    if (!_running) return;
    // A list without this device is the host's own connection dropping (the
    // channel then reports nobody): no one left, and the list that comes
    // back with it is compared with the one before.
    if (!list.any((p) => p.deviceId == _me.deviceId)) return;
    try {
      final now = {for (final p in list) p.deviceId: p};
      for (final p in now.values) {
        if (p.deviceId != _me.deviceId && !_known.containsKey(p.deviceId)) {
          _events.add(GuestJoined(p.name));
        }
      }
      for (final p in _known.values) {
        if (p.deviceId != _me.deviceId && !now.containsKey(p.deviceId)) {
          _events.add(GuestLeft(p.name));
        }
      }
      _known = now;
      var changed = false;
      for (final p in list) {
        changed = _noteFace(p) || changed;
      }
      if (changed) {
        _facesChanges.add(faces);
        // A face in the window may have changed: guests get it now.
        _schedule();
      }
      _people.add(list);
    } on Object catch (e, st) {
      AppLog.w('room host: presence failed', e, st);
    }
  }

  /// Records [p]'s face; whether it is new or changed.
  bool _noteFace(RoomPresence p) {
    final face = RoomFace(name: p.name, avatarUrl: p.avatarUrl);
    if (_faces[p.userId] == face) return false;
    _faces[p.userId] = face;
    return true;
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
      if (!s.playing) {
        _heartbeat?.cancel();
        _heartbeat = null;
      } else if (_heartbeat == null) {
        _armHeartbeat();
      }
      if (previous == null || _differs(previous, s, elapsed)) _schedule();
    } on Object catch (e, st) {
      AppLog.w('room host: player change failed', e, st);
    }
  }

  static bool _differs(PlayerState a, PlayerState b, Duration elapsed) {
    if (!identical(a.queue, b.queue)) {
      if (a.queue.length != b.queue.length) return true;
      for (var i = 0; i < a.queue.length; i++) {
        if (a.queue[i].id != b.queue[i].id) return true;
      }
    }
    final advancing = a.playing && !a.buffering;
    final expected = a.position + (advancing ? elapsed : Duration.zero);
    return a.index != b.index ||
        a.playing != b.playing ||
        a.buffering != b.buffering ||
        a.duration != b.duration ||
        a.shuffle != b.shuffle ||
        a.repeat != b.repeat ||
        (b.position - expected).abs() > seekTolerance;
  }

  // --- sending -------------------------------------------------------------

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
      if (!always && !_guestPresent) return;
      await _channel.send(_build(full: always));
    } on Object catch (e, st) {
      AppLog.w('room host: sending state failed', e, st);
    }
  }

  Future<void> _sendRoles() async {
    try {
      await _channel.send(RoomRolesMsg(roles: Map.of(_roles)));
    } on Object catch (e, st) {
      AppLog.w('room host: sending roles failed', e, st);
    }
  }

  /// Every guest present follows beats (none is an older build).
  bool get _guestsTakeBeats =>
      _channel.present.every((p) => p.deviceId == _me.deviceId || p.beats);

  /// The state to send: a beat while the window is the one last sent in
  /// full and every guest takes beats, else the full state ([full] forces
  /// it, as for a hello).
  RoomMessage _build({bool full = false}) {
    final s = _player.state;
    final len = s.queue.length;
    final offset = max(
      0,
      min(s.index - kRoomQueueWindow ~/ 2, len - kRoomQueueWindow),
    );
    final end = min(len, offset + kRoomQueueWindow);
    final epoch = _player.stateEpoch;
    final window = s.queue.sublist(offset, end);
    // An untagged entry is the host's own.
    final bys = [
      for (var i = offset; i < end; i++)
        s.addedBy.elementAtOrNull(i) ?? _me.userId,
    ];
    final windowFaces = {for (final id in bys) id: ?_faces[id]};
    final same =
        epoch == _sentEpoch &&
        offset == _sentOffset &&
        _sameTracks(window, _sentWindow) &&
        listEquals(bys, _sentBys) &&
        mapEquals(windowFaces, _sentFaces);
    if (same && !full && _guestsTakeBeats) {
      return RoomBeatMsg(
        rev: _rev,
        index: s.index,
        playing: s.playing,
        positionMs: s.position.inMilliseconds,
        durationMs: s.duration?.inMilliseconds,
        shuffle: s.shuffle,
        repeat: s.repeat,
      );
    }
    if (!same) {
      _rev++;
      _sentEpoch = epoch;
      _sentOffset = offset;
      _sentWindow = window;
      _sentBys = bys;
      _sentFaces = windowFaces;
    }
    return RoomStateMsg(
      rev: _rev,
      epoch: epoch,
      songs: [
        for (var i = 0; i < window.length; i++)
          roomSongOf(window[i], by: bys[i]),
      ],
      faces: windowFaces,
      offset: offset,
      index: s.index,
      playing: s.playing,
      positionMs: s.position.inMilliseconds,
      durationMs: s.duration?.inMilliseconds,
      shuffle: s.shuffle,
      repeat: s.repeat,
    );
  }

  static bool _sameTracks(List<Track> a, List<Track> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // --- requests ------------------------------------------------------------

  void _onMessage(RoomMessage m) {
    if (!_running) return;
    try {
      switch (m) {
        case RoomHelloMsg():
          unawaited(_answerHello());
        case RoomRequestMsg():
          _tail = _tail.then((_) => _run(m));
        default:
          break;
      }
    } on Object catch (e, st) {
      AppLog.w('room host: message failed', e, st);
    }
  }

  Future<void> _answerHello() async {
    await _sendRoles();
    await _sendState(always: true);
  }

  RoomPresence? _presentDevice(String id) {
    for (final p in _channel.present) {
      if (p.deviceId == id) return p;
    }
    return null;
  }

  Future<void> _run(RoomRequestMsg r) async {
    if (!_running) return;
    final who = _presentDevice(r.from);
    if (who == null || who.deviceId == _me.deviceId) return;
    if (!roleAllows(_roles[r.from] ?? RoomRole.listener, r.op)) return;
    try {
      await _apply(r, who);
    } on Object catch (e, st) {
      AppLog.w('room host: request ${r.op.name} failed', e, st);
    }
    // Every allowed request is answered: a no-op or failure corrects the
    // guest's view; a change is reported anyway.
    _schedule();
  }

  /// The queue entry at [index] if its video id is [videoId] (both null for a
  /// local song), else null.
  Track? _seen(Object? index, Object? videoId) {
    final q = _player.state.queue;
    if (index is! int || index < 0 || index >= q.length) return null;
    final t = q[index];
    return t.ytVideoId == videoId ? t : null;
  }

  Future<void> _apply(RoomRequestMsg r, RoomPresence who) async {
    final a = r.args;
    final p = _player;
    final epoch = r.epoch ?? -1;
    switch (r.op) {
      case RoomOp.play:
        await p.play();
      case RoomOp.pause:
        await p.pause();
      case RoomOp.toggle:
        await p.togglePlay();
      case RoomOp.next:
        await p.next();
      case RoomOp.previous:
        await p.previous();
      case RoomOp.seek:
        final ms = a['positionMs'];
        if (ms is int) await p.seek(Duration(milliseconds: ms));
      case RoomOp.shuffle:
        final on = a['on'];
        if (on is bool) p.setShuffle(on);
      case RoomOp.repeat:
        RepeatMode? mode;
        for (final m in RepeatMode.values) {
          if (m.name == a['mode']) mode = m;
        }
        if (mode == null) return;
        for (var i = 0; i < RepeatMode.values.length; i++) {
          if (p.state.repeat == mode) break;
          p.cycleRepeat();
        }
      case RoomOp.playAt:
        final t = _seen(a['index'], a['videoId']);
        if (t != null) await p.playAtIf(a['index']! as int, t.id, epoch);
      case RoomOp.remove:
        final t = _seen(a['index'], a['videoId']);
        if (t != null) await p.removeAtIf(a['index']! as int, t.id, epoch);
      case RoomOp.move:
        final from = a['from'];
        final to = a['to'];
        final t = _seen(from, a['videoId']);
        if (t != null && to is int) p.moveIf(from! as int, to, t.id, epoch);
      case RoomOp.playSongs:
        final songs = _songsOf(a['songs']);
        final start = a['startIndex'];
        if (songs == null || start is! int) return;
        if (start < 0 || start >= songs.length) return;
        final tracks = await _tracksFor(songs);
        if (!_running) return;
        final out = <Track>[];
        int? startAt;
        for (var i = 0; i < tracks.length; i++) {
          final t = tracks[i];
          if (t == null) continue;
          if (i >= start) startAt ??= out.length;
          out.add(t);
        }
        if (startAt == null) return;
        await p.playQueue(
          out,
          startIndex: startAt,
          addedBy: List.filled(out.length, who.userId),
        );
      case RoomOp.addNext:
      case RoomOp.addToEnd:
        final songs = _songsOf(a['songs']);
        if (songs == null || songs.isEmpty) return;
        final tracks = [for (final t in await _tracksFor(songs)) ?t];
        if (!_running || tracks.isEmpty) return;
        final by = List<String?>.filled(tracks.length, who.userId);
        if (r.op == RoomOp.addNext) {
          await p.addToQueue(tracks, addedBy: by);
        } else {
          await p.appendToQueue(tracks, addedBy: by);
        }
        _events.add(GuestAdded(who.name, songs.first.title));
    }
  }

  static List<RoomSong>? _songsOf(Object? o) {
    if (o is! List) return null;
    final out = <RoomSong>[];
    for (final e in o) {
      final s = RoomSong.fromJson(e);
      if (s == null) return null;
      out.add(s);
    }
    return out;
  }
}
