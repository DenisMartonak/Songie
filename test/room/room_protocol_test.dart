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
    // Beats: this build takes them; a build before them leaves the key out.
    expect(back.beats, isTrue);
    const withPicture = RoomPresence(
      userId: 'u',
      deviceId: 'd',
      name: 'N',
      platform: 'linux',
      host: false,
      avatarUrl: 'https://x/p.jpg',
    );
    expect(
      RoomPresence.fromJson(withPicture.toJson())!.avatarUrl,
      'https://x/p.jpg',
    );
    expect(back.avatarUrl, isNull);
    expect(
      RoomPresence.fromJson({...p.toJson(), 'avatarUrl': 3})!.avatarUrl,
      isNull,
    );
    expect(
      RoomPresence.fromJson({...p.toJson()}..remove('beats'))!.beats,
      isFalse,
    );
  });

  test('a state carries its revision; one without it still decodes', () {
    const full = RoomStateMsg(
      rev: 9,
      epoch: 2,
      songs: [yt],
      offset: 3,
      index: 3,
      playing: true,
      positionMs: 50,
      durationMs: 1000,
      shuffle: false,
      repeat: RepeatMode.off,
    );
    expect((roundTrip(full)! as RoomStateMsg).rev, 9);
    final old = {...full.toJson()}..remove('rev');
    final s = RoomMessage.decode('state', old)! as RoomStateMsg;
    expect(s.rev, isNull);
    expect(s.songs.single.videoId, 'v1');
  });

  test('songs carry who added them; faces round-trip', () {
    const face = RoomFace(name: 'ann', avatarUrl: 'https://x/a.jpg');
    const full = RoomStateMsg(
      rev: 1,
      epoch: 2,
      songs: [RoomSong(videoId: 'v1', title: 'Halo', artist: 'B', by: 'u1')],
      offset: 0,
      index: 0,
      playing: true,
      positionMs: 0,
      durationMs: null,
      shuffle: false,
      repeat: RepeatMode.off,
      faces: {'u1': face},
    );
    final back = roundTrip(full)! as RoomStateMsg;
    expect(back.songs.single.by, 'u1');
    expect(back.faces, {'u1': face});
    expect(const RoomFace(name: 'ann'), isNot(face));

    final json = full.toJson();
    final old = {
      ...json,
      'songs': [
        {...(json['songs']! as List).single as Map}..remove('by'),
      ],
    }..remove('faces');
    final s = RoomMessage.decode('state', old)! as RoomStateMsg;
    expect(s.songs.single.by, isNull);
    expect(s.faces, isEmpty);

    final bad =
        RoomMessage.decode('state', {
              ...json,
              'faces': {'u1': 3},
            })!
            as RoomStateMsg;
    expect(bad.faces, isEmpty);
    final badBy = RoomSong.fromJson({...yt.toJson(), 'by': 5});
    expect(badBy, isNotNull);
    expect(badBy!.by, isNull);
  });

  test('a beat round-trips and plays over its full state', () {
    const full = RoomStateMsg(
      rev: 9,
      epoch: 2,
      songs: [yt, loc],
      offset: 3,
      index: 3,
      playing: true,
      positionMs: 50,
      durationMs: 1000,
      shuffle: false,
      repeat: RepeatMode.off,
    );
    final beat =
        roundTrip(
              const RoomBeatMsg(
                rev: 9,
                index: 4,
                playing: false,
                positionMs: 70,
                durationMs: null,
                shuffle: true,
                repeat: RepeatMode.one,
              ),
            )!
            as RoomBeatMsg;
    expect(beat.toJson().containsKey('songs'), isFalse);
    final s = beat.over(full);
    expect(s.rev, 9);
    expect(s.epoch, 2);
    expect(s.songs, same(full.songs));
    expect(s.faces, same(full.faces));
    expect(s.offset, 3);
    expect(s.index, 4);
    expect(s.playing, isFalse);
    expect(s.positionMs, 70);
    expect(s.durationMs, isNull);
    expect(s.shuffle, isTrue);
    expect(s.repeat, RepeatMode.one);
    expect(RoomMessage.decode('beat', {'v': 1, 'index': 1}), isNull);
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
