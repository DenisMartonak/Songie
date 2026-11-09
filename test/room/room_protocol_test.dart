import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/player_service.dart' show RepeatMode;
import 'package:songies/room/room_protocol.dart';

const yt = RoomSong(
  videoId: 'v1',
  title: 'Halo',
  artist: 'Beyonce',
  album: 'I Am',
  durationMs: 1000,
  artUrl: 'https://x/a.jpg',
);
const loc = RoomSong(title: 'Mine', artist: 'Me');

RoomMessage? roundTrip(RoomMessage m) =>
    RoomMessage.decode(m.event, m.toJson());

void main() {
  test('songs round-trip', () {
    final back = RoomSong.fromJson(yt.toJson())!;
    expect(back.toJson(), yt.toJson());
    expect(RoomSong.fromJson(loc.toJson())!.local, isTrue);
    expect(yt.local, isFalse);
    expect(RoomSong.fromJson({'title': 1}), isNull);
    expect(RoomSong.fromJson('x'), isNull);
  });

  test('presence round-trips and decodes any v', () {
    const p = RoomPresence(
      userId: 'u',
      deviceId: 'd',
      name: 'N',
      platform: 'linux',
      host: true,
    );
    final back = RoomPresence.fromJson(p.toJson())!;
    expect(back.host, isTrue);
    expect(back.compatible, isTrue);
    final other = RoomPresence.fromJson({...p.toJson(), 'v': 7})!;
    expect(other.v, 7);
    expect(other.compatible, isFalse);
    expect(RoomPresence.fromJson({'v': 1}), isNull);
  });

  test('messages round-trip', () {
    final state = roundTrip(
      const RoomStateMsg(
        epoch: 2,
        songs: [yt, loc],
        offset: 3,
        index: 4,
        playing: true,
        positionMs: 50,
        durationMs: null,
        shuffle: true,
        repeat: RepeatMode.all,
      ),
    );
    expect(state, isA<RoomStateMsg>());
    final s = state! as RoomStateMsg;
    expect(s.songs.length, 2);
    expect(s.offset, 3);
    expect(s.repeat, RepeatMode.all);
    expect(s.durationMs, isNull);

    final roles =
        roundTrip(
              const RoomRolesMsg(
                roles: {'d': RoomRole.queue, 'e': RoomRole.full},
              ),
            )!
            as RoomRolesMsg;
    expect(roles.roles['d'], RoomRole.queue);

    final req =
        roundTrip(
              const RoomRequestMsg(
                from: 'd',
                id: 'r1',
                op: RoomOp.playAt,
                args: {'videoId': 'v1'},
                epoch: 2,
              ),
            )!
            as RoomRequestMsg;
    expect(req.op, RoomOp.playAt);
    expect(req.args['videoId'], 'v1');
    expect(req.epoch, 2);

    expect(
      (roundTrip(const RoomHelloMsg(from: 'd'))! as RoomHelloMsg).from,
      'd',
    );
    expect(
      (roundTrip(const RoomKickMsg(deviceId: 'd'))! as RoomKickMsg).deviceId,
      'd',
    );
    expect(roundTrip(const RoomEndMsg()), isA<RoomEndMsg>());
  });

  test('bad input decodes to null', () {
    expect(RoomMessage.decode('hello', {'v': 2, 'from': 'd'}), isNull);
    expect(RoomMessage.decode('hello', {'from': 'd'}), isNull);
    expect(RoomMessage.decode('nope', {'v': 1}), isNull);
    expect(RoomMessage.decode('hello', 'garbage'), isNull);
    expect(RoomMessage.decode('hello', null), isNull);
    expect(RoomMessage.decode('hello', {'v': 1, 'from': 3}), isNull);
    expect(
      RoomMessage.decode('request', {
        'v': 1,
        'from': 'd',
        'id': 'r',
        'op': 'x',
      }),
      isNull,
    );
    expect(
      RoomMessage.decode('roles', {
        'v': 1,
        'roles': {'d': 'boss'},
      }),
      isNull,
    );
    expect(RoomMessage.decode('state', {'v': 1, 'songs': 'x'}), isNull);
  });

  test('roleAllows', () {
    for (final op in RoomOp.values) {
      expect(roleAllows(RoomRole.listener, op), isFalse);
      expect(roleAllows(RoomRole.full, op), isTrue);
      expect(
        roleAllows(RoomRole.queue, op),
        op == RoomOp.addNext || op == RoomOp.addToEnd,
      );
    }
    expect(RoomOp.values.length, 14);
  });
}
