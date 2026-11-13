import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/room/room_channel.dart';
import 'package:songies/room/room_host.dart';
import 'package:songies/room/room_protocol.dart';

import '../helpers/fake_audio_backend.dart';
import '../helpers/fake_room_hub.dart';

Track track(String id, {bool yt = true}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: yt ? 'youtube' : 'local',
  ytVideoId: yt ? 'v$id' : null,
  title: 'Title $id',
  artist: 'Artist',
  durationMs: 0,
  unavailable: false,
  searchText: 'title $id artist',
);

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));

  @override
  Future<void> prefetch(Track t) async {}

  @override
  void invalidate(Track t) {}
}

RoomPresence who(String user, String device, {bool host = false}) =>
    RoomPresence(
      userId: user,
      deviceId: device,
      name: 'Name $device',
      platform: 'linux',
      host: host,
    );

class Rig {
  Rig(this.async, {bool guest = true}) {
    player = PlayerService(FakeAudioBackend(), _Resolver(), random: Random(3));
    host = RoomHost(
      channel: hub.channelFor('h'),
      player: player,
      me: who('uh', 'h', host: true),
      tracksFor: (songs) async => [
        for (final s in songs) s.local ? null : track(s.videoId!.substring(1)),
      ],
      removeMember: (u) async => removed.add(u),
      nowMs: () => 1000000 + async.elapsed.inMilliseconds,
    );
    sub = host.events.listen(events.add);
    guestCh = hub.channelFor('g');
    if (guest) guestCh.join(who('ug', 'g'));
    host.start();
    async.flushMicrotasks();
  }

  final FakeAsync async;
  final hub = FakeRoomHub();
  late final PlayerService player;
  late final RoomHost host;
  late final RoomChannel guestCh;
  late final StreamSubscription<RoomHostEvent> sub;
  final events = <RoomHostEvent>[];
  final removed = <String>[];
  var _n = 0;

  List<RoomStateMsg> get states => hub.sent.whereType<RoomStateMsg>().toList();
  List<RoomBeatMsg> get beats => hub.sent.whereType<RoomBeatMsg>().toList();

  void playQueue(List<String> queue, {int start = 0}) {
    player.playQueue([for (final id in queue) track(id)], startIndex: start);
    settle();
  }

  void settle() {
    async.elapse(const Duration(milliseconds: 300));
    hub.sent.clear();
  }

  void hello() {
    guestCh.send(const RoomHelloMsg(from: 'g'));
    async.flushMicrotasks();
  }

  void request(
    RoomOp op, [
    Map<String, Object?> args = const {},
    int? epoch,
    String from = 'g',
  ]) {
    guestCh.send(
      RoomRequestMsg(
        from: from,
        id: 'r${_n++}',
        op: op,
        args: args,
        epoch: epoch,
      ),
    );
    async.flushMicrotasks();
    async.elapse(const Duration(milliseconds: 300));
  }

  void dispose() {
    host.stop();
    async.flushMicrotasks();
    sub.cancel();
    player.dispose();
    async.flushMicrotasks();
  }
}

void hostTest(String name, void Function(Rig r) body, {bool guest = true}) {
  test(name, () {
    fakeAsync((async) {
      final r = Rig(async, guest: guest);
      body(r);
      r.dispose();
    });
  });
}

List<String> ids(PlayerService p) => [for (final t in p.state.queue) t.id];

