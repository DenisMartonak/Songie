import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/remote/remote_channel.dart';
import 'package:songies/remote/remote_protocol.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = RemotePresence(
  deviceId: 'c',
  name: 'This PC',
  platform: 'linux',
  appVersion: '1.0.0',
  playing: false,
);

void main() {
  final logs = <String>[];
  var clientCalls = 0;

  setUp(() {
    logs.clear();
    clientCalls = 0;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = original);
  });

  SupabaseRemoteChannel channel() => SupabaseRemoteChannel(() {
    clientCalls++;
    throw StateError('no client in this test');
  }, 'u1');

  test('a dropped connection empties the devices and says so', () async {
    final ch = channel();
    final seen = <List<RemotePresence>>[];
    ch.presences.listen(seen.add);
    ch.onStatus(RealtimeSubscribeStatus.channelError, 'socket gone');
    await pumpEventQueue();
    expect(seen, [isEmpty]);
    expect(ch.present, isEmpty);
    expect(logs.single, contains('channelError'));
  });

  test('closed and timed out are logged without an error too', () async {
    final ch = channel();
    final seen = <List<RemotePresence>>[];
    ch.presences.listen(seen.add);
    ch.onStatus(RealtimeSubscribeStatus.timedOut, null);
    ch.onStatus(RealtimeSubscribeStatus.closed, null);
    await pumpEventQueue();
    expect(seen, hasLength(2));
    expect(logs, hasLength(2));
    expect(logs[0], contains('timedOut'));
    expect(logs[1], contains('closed'));
  });

  test('a leave while a join waits makes the join do nothing', () async {
    final ch = channel();
    final joining = ch.join(_me);
    await ch.leave();
    await joining;
    expect(clientCalls, 0);
  });
}
