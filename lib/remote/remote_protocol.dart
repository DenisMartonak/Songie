import '../player/player_service.dart' show RepeatMode;

/// The wire version carried by every remote-control message.
const int kRemoteProtocol = 1;

/// The most queue ids a state message carries (around the current one).
const int kRemoteQueueWindow = 2000;

/// A device on the `remote:<user id>` channel, as tracked by Presence.
///
/// Decodes any integer `v`, so devices running another version can still be
/// listed (greyed out, see [compatible]).
class RemotePresence {
  const RemotePresence({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.playing,
    this.title,
    this.inRoom = false,
    this.v = kRemoteProtocol,
  });

  final String deviceId;
  final String name;
  final String platform;
  final String appVersion;
  final bool playing;
  final String? title;

  /// Whether the device is in a Listen together room, and so takes no
  /// remote control. Absent from older devices' payloads: false.
  final bool inRoom;
  final int v;

  bool get compatible => v == kRemoteProtocol;

  Map<String, Object?> toJson() => {
    'v': v,
    'deviceId': deviceId,
    'name': name,
    'platform': platform,
    'appVersion': appVersion,
    'playing': playing,
    'title': title,
    'inRoom': inRoom,
  };

  static RemotePresence? fromJson(Object? j) {
    try {
      if (j is! Map) return null;
      final v = j['v'];
      final deviceId = j['deviceId'];
      final name = j['name'];
      if (v is! int) return null;
      if (deviceId is! String || deviceId.isEmpty) return null;
      if (name is! String || name.isEmpty) return null;
      final platform = j['platform'];
      final appVersion = j['appVersion'];
      final playing = j['playing'];
      final title = j['title'];
      final inRoom = j['inRoom'];
      return RemotePresence(
        deviceId: deviceId,
        name: name,
        platform: platform is String ? platform : '',
        appVersion: appVersion is String ? appVersion : '',
        playing: playing is bool ? playing : false,
        title: title is String ? title : null,
        inRoom: inRoom is bool ? inRoom : false,
        v: v,
      );
    } on Object {
      return null;
    }
  }
}

/// A message on the remote channel. [decode] never throws: anything
/// malformed, of another version or of an unknown event is null.
sealed class RemoteMessage {
  const RemoteMessage();

  String get event;

  Map<String, Object?> toJson();

  static RemoteMessage? decode(String event, Object? payload) {
    try {
      if (payload is! Map) return null;
      if (payload['v'] != kRemoteProtocol) return null;
      return switch (event) {
        'state' => RemoteState._decode(payload),
        'command' => RemoteCommand._decode(payload),
        'hello' => RemoteHello._decode(payload),
        _ => null,
      };
    } on Object {
      return null;
    }
  }
}

List<String>? _strings(Object? o) {
  if (o is! List) return null;
  final out = <String>[];
  for (final e in o) {
    if (e is! String) return null;
    out.add(e);
  }
  return out;
}

/// A host's playback state, sent to the controllers.
class RemoteState extends RemoteMessage {
  const RemoteState({
    required this.from,
    required this.epoch,
    required this.offset,
    required this.index,
    required this.queue,
    required this.playing,
    required this.buffering,
    required this.shuffle,
    required this.positionMs,
    required this.atMs,
    required this.durationMs,
    required this.volume,
    required this.repeat,
    this.notice,
  });

  final String from;
  final int epoch;

  /// Absolute index of `queue[0]`.
  final int offset;

  /// Absolute index of the current track; -1 when the queue is empty.
  final int index;
  final List<String> queue;
  final bool playing;
  final bool buffering;
  final bool shuffle;
  final int positionMs;
  final int atMs;
  final int? durationMs;
  final double volume;
  final RepeatMode repeat;
  final ({String title, String reason})? notice;

  @override
  String get event => 'state';

  @override
  Map<String, Object?> toJson() => {
    'v': kRemoteProtocol,
    'from': from,
    'epoch': epoch,
    'offset': offset,
    'index': index,
    'queue': queue,
    'playing': playing,
    'buffering': buffering,
    'position_ms': positionMs,
    'at_ms': atMs,
    'duration_ms': durationMs,
    'volume': volume,
    'shuffle': shuffle,
    'repeat': repeat.name,
    'notice': notice == null
        ? null
        : {'title': notice!.title, 'reason': notice!.reason},
  };

  static RemoteState? _decode(Map<Object?, Object?> j) {
    final from = j['from'];
    final epoch = j['epoch'];
    final offset = j['offset'];
    final index = j['index'];
    final queue = _strings(j['queue']);
    final playing = j['playing'];
    final buffering = j['buffering'];
    final shuffle = j['shuffle'];
    final positionMs = j['position_ms'];
    final atMs = j['at_ms'];
    final durationMs = j['duration_ms'];
    final volume = j['volume'];
    final repeat = _repeat(j['repeat']);
    final rawNotice = j['notice'];
    ({String title, String reason})? notice;
    if (rawNotice != null) {
      if (rawNotice is! Map) return null;
      final t = rawNotice['title'];
      final r = rawNotice['reason'];
      if (t is! String || r is! String) return null;
      notice = (title: t, reason: r);
    }
    if (from is! String ||
        epoch is! int ||
        offset is! int ||
        index is! int ||
        queue == null ||
        playing is! bool ||
        buffering is! bool ||
        shuffle is! bool ||
        positionMs is! int ||
        atMs is! int ||
        (durationMs != null && durationMs is! int) ||
        volume is! num ||
        repeat == null) {
      return null;
    }
    return RemoteState(
      from: from,
      epoch: epoch,
      offset: offset,
      index: index,
      queue: queue,
      playing: playing,
      buffering: buffering,
      shuffle: shuffle,
      positionMs: positionMs,
      atMs: atMs,
      durationMs: durationMs as int?,
      volume: volume.toDouble(),
      repeat: repeat,
      notice: notice,
    );
  }
}

