import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:songies/data/database.dart';
import 'package:songies/discord/discord_ipc.dart';

/// An in-memory Discord: answers the handshake with READY and every frame
/// with an empty success, and records what it was sent.
class FakeDiscord {
  /// What the next connect returns: false acts as "Discord isn't running".
  bool running = true;

  /// Answer the handshake with a CLOSE (an unknown application id).
  bool refuse = false;

  /// Fail the next write (the user quit Discord).
  bool dropNextWrite = false;

  int connects = 0;
  final List<(int, Map<String, Object?>)> sent = [];
  FakePipe? pipe;

  Future<DiscordPipe?> connect() async {
    connects++;
    if (!running) return null;
    return pipe = FakePipe(this);
  }

  /// The activities set, in order (null for a clear).
  List<Map<String, Object?>?> get activities => [
    for (final (op, m) in sent)
      if (op == DiscordOp.frame && m['cmd'] == 'SET_ACTIVITY')
        (m['args']! as Map)['activity'] as Map<String, Object?>?,
  ];
}

class FakePipe implements DiscordPipe {
  FakePipe(this._discord);

  final FakeDiscord _discord;
  final List<int> _out = [];
  bool closed = false;

  @override
  Future<void> write(List<int> bytes) async {
    if (closed) throw StateError('closed');
    if (_discord.dropNextWrite) {
      _discord.dropNextWrite = false;
      throw StateError('Discord went away');
    }
    final header = ByteData.sublistView(Uint8List.fromList(bytes), 0, 8);
    final op = header.getUint32(0, Endian.little);
    final body =
        jsonDecode(utf8.decode(bytes.sublist(8))) as Map<String, Object?>;
    _discord.sent.add((op, body));
    if (op == DiscordOp.handshake) {
      _out.addAll(
        _discord.refuse
            ? encodeDiscordFrame(DiscordOp.close, {
                'code': 4000,
                'message': 'Invalid Client ID',
              })
            : encodeDiscordFrame(DiscordOp.frame, {
                'cmd': 'DISPATCH',
                'evt': 'READY',
              }),
      );
    } else {
      _out.addAll(
        encodeDiscordFrame(DiscordOp.frame, {
          'cmd': body['cmd'],
          'nonce': body['nonce'],
        }),
      );
    }
  }

  @override
  Future<Uint8List> read(int count) async {
    if (_out.length < count) throw StateError('nothing to read');
    final bytes = Uint8List.fromList(_out.sublist(0, count));
    _out.removeRange(0, count);
    return bytes;
  }

  @override
  Future<void> close() async => closed = true;
}

Track discordTrack(
  String id, {
  String source = 'local',
  String? videoId,
  String title = 'Get Lucky',
  String artist = 'Daft Punk',
  String? album,
  int durationMs = 248000,
}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: source,
  ytVideoId: videoId,
  title: title,
  artist: artist,
  album: album,
  durationMs: durationMs,
  unavailable: false,
  searchText: '$title $artist',
);
