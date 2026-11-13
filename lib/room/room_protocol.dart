import '../player/player_service.dart' show RepeatMode;

/// The wire version carried by every room message.
const int kRoomProtocol = 1;

/// The most people (host included) in one room. The app does not enforce
/// it: the cap is `join_room`'s `>= 10` in
/// `supabase/migrations/20261109120000_listen_together.sql`, which counts
/// accounts (`room_members` rows), not devices. Change both together.
const int kRoomMaxPeople = 10;

/// The most songs a state message carries (around the current one).
const int kRoomQueueWindow = 500;

/// How long guests wait for a host that dropped before the room ends.
const Duration kRoomHostGrace = Duration(seconds: 15);

/// How far a guest may drift from the host before it seeks.
const Duration kRoomDriftLimit = Duration(milliseconds: 1000);

/// What a guest may do in the room (wire name = enum name).
enum RoomRole { listener, queue, full }

/// What a guest can ask the host to do (wire name = enum name).
enum RoomOp {
  play,
  pause,
  toggle,
  next,
  previous,
  seek,
  shuffle,
  repeat,
  playAt,
  remove,
  move,
  playSongs,
  addNext,
  addToEnd,
}

/// Whether [role] may ask for [op].
bool roleAllows(RoomRole role, RoomOp op) => switch (role) {
  RoomRole.listener => false,
  RoomRole.queue => op == RoomOp.addNext || op == RoomOp.addToEnd,
  RoomRole.full => true,
};

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// A song in a room. A null [videoId] is a local file the guests cannot play.
class RoomSong {
  const RoomSong({
    this.videoId,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.artUrl,
    this.by,
  });

  final String? videoId;
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;
  final String? artUrl;

  /// Who put it in the room's queue (a user id; see `RoomStateMsg.faces`).
  /// Hosts before it leave it out.
  final String? by;

  bool get local => videoId == null;

  Map<String, Object?> toJson() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': durationMs,
    'artUrl': artUrl,
    'by': ?by,
  };

  static RoomSong? fromJson(Object? j) {
    try {
      if (j is! Map) return null;
      final videoId = j['videoId'];
      final title = j['title'];
      final artist = j['artist'];
      final album = j['album'];
      final durationMs = j['durationMs'];
      final artUrl = j['artUrl'];
      final by = j['by'];
      if (title is! String || artist is! String) return null;
      if (videoId != null && videoId is! String) return null;
      if (album != null && album is! String) return null;
      if (durationMs != null && durationMs is! int) return null;
      if (artUrl != null && artUrl is! String) return null;
      return RoomSong(
        videoId: videoId as String?,
        title: title,
        artist: artist,
        album: album as String?,
        durationMs: durationMs as int?,
        artUrl: artUrl as String?,
        by: by is String ? by : null,
      );
    } on Object {
      return null;
    }
  }
}

List<RoomSong>? _songs(Object? o) {
  if (o is! List) return null;
  final out = <RoomSong>[];
  for (final e in o) {
    final s = RoomSong.fromJson(e);
    if (s == null) return null;
    out.add(s);
  }
  return out;
}

/// A person as shown beside the songs they added: name and picture.
class RoomFace {
  const RoomFace({required this.name, this.avatarUrl});

  final String name;

  /// The picture's public URL; null without one (the initial shows).
  final String? avatarUrl;

  Map<String, Object?> toJson() => {'name': name, 'avatarUrl': avatarUrl};

  static RoomFace? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    final avatarUrl = j['avatarUrl'];
    if (name is! String) return null;
    return RoomFace(
      name: name,
      avatarUrl: avatarUrl is String ? avatarUrl : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoomFace && other.name == name && other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(name, avatarUrl);
}

Map<String, RoomFace> _faces(Object? o) {
  if (o is! Map) return const {};
  return {
    for (final e in o.entries)
      if (e.key is String) e.key! as String: ?RoomFace.fromJson(e.value),
  };
}

/// A member of the room channel, as tracked by Presence.
///
/// Decodes any integer `v`, so a host on another version can be told apart.
class RoomPresence {
  const RoomPresence({
    required this.userId,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.host,
    this.v = kRoomProtocol,
    this.beats = true,
    this.avatarUrl,
  });

  final String userId;
  final String deviceId;
  final String name;
  final String platform;
  final bool host;
  final int v;

  /// Whether this device follows [RoomBeatMsg]s. Builds before them leave
  /// it out, and the host sends them full states only.
  final bool beats;

  /// The account's picture (public URL); null without one.
  final String? avatarUrl;

  bool get compatible => v == kRoomProtocol;

  Map<String, Object?> toJson() => {
    'v': v,
    'userId': userId,
    'deviceId': deviceId,
    'name': name,
    'platform': platform,
    'host': host,
    'beats': beats,
    'avatarUrl': ?avatarUrl,
  };

