import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/log.dart';
import 'remote_protocol.dart';

/// The private channel `remote:<user id>` a user's devices share: Presence
/// for who is online, Broadcast for [RemoteMessage]s.
abstract class RemoteChannel {
  /// Joins the channel and announces [me].
  Future<void> join(RemotePresence me);

  /// Replaces what this device announces (e.g. its playing flag or title).
  Future<void> updatePresence(RemotePresence me);

  /// Every device present, this one included; one entry per device id.
  Stream<List<RemotePresence>> get presences;

  /// The latest list [presences] emitted.
  List<RemotePresence> get present;

  Future<void> send(RemoteMessage m);

  /// Messages from other devices only, never this device's own sends.
  Stream<RemoteMessage> get messages;

  Future<void> leave();
}

/// [RemoteChannel] on Supabase Realtime. Thin and not unit-tested, like
/// `SupabaseCloudRemote.changes`; reconnecting is the client's own.
class SupabaseRemoteChannel implements RemoteChannel {
  SupabaseRemoteChannel(this._client, this._userId);

  final SupabaseClient Function() _client;
  final String _userId;

  RealtimeChannel? _channel;
  RemotePresence? _me;
  var _present = const <RemotePresence>[];
  final _presences = StreamController<List<RemotePresence>>.broadcast();
  final _messages = StreamController<RemoteMessage>.broadcast();

  @override
  List<RemotePresence> get present => _present;

  @override
  Stream<List<RemotePresence>> get presences => _presences.stream;

  @override
  Stream<RemoteMessage> get messages => _messages.stream;

  @override
  Future<void> join(RemotePresence me) async {
    await leave();
    _me = me;
    final channel = _client().channel(
      'remote:$_userId',
      opts: RealtimeChannelConfig(private: true, key: me.deviceId),
    );
    _channel = channel;
    channel.onPresenceSync((_) => _onSync(channel));
    for (final event in const ['state', 'command', 'hello']) {
      channel.onBroadcast(
        event: event,
        callback: (payload) => _onBroadcast(channel, event, payload),
      );
    }
    channel.subscribe((status, error) {
      if (channel != _channel) return;
      try {
        if (status == RealtimeSubscribeStatus.subscribed) {
          final mine = _me;
          if (mine != null) unawaited(_track(channel, mine));
        } else if (error != null) {
          AppLog.w('remote channel: $status', error);
        }
      } on Object catch (e, s) {
        AppLog.w('remote channel: subscribe callback failed', e, s);
      }
    });
  }

  Future<void> _track(RealtimeChannel channel, RemotePresence me) async {
    try {
      final res = await channel.track(me.toJson());
      if (res != ChannelResponse.ok) {
        AppLog.w('remote channel: track answered ${res.name}');
      }
    } on Object catch (e, s) {
      AppLog.w('remote channel: track failed', e, s);
    }
  }

  @override
  Future<void> updatePresence(RemotePresence me) async {
    _me = me;
    final channel = _channel;
    if (channel != null) await _track(channel, me);
  }

  void _onSync(RealtimeChannel channel) {
    if (channel != _channel) return;
    try {
      final byDevice = <String, RemotePresence>{};
      for (final s in channel.presenceState()) {
        for (final p in s.presences) {
          final one = RemotePresence.fromJson(p.payload);
          if (one != null) byDevice[one.deviceId] = one;
        }
      }
      _present = List.unmodifiable(byDevice.values);
      if (!_presences.isClosed) _presences.add(_present);
    } on Object catch (e, s) {
      AppLog.w('remote channel: presence sync failed', e, s);
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
      final m = RemoteMessage.decode(event, payload);
      if (m != null && !_messages.isClosed) _messages.add(m);
    } on Object catch (e, s) {
      AppLog.w('remote channel: message failed', e, s);
    }
  }

  @override
  Future<void> send(RemoteMessage m) async {
    final channel = _channel;
    if (channel == null) return;
    try {
      final res = await channel.sendBroadcastMessage(
        event: m.event,
        payload: m.toJson(),
      );
      if (res != ChannelResponse.ok) {
        AppLog.w('remote channel: send answered ${res.name}');
      }
    } on Object catch (e, s) {
      AppLog.w('remote channel: send failed', e, s);
    }
  }

  @override
  Future<void> leave() async {
    final channel = _channel;
    _channel = null;
    _present = const [];
    if (!_presences.isClosed) _presences.add(_present);
    if (channel == null) return;
    try {
      await _client().removeChannel(channel);
    } on Object catch (e, s) {
      AppLog.w('remote channel: leave failed', e, s);
    }
  }
}
