import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/discord/discord_ipc.dart';

import 'fake_discord.dart';

void main() {
  test('a frame is the opcode and length, little-endian, then JSON', () {
    final frame = encodeDiscordFrame(DiscordOp.handshake, {'v': 1});
    final header = ByteData.sublistView(frame, 0, 8);
    expect(header.getUint32(0, Endian.little), 0);
    expect(header.getUint32(4, Endian.little), '{"v":1}'.length);
    expect(String.fromCharCodes(frame.sublist(8)), '{"v":1}');
  });

  group('discordIpcPaths', () {
    test('Windows: the ten named pipes', () {
      final paths = discordIpcPaths(windows: true, env: const {});
      expect(paths, hasLength(10));
      expect(paths.first, r'\\?\pipe\discord-ipc-0');
    });

    test('Linux: the runtime dir first, Flatpak and Snap too', () {
      final paths = discordIpcPaths(
        windows: false,
        env: const {'XDG_RUNTIME_DIR': '/run/user/1000'},
      );
      expect(paths.first, '/run/user/1000/discord-ipc-0');
      expect(
        paths,
        contains('/run/user/1000/app/com.discordapp.Discord/discord-ipc-0'),
      );
      expect(paths, contains('/run/user/1000/snap.discord/discord-ipc-0'));
      expect(paths, contains('/tmp/discord-ipc-9'));
    });
  });

  group('DiscordRpc', () {
    late FakeDiscord discord;
    late DiscordRpc rpc;

    setUp(() {
      discord = FakeDiscord();
      rpc = DiscordRpc(discord.connect, processId: 42);
    });

    test('connect sends the handshake with the client id', () async {
      expect(await rpc.connect('123'), isTrue);
      expect(rpc.connected, isTrue);
      final (op, body) = discord.sent.single;
      expect(op, DiscordOp.handshake);
      expect(body, {'v': 1, 'client_id': '123'});
    });

    test('connect is false when Discord is not running', () async {
      discord.running = false;
      expect(await rpc.connect('123'), isFalse);
      expect(rpc.connected, isFalse);
    });

    test('a refused handshake closes the connection', () async {
      discord.refuse = true;
      expect(await rpc.connect('bad'), isFalse);
      expect(rpc.connected, isFalse);
      expect(discord.pipe!.closed, isTrue);
    });

    test('setActivity sends SET_ACTIVITY with the pid; null clears', () async {
      await rpc.connect('123');
      expect(await rpc.setActivity({'details': 'Song'}), isTrue);
      expect(await rpc.setActivity(null), isTrue);
      final (op, first) = discord.sent[1];
      expect(op, DiscordOp.frame);
      expect(first['cmd'], 'SET_ACTIVITY');
      expect((first['args']! as Map)['pid'], 42);
      expect(discord.activities, [
        {'details': 'Song'},
        null,
      ]);
      expect(
        (discord.sent[2].$2['args']! as Map).containsKey('activity'),
        isFalse,
      );
    });

    test('a lost connection is closed and reported', () async {
      await rpc.connect('123');
      discord.dropNextWrite = true;
      expect(await rpc.setActivity({'details': 'Song'}), isFalse);
      expect(rpc.connected, isFalse);
    });
  });
}
