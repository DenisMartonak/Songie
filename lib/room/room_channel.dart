import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/log.dart';
import 'room_protocol.dart';

/// The private channel `room:<room id>` a room's host and guests share:
/// Presence for who is in the room, Broadcast for [RoomMessage]s.
abstract class RoomChannel {
  /// Joins the channel and announces [me].
  Future<void> join(RoomPresence me);

  /// Every device present, this one included; one entry per device id.
  Stream<List<RoomPresence>> get presences;

  /// The latest list [presences] emitted.
  List<RoomPresence> get present;

  Future<void> send(RoomMessage m);

  /// Messages from other devices only, never this device's own sends.
  Stream<RoomMessage> get messages;

  Future<void> leave();
}

/// [RoomChannel] on Supabase Realtime. Thin, like
/// `SupabaseCloudRemote.changes` (only [onStatus] and [join]'s ordering are
/// unit-tested); reconnecting is the client's own. While this device is off
/// the channel it reports no one present.
class SupabaseRoomChannel implements RoomChannel {
  SupabaseRoomChannel(this._client, this._roomId);

  final SupabaseClient Function() _client;
  final String _roomId;

  RealtimeChannel? _channel;
  RoomPresence? _me;
  var _present = const <RoomPresence>[];
  final _presences = StreamController<List<RoomPresence>>.broadcast();
  final _messages = StreamController<RoomMessage>.broadcast();

  @override
  List<RoomPresence> get present => _present;

  @override
  Stream<List<RoomPresence>> get presences => _presences.stream;

  @override
  Stream<RoomMessage> get messages => _messages.stream;

  /// Bumped by every [join] and [leave], so a join still waiting for the
  /// previous channel to go can tell it has been overtaken.
  int _turn = 0;

  @override
  Future<void> join(RoomPresence me) async {
    final turn = ++_turn;
    await _remove();
    // A leave (the host stopping) or another join came meanwhile.
    if (turn != _turn) return;
    _me = me;
    final channel = _client().channel(
      'room:$_roomId',
      opts: RealtimeChannelConfig(private: true, key: me.deviceId),
    );
    _channel = channel;
    channel.onPresenceSync((_) => _onSync(channel));
    for (final event in const [
      'state',
      'roles',
      'request',
      'hello',
      'kick',
      'end',
    ]) {
      channel.onBroadcast(
        event: event,
        callback: (payload) => _onBroadcast(channel, event, payload),
      );
    }
    channel.subscribe((status, error) {
      if (channel == _channel) onStatus(status, error);
    });
  }

  /// The channel's subscribe status changed. Subscribed (also after the
  /// client rejoins by itself) announces this device again, and the
  /// presence sync that follows brings the others back. Anything else means
  /// this device is off the channel: no one is known to be online until then
  /// (a controller shows its link lost; the picker shows no devices).
  @visibleForTesting
  void onStatus(RealtimeSubscribeStatus status, Object? error) {
    try {
      if (status == RealtimeSubscribeStatus.subscribed) {
        final channel = _channel;
        final mine = _me;
        if (channel != null && mine != null) unawaited(_track(channel, mine));
        return;
      }
      AppLog.w('room channel: ${status.name}', error);
      _present = const [];
      if (!_presences.isClosed) _presences.add(_present);
    } on Object catch (e, s) {
      AppLog.w('room channel: subscribe callback failed', e, s);
    }
  }

  Future<void> _track(RealtimeChannel channel, RoomPresence me) async {
    try {
      final res = await channel.track(me.toJson());
      if (res != ChannelResponse.ok) {
        AppLog.w('room channel: track answered ${res.name}');
      }
    } on Object catch (e, s) {
      AppLog.w('room channel: track failed', e, s);
    }
  }

  void _onSync(RealtimeChannel channel) {
    if (channel != _channel) return;
    try {
      final byDevice = <String, RoomPresence>{};
      for (final s in channel.presenceState()) {
        for (final p in s.presences) {
          final one = RoomPresence.fromJson(p.payload);
          if (one != null) byDevice[one.deviceId] = one;
        }
      }
      _present = List.unmodifiable(byDevice.values);
      if (!_presences.isClosed) _presences.add(_present);
    } on Object catch (e, s) {
      AppLog.w('room channel: presence sync failed', e, s);
    }
  }

  void _onBroadcast(
    RealtimeChannel channel,
    String event,
    Map<String, dynamic> message,
  ) {
    if (channel != _channel) return;
    try {
      // The client hands over the envelope; the message is under `payload`.
      final inner = message['payload'];
      final payload = message.containsKey('v') || inner is! Map
          ? message
          : inner;
      final m = RoomMessage.decode(event, payload);
      if (m != null && !_messages.isClosed) _messages.add(m);
    } on Object catch (e, s) {
      AppLog.w('room channel: message failed', e, s);
    }
  }

  @override
  Future<void> send(RoomMessage m) async {
    final channel = _channel;
    if (channel == null) return;
    try {
      final res = await channel.sendBroadcastMessage(
        event: m.event,
        payload: m.toJson(),
      );
      if (res != ChannelResponse.ok) {
        AppLog.w('room channel: send answered ${res.name}');
      }
    } on Object catch (e, s) {
      AppLog.w('room channel: send failed', e, s);
    }
  }

  @override
  Future<void> leave() {
    _turn++;
    return _remove();
  }

  Future<void> _remove() async {
    final channel = _channel;
    _channel = null;
    _present = const [];
    if (!_presences.isClosed) _presences.add(_present);
    if (channel == null) return;
    try {
      await _client().removeChannel(channel);
    } on Object catch (e, s) {
      AppLog.w('room channel: leave failed', e, s);
    }
  }
}