  static RoomPresence? fromJson(Object? j) {
    try {
      if (j is! Map) return null;
      final v = j['v'];
      final userId = j['userId'];
      final deviceId = j['deviceId'];
      final name = j['name'];
      final platform = j['platform'];
      final host = j['host'];
      final beats = j['beats'];
      final avatarUrl = j['avatarUrl'];
      if (v is! int) return null;
      if (userId is! String || userId.isEmpty) return null;
      if (deviceId is! String || deviceId.isEmpty) return null;
      if (name is! String) return null;
      return RoomPresence(
        userId: userId,
        deviceId: deviceId,
        name: name,
        platform: platform is String ? platform : '',
        host: host is bool ? host : false,
        v: v,
        beats: beats is bool ? beats : false,
        avatarUrl: avatarUrl is String ? avatarUrl : null,
      );
    } on Object {
      return null;
    }
  }
}

/// A message on the room channel. [decode] never throws: anything malformed,
/// of another version or of an unknown event is null.
sealed class RoomMessage {
  const RoomMessage();

  String get event;

  Map<String, Object?> toJson();

  static RoomMessage? decode(String event, Object? payload) {
    try {
      if (payload is! Map) return null;
      if (payload['v'] != kRoomProtocol) return null;
      return switch (event) {
        'state' => RoomStateMsg._decode(payload),
        'beat' => RoomBeatMsg._decode(payload),
        'roles' => RoomRolesMsg._decode(payload),
        'request' => RoomRequestMsg._decode(payload),
        'hello' => RoomHelloMsg._decode(payload),
        'kick' => RoomKickMsg._decode(payload),
        'end' => const RoomEndMsg(),
        _ => null,
      };
    } on Object {
      return null;
    }
  }
}

/// The host's playback state. [songs] is the queue window starting at
/// [offset]; [index] is into the full queue. [rev] names this window (epoch,
/// offset and songs) for the [RoomBeatMsg]s that follow; hosts before beats
/// leave it out.
class RoomStateMsg extends RoomMessage {
  const RoomStateMsg({
    this.rev,
    required this.epoch,
    required this.songs,
    required this.offset,
    required this.index,
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.shuffle,
    required this.repeat,
    this.faces = const {},
  });

  final int? rev;
  final int epoch;
  final List<RoomSong> songs;
  final int offset;
  final int index;
  final bool playing;
  final int positionMs;
  final int? durationMs;
  final bool shuffle;
  final RepeatMode repeat;

  /// Who the songs' [RoomSong.by] ids are, for the ids in [songs].
  final Map<String, RoomFace> faces;

  @override
  String get event => 'state';

  @override
  Map<String, Object?> toJson() => {
    'v': kRoomProtocol,
    'rev': ?rev,
    'epoch': epoch,
    'songs': [for (final s in songs) s.toJson()],
    'offset': offset,
    'index': index,
    'playing': playing,
    'position_ms': positionMs,
    'duration_ms': durationMs,
    'shuffle': shuffle,
    'repeat': repeat.name,
    if (faces.isNotEmpty)
      'faces': {for (final e in faces.entries) e.key: e.value.toJson()},
  };

  static RoomStateMsg? _decode(Map<Object?, Object?> j) {
    final rev = j['rev'];
    final epoch = j['epoch'];
    final songs = _songs(j['songs']);
    final offset = j['offset'];
    final index = j['index'];
    final playing = j['playing'];
    final positionMs = j['position_ms'];
    final durationMs = j['duration_ms'];
    final shuffle = j['shuffle'];
    final repeat = _byName(RepeatMode.values, j['repeat']);
    if (epoch is! int ||
        songs == null ||
        offset is! int ||
        index is! int ||
        playing is! bool ||
        positionMs is! int ||
        (durationMs != null && durationMs is! int) ||
        shuffle is! bool ||
        repeat == null) {
      return null;
    }
    return RoomStateMsg(
      rev: rev is int ? rev : null,
      epoch: epoch,
      songs: songs,
      offset: offset,
      index: index,
      playing: playing,
      positionMs: positionMs,
      durationMs: durationMs as int?,
      shuffle: shuffle,
      repeat: repeat,
      faces: _faces(j['faces']),
    );
  }
}

/// The host's playback state without its songs, while they are those of
/// the [RoomStateMsg] with the same [rev]. A guest that holds another
/// revision asks for the full state (hello). Older guests ignore it, so the
/// host sends it only when every guest present [RoomPresence.beats].
class RoomBeatMsg extends RoomMessage {
  const RoomBeatMsg({
    required this.rev,
    required this.index,
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.shuffle,
    required this.repeat,
  });

  final int rev;
  final int index;
  final bool playing;
  final int positionMs;
  final int? durationMs;
  final bool shuffle;
  final RepeatMode repeat;

  @override
  String get event => 'beat';

