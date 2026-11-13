import 'dart:async';
import 'dart:convert';

import 'package:songies/room/room_channel.dart';
import 'package:songies/room/room_protocol.dart';

/// An in-memory `room:<id>` channel for tests: one [channelFor] per
/// device. Sends reach every other joined, connected device a microtask
/// later, after a JSON round trip (so tests exercise the protocol).
class FakeRoomHub {
  final _channels = <String, _FakeChannel>{};
  final _dropped = <String>{};

  /// Every message sent through the hub, in order (as the sender made it).
  /// Sends from dropped or unjoined devices are not recorded.
  final List<RoomMessage> sent = [];

  /// When it returns true for a sent message, the message is recorded but
  /// never arrives (lost on the way).
  bool Function(RoomMessage m)? lose;

  RoomChannel channelFor(String deviceId) =>
      _channels.putIfAbsent(deviceId, () => _FakeChannel(this, deviceId));

  /// Takes [deviceId] off the network: gone from Presence, nothing in or out.
  /// The dropped device itself then sees no one present, as
  /// `SupabaseRoomChannel` reports when its own connection drops.
  void drop(String deviceId) {
    _dropped.add(deviceId);
    _publish();
  }

  void restore(String deviceId) {
    _dropped.remove(deviceId);
    _publish();
  }

  bool _online(_FakeChannel c) => c.me != null && !_dropped.contains(c.id);

  List<RoomPresence> _list() => [
    for (final c in _channels.values)
      if (_online(c)) c.me!,
  ];

  void _publish() {
    for (final c in _channels.values) {
      c._emitPresence(_online(c) ? _list() : const []);
    }
  }

  void _deliver(_FakeChannel from, RoomMessage m) {
    if (!_online(from)) return;
    sent.add(m);
    if (lose?.call(m) ?? false) return;
    final wire = jsonDecode(jsonEncode(m.toJson()));
    final decoded = RoomMessage.decode(m.event, wire);
    if (decoded == null) return;
    for (final c in _channels.values) {
      if (c == from || !_online(c)) continue;
      scheduleMicrotask(() {
        if (_online(c)) c._messages.add(decoded);
      });
    }
  }
}

class _FakeChannel implements RoomChannel {
  _FakeChannel(this._hub, this.id);

  final FakeRoomHub _hub;
  final String id;
  RoomPresence? me;
  var _present = const <RoomPresence>[];
  final _presences = StreamController<List<RoomPresence>>.broadcast();
  final _messages = StreamController<RoomMessage>.broadcast();

  void _emitPresence(List<RoomPresence> list) {
    _present = list;
    scheduleMicrotask(() {
      if (!_presences.isClosed) _presences.add(list);
    });
  }

  @override
  Future<void> join(RoomPresence p) async {
    me = p;
    _hub._publish();
  }

  @override
  Stream<List<RoomPresence>> get presences => _presences.stream;

  @override
  List<RoomPresence> get present => _present;

  @override
  Future<void> send(RoomMessage m) async => _hub._deliver(this, m);

  @override
  Stream<RoomMessage> get messages => _messages.stream;

  @override
  Future<void> leave() async {
    me = null;
    _hub._publish();
  }
}
