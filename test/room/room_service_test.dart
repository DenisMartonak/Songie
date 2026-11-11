import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/room/room_backend.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/room/room_service.dart';

import '../helpers/fake_audio_backend.dart';
import '../helpers/fake_room_hub.dart';

Track track(String id) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'youtube',
  ytVideoId: 'v$id',
  title: 'Title $id',
  artist: 'Artist',
  durationMs: 200000,
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

class FakeBackend implements RoomBackend {
  RoomJoinError? joinFails;
  final calls = <String>[];

  @override
  Future<OpenedRoom> open() async {
    calls.add('open');
    return const OpenedRoom(roomId: 'room1', code: 'ABCD2345');
  }

  @override
  Future<String> join(String code) async {
    calls.add('join $code');
    final f = joinFails;
    if (f != null) throw RoomJoinException(f);
    return 'room1';
  }

  @override
  Future<void> leave(String roomId) async => calls.add('leave $roomId');

  @override
  Future<void> remove(String roomId, String userId) async =>
      calls.add('remove $roomId $userId');

  @override
  Future<void> end(String roomId) async => calls.add('end $roomId');
}

Future<List<Track?>> tracksFor(List<RoomSong> songs) async => [
  for (final s in songs) s.local ? null : track(s.videoId!.substring(1)),
];

/// One device: its player and its service.
class Device {
  Device(this.id, FakeRoomHub hub, this.backend) {
    player = PlayerService(FakeAudioBackend(), _Resolver(), random: Random(3));
    service = RoomService(
      backend: backend,
      channelFor: (_) => hub.channelFor(id),
      player: player,
      tracksFor: tracksFor,
      deviceId: id,
      platform: 'linux',
    );
    service.notices.listen((n) {
      if (n is RoomNoticeText) notices.add(n.text);
    });
  }

  final String id;
  final FakeBackend backend;
  late final PlayerService player;
  late final RoomService service;
  final notices = <String>[];
}

void inRoomTest(
  String name,
  void Function(FakeAsync async, Device host, Device guest, FakeBackend backend)
  body,
) {
  test(name, () {
    fakeAsync((async) {
      final hub = FakeRoomHub();
      final backend = FakeBackend();
      final host = Device('h', hub, backend);
      final guest = Device('g', hub, backend);
      body(async, host, guest, backend);
      host.player.dispose();
      guest.player.dispose();
      async.flushMicrotasks();
    });
  });
}

/// Runs [f] to completion on the fake clock.
T done<T>(FakeAsync async, Future<T> f) {
  T? out;
  Object? error;
  f.then(
    (v) => out = v,
    onError: (Object e) {
      error = e;
    },
  );
  async.elapse(const Duration(seconds: 1));
  if (error != null) throw error!;
  return out as T;
}

