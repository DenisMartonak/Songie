import 'package:flutter_test/flutter_test.dart';
import 'package:songies/remote/remote_channel.dart';
import 'package:songies/remote/remote_protocol.dart';

import '../helpers/fake_remote_hub.dart';

RemotePresence _p(String id, {bool playing = false}) => RemotePresence(
  deviceId: id,
  name: 'Device $id',
  platform: 'android',
  appVersion: '1.0.0',
  playing: playing,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeRemoteHub hub;
  late RemoteChannel a;
  late RemoteChannel b;
  late RemoteChannel c;
  late List<RemoteMessage> gotA;
  late List<RemoteMessage> gotB;
  late List<RemoteMessage> gotC;

  setUp(() async {
    hub = FakeRemoteHub();
    a = hub.channelFor('a');
    b = hub.channelFor('b');
    c = hub.channelFor('c');
    gotA = [];
    gotB = [];
    gotC = [];
    a.messages.listen(gotA.add);
    b.messages.listen(gotB.add);
    c.messages.listen(gotC.add);
    await a.join(_p('a'));
    await b.join(_p('b'));
    await c.join(_p('c'));
    await _settle();
  });

  test('delivers to others, not self', () async {
    await a.send(const RemoteHello(to: 'b'));
    await _settle();
    expect(gotA, isEmpty);
    expect(gotB, hasLength(1));
    expect(gotC, hasLength(1));
    expect((gotB.single as RemoteHello).to, 'b');
    expect(hub.sent, hasLength(1));
  });

  test('presence lists every joined device and updates', () async {
    expect(a.present.map((p) => p.deviceId).toSet(), {'a', 'b', 'c'});
    final seen = <List<RemotePresence>>[];
    final sub = a.presences.listen(seen.add);
    await b.updatePresence(_p('b', playing: true));
    await _settle();
    await sub.cancel();
    expect(seen, isNotEmpty);
    expect(a.present.firstWhere((p) => p.deviceId == 'b').playing, isTrue);
    expect(a.present, hasLength(3));
  });

  test('drop hides a device and stops delivery until restore', () async {
    hub.drop('b');
    await _settle();
    expect(a.present.map((p) => p.deviceId).toSet(), {'a', 'c'});
    expect(b.present, isEmpty);

    await a.send(const RemoteHello(to: 'b'));
    await b.send(const RemoteHello(to: 'a'));
    await _settle();
    expect(gotB, isEmpty);
    expect(gotA, isEmpty);
    expect(gotC, hasLength(1));

    hub.restore('b');
    await _settle();
    expect(a.present.map((p) => p.deviceId).toSet(), {'a', 'b', 'c'});
    await a.send(const RemoteHello(to: 'b'));
    await _settle();
    expect(gotB, hasLength(1));
  });

  test('leave removes presence', () async {
    await b.leave();
    await _settle();
    expect(a.present.map((p) => p.deviceId).toSet(), {'a', 'c'});
    await a.send(const RemoteHello(to: 'b'));
    await _settle();
    expect(gotB, isEmpty);
  });

  test('a payload that fails to decode is not delivered', () async {
    // seek needs a non-negative integer `ms`: it encodes, but won't decode.
    await a.send(
      const RemoteCommand(
        to: 'b',
        id: '1',
        op: RemoteOp.seek,
        args: {'ms': -5},
      ),
    );
    await _settle();
    expect(gotB, isEmpty);
    expect(gotC, isEmpty);
  });
}