RepeatMode? _repeat(Object? o) {
  for (final m in RepeatMode.values) {
    if (m.name == o) return m;
  }
  return null;
}

/// What a controller asks a host to do (wire name = enum name).
enum RemoteOp {
  play,
  pause,
  toggle,
  next,
  previous,
  seek,
  volume,
  shuffle,
  repeat,
  playAt,
  remove,
  move,
  playTracks,
  addNext,
  addToEnd,
}

/// A controller's command to the device `to`.
class RemoteCommand extends RemoteMessage {
  const RemoteCommand({
    required this.to,
    required this.id,
    required this.op,
    this.args = const {},
    this.epoch,
  });

  final String to;
  final String id;
  final RemoteOp op;
  final Map<String, Object?> args;
  final int? epoch;

  @override
  String get event => 'command';

  @override
  Map<String, Object?> toJson() => {
    'v': kRemoteProtocol,
    'to': to,
    'id': id,
    'op': op.name,
    'args': args,
    if (epoch != null) 'epoch': epoch,
  };

  static RemoteCommand? _decode(Map<Object?, Object?> j) {
    final to = j['to'];
    final id = j['id'];
    final opName = j['op'];
    final rawArgs = j['args'] ?? const <String, Object?>{};
    final epoch = j['epoch'];
    if (to is! String || id is! String || opName is! String) return null;
    if (rawArgs is! Map) return null;
    if (epoch != null && epoch is! int) return null;
    RemoteOp? op;
    for (final o in RemoteOp.values) {
      if (o.name == opName) op = o;
    }
    if (op == null) return null;
    final args = <String, Object?>{
      for (final e in rawArgs.entries)
        if (e.key is String) e.key! as String: e.value,
    };
    final needsEpoch =
        op == RemoteOp.playAt || op == RemoteOp.remove || op == RemoteOp.move;
    if (needsEpoch && epoch == null) return null;
    final clean = _checkArgs(op, args);
    if (clean == null) return null;
    return RemoteCommand(
      to: to,
      id: id,
      op: op,
      args: clean,
      epoch: epoch as int?,
    );
  }

  /// The validated args for [op] (only the known keys), or null.
  static Map<String, Object?>? _checkArgs(RemoteOp op, Map<String, Object?> a) {
    switch (op) {
      case RemoteOp.seek:
        final ms = a['ms'];
        if (ms is! int || ms < 0) return null;
        return {'ms': ms};
      case RemoteOp.volume:
        final v = a['v'];
        if (v is! num || v < 0 || v > 1) return null;
        return {'v': v};
      case RemoteOp.shuffle:
        final on = a['on'];
        if (on is! bool) return null;
        return {'on': on};
      case RemoteOp.repeat:
        final mode = a['mode'];
        if (_repeat(mode) == null) return null;
        return {'mode': mode};
      case RemoteOp.playAt:
      case RemoteOp.remove:
        final index = a['index'];
        final track = a['track'];
        if (index is! int || track is! String) return null;
        return {'index': index, 'track': track};
      case RemoteOp.move:
        final from = a['from'];
        final to = a['to'];
        final track = a['track'];
        if (from is! int || to is! int || track is! String) return null;
        return {'from': from, 'to': to, 'track': track};
      case RemoteOp.playTracks:
        final ids = _strings(a['ids']);
        final start = a['start'];
        final playlist = a['playlist'];
        if (ids == null || ids.isEmpty || start is! int) return null;
        if (playlist != null && playlist is! String) return null;
        return {'ids': ids, 'start': start, 'playlist': playlist};
      case RemoteOp.addNext:
      case RemoteOp.addToEnd:
        final ids = _strings(a['ids']);
        if (ids == null || ids.isEmpty) return null;
        return {'ids': ids};
      case RemoteOp.play:
      case RemoteOp.pause:
      case RemoteOp.toggle:
      case RemoteOp.next:
      case RemoteOp.previous:
        return const {};
    }
  }
}

/// A controller asking the device `to` for its full state at once.
class RemoteHello extends RemoteMessage {
  const RemoteHello({required this.to});

  final String to;

  @override
  String get event => 'hello';

  @override
  Map<String, Object?> toJson() => {'v': kRemoteProtocol, 'to': to};

  static RemoteHello? _decode(Map<Object?, Object?> j) {
    final to = j['to'];
    if (to is! String) return null;
    return RemoteHello(to: to);
  }
}