  @override
  Map<String, Object?> toJson() => {
    'v': kRoomProtocol,
    'rev': rev,
    'index': index,
    'playing': playing,
    'position_ms': positionMs,
    'duration_ms': durationMs,
    'shuffle': shuffle,
    'repeat': repeat.name,
  };

  /// [full]'s window with this beat's playback.
  RoomStateMsg over(RoomStateMsg full) => RoomStateMsg(
    rev: rev,
    epoch: full.epoch,
    songs: full.songs,
    offset: full.offset,
    index: index,
    playing: playing,
    positionMs: positionMs,
    durationMs: durationMs,
    shuffle: shuffle,
    repeat: repeat,
    faces: full.faces,
  );

  static RoomBeatMsg? _decode(Map<Object?, Object?> j) {
    final rev = j['rev'];
    final index = j['index'];
    final playing = j['playing'];
    final positionMs = j['position_ms'];
    final durationMs = j['duration_ms'];
    final shuffle = j['shuffle'];
    final repeat = _byName(RepeatMode.values, j['repeat']);
    if (rev is! int ||
        index is! int ||
        playing is! bool ||
        positionMs is! int ||
        (durationMs != null && durationMs is! int) ||
        shuffle is! bool ||
        repeat == null) {
      return null;
    }
    return RoomBeatMsg(
      rev: rev,
      index: index,
      playing: playing,
      positionMs: positionMs,
      durationMs: durationMs as int?,
      shuffle: shuffle,
      repeat: repeat,
    );
  }
}

/// Every guest's role, keyed by device id.
class RoomRolesMsg extends RoomMessage {
  const RoomRolesMsg({required this.roles});

  final Map<String, RoomRole> roles;

  @override
  String get event => 'roles';

  @override
  Map<String, Object?> toJson() => {
    'v': kRoomProtocol,
    'roles': {for (final e in roles.entries) e.key: e.value.name},
  };

  static RoomRolesMsg? _decode(Map<Object?, Object?> j) {
    final raw = j['roles'];
    if (raw is! Map) return null;
    final roles = <String, RoomRole>{};
    for (final e in raw.entries) {
      final k = e.key;
      final role = _byName(RoomRole.values, e.value);
      if (k is! String || role == null) return null;
      roles[k] = role;
    }
    return RoomRolesMsg(roles: roles);
  }
}

/// A guest's request to the host.
class RoomRequestMsg extends RoomMessage {
  const RoomRequestMsg({
    required this.from,
    required this.id,
    required this.op,
    this.args = const {},
    this.epoch,
  });

  /// The asking device's id.
  final String from;
  final String id;
  final RoomOp op;
  final Map<String, Object?> args;
  final int? epoch;

  @override
  String get event => 'request';

  @override
  Map<String, Object?> toJson() => {
    'v': kRoomProtocol,
    'from': from,
    'id': id,
    'op': op.name,
    'args': args,
    if (epoch != null) 'epoch': epoch,
  };

  static RoomRequestMsg? _decode(Map<Object?, Object?> j) {
    final from = j['from'];
    final id = j['id'];
    final op = _byName(RoomOp.values, j['op']);
    final rawArgs = j['args'] ?? const <String, Object?>{};
    final epoch = j['epoch'];
    if (from is! String || id is! String || op == null) return null;
    if (rawArgs is! Map) return null;
    if (epoch != null && epoch is! int) return null;
    return RoomRequestMsg(
      from: from,
      id: id,
      op: op,
      args: {
        for (final e in rawArgs.entries)
          if (e.key is String) e.key! as String: e.value,
      },
      epoch: epoch as int?,
    );
  }
}

/// A guest asking the host for its full state at once.
class RoomHelloMsg extends RoomMessage {
  const RoomHelloMsg({required this.from});

  final String from;

  @override
  String get event => 'hello';

  @override
  Map<String, Object?> toJson() => {'v': kRoomProtocol, 'from': from};

  static RoomHelloMsg? _decode(Map<Object?, Object?> j) {
    final from = j['from'];
    if (from is! String) return null;
    return RoomHelloMsg(from: from);
  }
}

/// The host removing a guest.
class RoomKickMsg extends RoomMessage {
  const RoomKickMsg({required this.deviceId});

  final String deviceId;

  @override
  String get event => 'kick';

  @override
  Map<String, Object?> toJson() => {'v': kRoomProtocol, 'deviceId': deviceId};

  static RoomKickMsg? _decode(Map<Object?, Object?> j) {
    final deviceId = j['deviceId'];
    if (deviceId is! String) return null;
    return RoomKickMsg(deviceId: deviceId);
  }
}

/// The host closing the room.
class RoomEndMsg extends RoomMessage {
  const RoomEndMsg();

  @override
  String get event => 'end';

  @override
  Map<String, Object?> toJson() => {'v': kRoomProtocol};
}
