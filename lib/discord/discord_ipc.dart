import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/log.dart';

/// A byte channel to the Discord app running on this computer. Reads and
/// writes take turns (a Windows pipe allows one operation at a time).
abstract class DiscordPipe {
  Future<void> write(List<int> bytes);

  /// Exactly [count] bytes; throws when the other side closes first.
  Future<Uint8List> read(int count);

  Future<void> close();
}

/// Opens a [DiscordPipe], or returns null when Discord isn't running.
typedef DiscordConnector = Future<DiscordPipe?> Function();

/// Discord listens on `discord-ipc-0` … `discord-ipc-9`: a named pipe on
/// Windows, a Unix socket on Linux (also inside Flatpak and Snap installs).
Future<DiscordPipe?> connectToDiscord() async {
  for (final path in discordIpcPaths(
    windows: Platform.isWindows,
    env: Platform.environment,
  )) {
    try {
      if (Platform.isWindows) {
        // A pipe that isn't there fails to open; exists() can't see pipes.
        final file = await File(path).open(mode: FileMode.append);
        return _WindowsPipe(file);
      }
      if (!await File(path).exists()) continue;
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 2),
      );
      return _UnixPipe(socket);
    } catch (_) {
      // Not this one; a stale socket or a pipe another client holds.
    }
  }
  return null;
}

/// Where Discord's IPC endpoint may be, most likely first.
List<String> discordIpcPaths({
  required bool windows,
  required Map<String, String> env,
}) {
  if (windows) {
    return [
      for (var i = 0; i < 10; i++)
        r'\\?\pipe\discord-ipc-'
            '$i',
    ];
  }
  final roots = <String>{
    for (final key in ['XDG_RUNTIME_DIR', 'TMPDIR', 'TMP', 'TEMP'])
      if (env[key] case final v? when v.isNotEmpty) v,
    '/tmp',
  };
  const subdirs = [
    '',
    'app/com.discordapp.Discord/',
    'app/com.discordapp.DiscordCanary/',
    'snap.discord/',
    '.flatpak/dev.vencord.Vesktop/xdg-run/',
  ];
  return [
    for (var i = 0; i < 10; i++)
      for (final root in roots)
        for (final sub in subdirs) '$root/${sub}discord-ipc-$i',
  ];
}

class _UnixPipe implements DiscordPipe {
  _UnixPipe(this._socket) {
    _sub = _socket.listen(
      (data) {
        _buffer.add(data);
        _wake();
      },
      onError: (Object _) => _end(),
      onDone: _end,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _sub;
  final BytesBuilder _buffer = BytesBuilder();
  Completer<void>? _waiting;
  bool _closed = false;

  void _wake() {
    final w = _waiting;
    _waiting = null;
    w?.complete();
  }

  void _end() {
    _closed = true;
    _wake();
  }

  @override
  Future<void> write(List<int> bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<Uint8List> read(int count) async {
    while (_buffer.length < count) {
      if (_closed) throw const SocketException('Discord closed the socket');
      await (_waiting = Completer<void>()).future;
    }
    final all = _buffer.takeBytes();
    _buffer.add(all.sublist(count));
    return Uint8List.sublistView(all, 0, count);
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _sub.cancel();
    _socket.destroy();
  }
}

class _WindowsPipe implements DiscordPipe {
  _WindowsPipe(this._file);

  final RandomAccessFile _file;

  @override
  Future<void> write(List<int> bytes) async {
    await _file.writeFrom(bytes);
    await _file.flush();
  }

  @override
  Future<Uint8List> read(int count) async {
    final out = BytesBuilder(copy: false);
    while (out.length < count) {
      final chunk = await _file.read(count - out.length);
      if (chunk.isEmpty) throw const FileSystemException('Discord closed');
      out.add(chunk);
    }
    return out.takeBytes();
  }

  @override
  Future<void> close() => _file.close();
}

/// Discord's IPC opcodes.
abstract final class DiscordOp {
  static const int handshake = 0;
  static const int frame = 1;
  static const int close = 2;
}

/// One message: a little-endian opcode and length, then UTF-8 JSON.
Uint8List encodeDiscordFrame(int op, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final header = ByteData(8)
    ..setUint32(0, op, Endian.little)
    ..setUint32(4, body.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(body))
      .takeBytes();
}

/// The Rich Presence part of Discord's local RPC: a handshake, then
/// `SET_ACTIVITY` requests, each answered before the next is sent.
class DiscordRpc {
  DiscordRpc(this._connect, {Random? random, int? processId})
    : _random = random ?? Random(),
      _pid = processId ?? pid;

  /// Longest wait for Discord's answer before giving up on the connection.
  static const Duration replyTimeout = Duration(seconds: 5);

  /// Largest answer accepted; anything bigger means a confused stream.
  static const int maxPayload = 64 * 1024;

  final DiscordConnector _connect;
  final Random _random;
  final int _pid;
  DiscordPipe? _pipe;

  bool get connected => _pipe != null;

  /// Connects and introduces the app as [clientId]; false when Discord isn't
  /// running or refused (for example an unknown application id).
  Future<bool> connect(String clientId) async {
    if (_pipe != null) return true;
    final pipe = await _connect();
    if (pipe == null) return false;
    _pipe = pipe;
    try {
      await pipe.write(
        encodeDiscordFrame(DiscordOp.handshake, {
          'v': 1,
          'client_id': clientId,
        }),
      );
      final (op, reply) = await _readFrame(pipe);
      if (op == DiscordOp.frame && reply['evt'] == 'READY') return true;
      AppLog.w('Discord refused the connection: ${reply['message'] ?? op}');
    } catch (e) {
      AppLog.w('Discord handshake failed: $e');
    }
    await disconnect();
    return false;
  }

  /// Shows [activity] on the user's profile, or clears it with null. False
  /// when the connection was lost (it is closed then).
  Future<bool> setActivity(Map<String, Object?>? activity) async {
    final pipe = _pipe;
    if (pipe == null) return false;
    try {
      await pipe.write(
        encodeDiscordFrame(DiscordOp.frame, {
          'cmd': 'SET_ACTIVITY',
          'args': {'pid': _pid, 'activity': ?activity},
          'nonce': _nonce(),
        }),
      );
      final (op, reply) = await _readFrame(pipe);
      if (op == DiscordOp.close) {
        AppLog.w('Discord closed the connection: ${reply['message']}');
        await disconnect();
        return false;
      }
      if (reply['evt'] == 'ERROR') {
        final data = reply['data'];
        AppLog.w(
          'Discord rejected the activity: '
          '${data is Map ? data['message'] : data}',
        );
      }
      return true;
    } catch (e) {
      AppLog.w('Discord connection lost: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    final pipe = _pipe;
    _pipe = null;
    if (pipe == null) return;
    try {
      await pipe.close();
    } catch (_) {
      // Already gone.
    }
  }

  Future<(int, Map<String, Object?>)> _readFrame(DiscordPipe pipe) async {
    final header = ByteData.sublistView(
      await pipe.read(8).timeout(replyTimeout),
    );
    final op = header.getUint32(0, Endian.little);
    final length = header.getUint32(4, Endian.little);
    if (length > maxPayload) {
      throw FormatException('Discord sent $length bytes');
    }
    final body = await pipe.read(length).timeout(replyTimeout);
    final json = jsonDecode(utf8.decode(body));
    return (op, json is Map<String, Object?> ? json : <String, Object?>{});
  }

  String _nonce() =>
      List.generate(16, (_) => _random.nextInt(256).toRadixString(16)).join();
}
