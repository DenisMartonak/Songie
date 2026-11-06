import 'dart:async';
import 'dart:convert';

import 'package:songies/remote/remote_channel.dart';
import 'package:songies/remote/remote_protocol.dart';

/// An in-memory `remote:<user>` channel for tests: one [channelFor] per
/// device. Sends reach every other joined, connected device a microtask
/// later, after a JSON round trip (so tests exercise the protocol).
class FakeRemoteHub {
  final _channels = <String, _FakeChannel>{};
  final _dropped = <String>{};

  /// Every message sent through the hub, in order (as the sender made it).
  /// Sends from dropped or unjoined devices are not recorded.
  final List<RemoteMessage> sent = [];

  RemoteChannel channelFor(String deviceId) =>
      _channels.putIfAbsent(deviceId, () => _FakeChannel(this, deviceId));

  /// Takes [deviceId] off the network: gone from Presence, nothing in or out.
  void drop(String deviceId) {
    _dropped.add(deviceId);
    _publish();
  }

  void restore(String deviceId) {
    _dropped.remove(deviceId);
    _publish();
  }

  bool _online(_FakeChannel c) => c.me != null && !_dropped.contains(c.id);

  List<RemotePresence> _list() => [
    for (final c in _channels.values)
      if (_online(c)) c.me!,
  ];

  void _publish() {
    for (final c in _channels.values) {
      c._emitPresence(_online(c) ? _list() : const []);
    }
  }

  void _deliver(_FakeChannel from, RemoteMessage m) {
    if (!_online(from)) return;
    sent.add(m);
    final wire = jsonDecode(jsonEncode(m.toJson()));
    final decoded = RemoteMessage.decode(m.event, wire);
    if (decoded == null) return;
    for (final c in _channels.values) {
      if (c == from || !_online(c)) continue;
      scheduleMicrotask(() {
        if (_online(c)) c._messages.add(decoded);
      });
    }
  }
}

class _FakeChannel implements RemoteChannel {
  _FakeChannel(this._hub, this.id);

  final FakeRemoteHub _hub;
  final String id;
  RemotePresence? me;
  var _present = const <RemotePresence>[];
  final _presences = StreamController<List<RemotePresence>>.broadcast();
  final _messages = StreamController<RemoteMessage>.broadcast();

  void _emitPresence(List<RemotePresence> list) {
    _present = list;
    scheduleMicrotask(() {
      if (!_presences.isClosed) _presences.add(list);
    });
  }

  @override
  Future<void> join(RemotePresence p) async {
    me = p;
    _hub._publish();
  }

  @override
  Future<void> updatePresence(RemotePresence p) async {
    if (me == null) return;
    me = p;
    _hub._publish();
  }

  @override
  Stream<List<RemotePresence>> get presences => _presences.stream;

  @override
  List<RemotePresence> get present => _present;

  @override
  Future<void> send(RemoteMessage m) async => _hub._deliver(this, m);

  @override
  Stream<RemoteMessage> get messages => _messages.stream;

  @override
  Future<void> leave() async {
    me = null;
    _hub._publish();
  }
}