void main() {
  setUp(() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = original);
  });

  inRoomTest('open makes a hosting room with a code and a link', (
    async,
    host,
    guest,
    backend,
  ) {
    done(async, host.service.open(userId: 'u1', name: 'Host'));
    final s = host.service.status as RoomHosting;
    expect(s.code, 'ABCD2345');
    expect(s.link, 'https://denismartonak.github.io/Songie/r/ABCD2345');
    expect(s.people.single.deviceId, 'h');
    expect(host.service.guestView, isNull);
  });

  inRoomTest('open with a queue starts it', (async, host, guest, backend) {
    done(
      async,
      host.service.open(
        userId: 'u1',
        name: 'Host',
        play: [track('a'), track('b')],
      ),
    );
    expect(host.player.state.queue.map((t) => t.id), ['a', 'b']);
    expect(host.player.state.playing, isTrue);
  });

  inRoomTest('a guest joins and follows, as a listener', (
    async,
    host,
    guest,
    backend,
  ) {
    done(
      async,
      host.service.open(userId: 'u1', name: 'Host', play: [track('a')]),
    );
    // The same account on a second device.
    done(async, guest.service.join('ABCD2345', userId: 'u1', name: 'Guest'));
    final g = guest.service.status as RoomGuesting;
    expect(g.host.deviceId, 'h');
    expect(g.host.name, 'Host');
    expect(g.role, RoomRole.listener);
    expect(guest.service.guestView, isNotNull);
    expect(backend.calls, contains('join ABCD2345'));
    expect(host.notices, ['Guest joined']);
    final h = host.service.status as RoomHosting;
    expect(h.people.map((p) => p.deviceId).toSet(), {'h', 'g'});
    expect(guest.player.state.current?.id, 'a');
  });

  for (final (kind, text) in [
    (RoomJoinError.full, 'This room is full'),
    (RoomJoinError.notFound, 'Room not found'),
    (RoomJoinError.ended, 'This room has ended'),
    (RoomJoinError.offline, "Couldn't reach the room"),
  ]) {
    inRoomTest('joining fails with ${kind.name}', (
      async,
      host,
      guest,
      backend,
    ) {
      backend.joinFails = kind;
      done(async, guest.service.join('ABCD2345', userId: 'u2', name: 'G'));
      expect(guest.service.status, isA<RoomIdle>());
      expect(guest.notices, [text]);
      expect(guest.service.guestView, isNull);
    });
  }

  inRoomTest('joining signed out offers to sign in', (
    async,
    host,
    guest,
    backend,
  ) {
    final seen = <RoomNotice>[];
    guest.service.notices.listen(seen.add);
    done(async, guest.service.join('ABCD2345', userId: '', name: 'G'));
    final n = seen.single as RoomNoticeText;
    expect(n.text, 'You need a Songies account to join a room');
    expect(n.signIn, isTrue);
    expect(backend.calls, isEmpty);
  });

  inRoomTest('end() ends both, and the guest keeps playing', (
    async,
    host,
    guest,
    backend,
  ) {
    done(
      async,
      host.service.open(userId: 'u1', name: 'Host', play: [track('a')]),
    );
    done(async, guest.service.join('ABCD2345', userId: 'u2', name: 'Guest'));
    expect(guest.player.state.playing, isTrue);
    done(async, host.service.end());
    expect(host.service.status, isA<RoomIdle>());
    expect(guest.service.status, isA<RoomIdle>());
    expect(guest.notices, ['The room ended']);
    expect(guest.player.state.playing, isTrue);
    expect(guest.service.guestView, isNull);
    expect(backend.calls, contains('end room1'));
    // The guest's own skip-unplayable setting is given back.
    expect(guest.player.skipUnplayable, isTrue);
  });

  inRoomTest('a role change tells the guest', (async, host, guest, backend) {
    done(async, host.service.open(userId: 'u1', name: 'Host'));
    done(async, guest.service.join('ABCD2345', userId: 'u1', name: 'Guest'));
    done(async, host.service.setRole('g', RoomRole.full));
    expect(guest.notices, ['You now have full control']);
    expect((guest.service.status as RoomGuesting).role, RoomRole.full);
    expect((host.service.status as RoomHosting).roles, {'g': RoomRole.full});
    done(async, host.service.setRole('g', RoomRole.queue));
    done(async, host.service.setRole('g', RoomRole.listener));
    expect(guest.notices.skip(1), [
      'You can now add songs',
      'You can listen only',
    ]);
  });

  test('a guest sees every guest\'s role, by device', () {
    fakeAsync((async) {
      final hub = FakeRoomHub();
      final backend = FakeBackend();
      final host = Device('h', hub, backend);
      final guest = Device('g', hub, backend);
      final other = Device('g2', hub, backend);
      done(async, host.service.open(userId: 'u1', name: 'Host'));
      done(async, guest.service.join('ABCD2345', userId: 'u2', name: 'G'));
      done(async, other.service.join('ABCD2345', userId: 'u3', name: 'G2'));
      done(async, host.service.setRole('g2', RoomRole.full));
      done(async, host.service.setRole('g', RoomRole.queue));
      final g = guest.service.status as RoomGuesting;
      expect(g.role, RoomRole.queue);
      expect(g.roles, {'g': RoomRole.queue, 'g2': RoomRole.full});
      // Another guest's role change tells this one nothing.
      expect(guest.notices, ['You can now add songs']);
      host.player.dispose();
      guest.player.dispose();
      other.player.dispose();
      async.flushMicrotasks();
    });
  });

  inRoomTest('removing a guest sends it away', (async, host, guest, backend) {
    done(async, host.service.open(userId: 'u1', name: 'Host'));
    done(async, guest.service.join('ABCD2345', userId: 'u2', name: 'Guest'));
    final g = (host.service.status as RoomHosting).people.firstWhere(
      (p) => p.deviceId == 'g',
    );
    done(async, host.service.remove(g));
    expect(guest.service.status, isA<RoomIdle>());
    expect(guest.notices, ['You were removed from the room']);
    expect(backend.calls, contains('remove room1 u2'));
    expect(host.notices, ['Guest joined', 'Guest left']);
  });

  inRoomTest('removing a guest of the host\'s own account keeps the member', (
    async,
    host,
    guest,
    backend,
  ) {
    done(async, host.service.open(userId: 'u1', name: 'Host'));
    done(async, guest.service.join('ABCD2345', userId: 'u1', name: 'Guest'));
    final g = (host.service.status as RoomHosting).people.firstWhere(
      (p) => p.deviceId == 'g',
    );
    done(async, host.service.remove(g));
    expect(guest.service.status, isA<RoomIdle>());
    expect(backend.calls.where((c) => c.startsWith('remove')), isEmpty);
  });

  inRoomTest('open or join while in a room throws', (
    async,
    host,
    guest,
    backend,
  ) {
    done(async, host.service.open(userId: 'u1', name: 'Host'));
    expect(
      () => host.service.open(userId: 'u1', name: 'Host'),
      throwsStateError,
    );
    expect(
      () => host.service.join('ABCD2345', userId: 'u1', name: 'Host'),
      throwsStateError,
    );
    done(async, guest.service.join('ABCD2345', userId: 'u2', name: 'Guest'));
    expect(
      () => guest.service.open(userId: 'u2', name: 'Guest'),
      throwsStateError,
    );
  });

  inRoomTest('signedOut() while guesting leaves the room', (
    async,
    host,
    guest,
    backend,
  ) {
    done(async, host.service.open(userId: 'u1', name: 'Host'));
    done(async, guest.service.join('ABCD2345', userId: 'u2', name: 'Guest'));
    done(async, guest.service.signedOut());
    expect(guest.service.status, isA<RoomIdle>());
    expect(backend.calls, contains('leave room1'));
    expect(guest.notices, isEmpty);
    expect(guest.player.skipUnplayable, isTrue);
  });

  inRoomTest('signedOut() while hosting ends the room', (
    async,
    host,
    guest,
    backend,
  ) {
    done(async, host.service.open(userId: 'u1', name: 'Host'));
    done(async, guest.service.join('ABCD2345', userId: 'u2', name: 'Guest'));
    done(async, host.service.signedOut());
    expect(host.service.status, isA<RoomIdle>());
    expect(backend.calls, contains('end room1'));
    expect(guest.service.status, isA<RoomIdle>());
  });

  inRoomTest('a host that never shows (a stale room) ends the join as '
      'ended, with the music left playing', (async, host, guest, backend) {
    guest.player.playQueue([track('x')]);
    async.elapse(const Duration(milliseconds: 300));
    final f = guest.service.join('ABCD2345', userId: 'u2', name: 'Guest');
    var finished = false;
    f.then((_) => finished = true);
    async.elapse(const Duration(seconds: 20));
    expect(finished, isTrue);
    expect(guest.service.status, isA<RoomIdle>());
    expect(guest.notices, ['This room has ended']);
    expect(backend.calls, contains('leave room1'));
    expect(guest.player.state.playing, isTrue);
    expect(guest.player.state.current?.id, 'x');
  });

  inRoomTest("a guest of the host's own account leaves with leave_room, and "
      'the room stays open', (async, host, guest, backend) {
    done(
      async,
      host.service.open(userId: 'u1', name: 'Host', play: [track('a')]),
    );
    done(async, guest.service.join('ABCD2345', userId: 'u1', name: 'Guest'));
    done(async, guest.service.leave());
    expect(guest.service.status, isA<RoomIdle>());
    expect(backend.calls, contains('leave room1'));
    expect(backend.calls, isNot(contains('end room1')));
    expect(host.service.status, isA<RoomHosting>());
    expect(guest.notices, isEmpty);
  });

  inRoomTest('the host sees what guests add', (async, host, guest, backend) {
    done(
      async,
      host.service.open(userId: 'u1', name: 'Host', play: [track('a')]),
    );
    done(async, guest.service.join('ABCD2345', userId: 'u2', name: 'Guest'));
    done(async, host.service.setRole('g', RoomRole.queue));
    done(async, guest.service.guestView!.addToEnd([track('b')]));
    async.elapse(const Duration(seconds: 1));
    expect(host.player.state.queue.map((t) => t.id), ['a', 'b']);
    expect(host.notices, contains('Guest added Title b'));
  });
}