void main() {
  setUp(() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = original);
  });

  hostTest('sends no state while alone', (r) {
    r.playQueue(['a', 'b']);
    r.player.playQueue([track('c')]);
    r.async.elapse(const Duration(seconds: 10));
    expect(r.states, isEmpty);
  }, guest: false);

  hostTest('a joining guest gets roles then state after hello', (r) {
    r.playQueue(['a', 'b']);
    r.hello();
    final sent = r.hub.sent.where((m) => m is! RoomHelloMsg).toList();
    expect(sent.first, isA<RoomRolesMsg>());
    expect(sent[1], isA<RoomStateMsg>());
    expect((sent[1] as RoomStateMsg).songs.map((s) => s.videoId), ['va', 'vb']);
    expect(r.events.first, isA<GuestJoined>());
    expect((r.events.first as GuestJoined).name, 'Name g');
  });

  hostTest('a listener cannot change anything', (r) {
    r.playQueue(['a', 'b'], start: 0);
    r.request(RoomOp.next);
    expect(r.player.state.index, 0);
    r.request(RoomOp.addToEnd, {
      'songs': [
        const RoomSong(videoId: 'vz', title: 't', artist: 'a').toJson(),
      ],
    });
    expect(ids(r.player), ['a', 'b']);
  });

  hostTest('queue role adds and emits GuestAdded, but cannot skip', (r) {
    r.playQueue(['a', 'b']);
    r.host.setRole('g', RoomRole.queue);
    r.async.flushMicrotasks();
    expect(
      r.hub.sent.whereType<RoomRolesMsg>().last.roles['g'],
      RoomRole.queue,
    );
    r.request(RoomOp.addToEnd, {
      'songs': [
        const RoomSong(videoId: 'vz', title: 'Zed', artist: 'a').toJson(),
      ],
    });
    expect(ids(r.player), ['a', 'b', 'z']);
    final added = r.events.whereType<GuestAdded>().single;
    expect(added.name, 'Name g');
    expect(added.title, 'Zed');
    r.request(RoomOp.next);
    expect(r.player.state.index, 0);
  });

  hostTest('full role may seek and playSongs (local songs dropped)', (r) {
    r.playQueue(['a', 'b']);
    r.host.setRole('g', RoomRole.full);
    r.async.flushMicrotasks();
    r.request(RoomOp.seek, {'positionMs': 5000});
    expect(r.player.state.position, const Duration(seconds: 5));
    r.request(RoomOp.playSongs, {
      'songs': [
        const RoomSong(title: 'loc', artist: 'a').toJson(),
        const RoomSong(videoId: 'vx', title: 'x', artist: 'a').toJson(),
        const RoomSong(videoId: 'vy', title: 'y', artist: 'a').toJson(),
      ],
      'startIndex': 2,
    });
    expect(ids(r.player), ['x', 'y']);
    expect(r.player.state.index, 1);
  });

  hostTest('a request from a device not present is ignored', (r) {
    r.playQueue(['a', 'b']);
    r.host.setRole('ghost', RoomRole.full);
    r.request(RoomOp.next, const {}, null, 'ghost');
    expect(r.player.state.index, 0);
  });

  hostTest('a stale-epoch remove touches nothing and sends state', (r) {
    r.playQueue(['a', 'b', 'c']);
    r.host.setRole('g', RoomRole.full);
    r.async.flushMicrotasks();
    r.hub.sent.clear();
    r.request(RoomOp.remove, {
      'index': 1,
      'videoId': 'vb',
    }, r.player.stateEpoch - 1);
    expect(ids(r.player), ['a', 'b', 'c']);
    expect([...r.states, ...r.beats], isNotEmpty);
    // A matching one works; a mismatching video id does not.
    r.request(RoomOp.remove, {
      'index': 1,
      'videoId': 'vz',
    }, r.player.stateEpoch);
    expect(ids(r.player), ['a', 'b', 'c']);
    r.request(RoomOp.remove, {
      'index': 1,
      'videoId': 'vb',
    }, r.player.stateEpoch);
    expect(ids(r.player), ['a', 'c']);
  });

  hostTest('heartbeat every 2 s while playing, none while paused', (r) {
    r.playQueue(['a', 'b']);
    expect(r.player.state.playing, isTrue);
    r.async.elapse(const Duration(seconds: 6));
    expect(r.beats.length, inInclusiveRange(3, 4));
    r.player.pause();
    r.async.elapse(const Duration(milliseconds: 300));
    r.hub.sent.clear();
    r.async.elapse(const Duration(seconds: 10));
    expect([...r.states, ...r.beats], isEmpty);
  });

  hostTest('songs go out only when the window changes; heartbeats are '
      'beats of its revision', (r) {
    r.player.playQueue([track('a'), track('b')]);
    r.async.elapse(const Duration(milliseconds: 300));
    final first = r.states.single;
    expect(first.rev, isNotNull);
    r.hub.sent.clear();
    r.async.elapse(const Duration(seconds: 6));
    expect(r.states, isEmpty);
    expect(r.beats, isNotEmpty);
    expect(r.beats.map((b) => b.rev).toSet(), {first.rev});
    // A song moving on keeps the window: a beat with the new index.
    r.player.next();
    r.async.elapse(const Duration(milliseconds: 300));
    expect(r.states, isEmpty);
    expect(r.beats.last.index, 1);
    // An added song changes it: the full state, of a new revision.
    r.hub.sent.clear();
    r.player.appendToQueue([track('c')]);
    r.async.elapse(const Duration(milliseconds: 300));
    final next = r.states.single;
    expect(next.rev, isNot(first.rev));
    expect(next.songs.map((s) => s.videoId), ['va', 'vb', 'vc']);
    r.hub.sent.clear();
    r.async.elapse(const Duration(seconds: 2));
    expect(r.beats.single.rev, next.rev);
  });

  hostTest('a hello is answered with the full state even when unchanged', (r) {
    r.playQueue(['a', 'b']);
    r.async.elapse(const Duration(seconds: 2));
    r.hub.sent.clear();
    r.hello();
    expect(r.states.single.songs.length, 2);
  });

  hostTest('an older guest present gets full states only', (r) {
    final old = r.hub.channelFor('old');
    old.join(
      const RoomPresence(
        userId: 'uo',
        deviceId: 'old',
        name: 'Old',
        platform: 'android',
        host: false,
        beats: false,
      ),
    );
    r.async.flushMicrotasks();
    r.playQueue(['a', 'b']);
    r.async.elapse(const Duration(seconds: 6));
    expect(r.beats, isEmpty);
    expect(r.states.length, inInclusiveRange(3, 4));
    expect(r.states.every((s) => s.songs.length == 2), isTrue);
    // Once it leaves, heartbeats are beats again.
    old.leave();
    r.async.flushMicrotasks();
    r.hub.sent.clear();
    r.async.elapse(const Duration(seconds: 4));
    expect(r.states, isEmpty);
    expect(r.beats, isNotEmpty);
  });

  hostTest('a 1200-song queue sends 500 songs with the right offset', (r) {
    r.player.playQueue([
      for (var i = 0; i < 1200; i++) track('t$i'),
    ], startIndex: 700);
    r.async.elapse(const Duration(milliseconds: 300));
    final s = r.states.last;
    expect(s.songs.length, 500);
    expect(s.offset, 450);
    expect(s.index, 700);
    expect(s.songs[250].videoId, 'vt700');
  });

  hostTest('removeGuest sharing the host user id kicks, no removeMember', (r) {
    final twin = r.hub.channelFor('twin');
    twin.join(who('uh', 'twin'));
    r.async.flushMicrotasks();
    r.host.removeGuest(who('uh', 'twin'));
    r.async.flushMicrotasks();
    expect(r.hub.sent.whereType<RoomKickMsg>().single.deviceId, 'twin');
    expect(r.removed, isEmpty);
    r.host.removeGuest(who('ug', 'g'));
    r.async.flushMicrotasks();
    expect(r.removed, ['ug']);
  });

  hostTest("a blip of the host's own connection makes no left/joined "
      'events', (r) {
    expect(r.events.whereType<GuestJoined>().length, 1);
    r.hub.drop('h');
    r.async.flushMicrotasks();
    r.hub.restore('h');
    r.async.flushMicrotasks();
    expect(r.events.whereType<GuestLeft>(), isEmpty);
    expect(r.events.whereType<GuestJoined>().length, 1);
    // A guest really going still counts.
    r.guestCh.leave();
    r.async.flushMicrotasks();
    expect(r.events.whereType<GuestLeft>().length, 1);
  });

  hostTest('stop() sends end', (r) {
    r.host.stop();
    r.async.flushMicrotasks();
    expect(r.hub.sent.last, isA<RoomEndMsg>());
  });
}
