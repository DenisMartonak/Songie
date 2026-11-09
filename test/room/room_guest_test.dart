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
import 'package:songies/room/room_guest.dart';
import 'package:songies/room/room_host.dart';
import 'package:songies/room/room_protocol.dart';

import '../helpers/fake_audio_backend.dart';
import '../helpers/fake_room_hub.dart';

const kSongMs = 200000;

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
  durationMs: kSongMs,
  unavailable: false,
  searchText: 'title $id artist',
);

/// Resolves every track to a file, except the ids in [failing].
class _Resolver extends TrackResolver {
  final failing = <String>{};
  final resolved = <String>[];

  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async {
    resolved.add(t.id);
    if (failing.contains(t.id)) {
      return const Err(Failure(FailureKind.unsupported, 'stream failed'));
    }
    return Ok(FileSource('/music/${t.id}.mp3'));
  }

  @override
  Future<void> prefetch(Track t) async {}

  @override
  void invalidate(Track t) {}
}

RoomPresence who(String user, String device, {bool host = false, int? v}) =>
    RoomPresence(
      userId: user,
      deviceId: device,
      name: 'Name $device',
      platform: 'linux',
      host: host,
      v: v ?? kRoomProtocol,
    );

Future<List<Track?>> tracksFor(List<RoomSong> songs) async => [
  for (final s in songs) s.local ? null : track(s.videoId!.substring(1)),
];

class Rig {
  Rig(this.async, {bool withHost = true}) {
    hostPlayer = PlayerService(hostBackend, _Resolver(), random: Random(3));
    guestPlayer = PlayerService(guestBackend, guestResolver, random: Random(4));
    host = RoomHost(
      channel: hub.channelFor('h'),
      player: hostPlayer,
      me: who('uh', 'h', host: true),
      tracksFor: tracksFor,
      nowMs: () => 1000000 + async.elapsed.inMilliseconds,
    );
    guest = RoomGuest(
      channel: hub.channelFor('g'),
      player: guestPlayer,
      me: who('ug', 'g'),
      tracksFor: tracksFor,
      // Five minutes off the host's clock.
      now: () => DateTime(2026, 11, 9, 12, 5).add(async.elapsed),
    );
    view = RoomGuestView(guest);
    subs = [
      guest.ended.listen(ended.add),
      guest.cantPlay.listen(cantPlay.add),
      view.notices.listen(notices.add),
    ];
    if (withHost) host.start();
    async.flushMicrotasks();
  }

  final FakeAsync async;
  final hub = FakeRoomHub();
  final hostBackend = FakeAudioBackend();
  final guestBackend = FakeAudioBackend();
  final guestResolver = _Resolver();
  late final PlayerService hostPlayer;
  late final PlayerService guestPlayer;
  late final RoomHost host;
  late final RoomGuest guest;
  late final RoomGuestView view;
  late final List<StreamSubscription<Object>> subs;
  final ended = <RoomLeaveReason>[];
  final cantPlay = <String>[];
  final notices = <String>[];

  void hostPlays(List<Track> queue, {int start = 0}) {
    hostPlayer.playQueue(queue, startIndex: start);
    settle();
  }

  void join() {
    guest.start();
    settle();
  }

  void settle() => async.elapse(const Duration(milliseconds: 300));

  String? get guestSong => guestPlayer.state.current?.id;
  int get guestMs => guestPlayer.state.position.inMilliseconds;
  int get hostMs => hostPlayer.state.position.inMilliseconds;
  List<String> get guestSeeks => [
    for (final c in guestBackend.calls)
      if (c.startsWith('seek:')) c,
  ];
  List<RoomRequestMsg> get requests =>
      hub.sent.whereType<RoomRequestMsg>().toList();

  void dispose() {
    guest.leave();
    host.stop();
    async.flushMicrotasks();
    for (final s in subs) {
      s.cancel();
    }
    hostPlayer.dispose();
    guestPlayer.dispose();
    async.flushMicrotasks();
  }
}

void guestTest(String name, void Function(Rig r) body, {bool withHost = true}) {
  test(name, () {
    fakeAsync((async) {
      final r = Rig(async, withHost: withHost);
      body(r);
      r.dispose();
    });
  });
}

void main() {
  setUp(() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = original);
  });

  guestTest('joining switches from its own song to the host song and '
      'position', (r) {
    r.guestPlayer.playQueue([track('x'), track('y')]);
    r.settle();
    expect(r.guestSong, 'x');
    r.hostPlays([track('a'), track('b'), track('c')], start: 1);
    r.hostBackend.setPosition(const Duration(seconds: 42));
    r.join();
    expect(r.guestSong, 'b');
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.guestMs, closeTo(42000, 1000));
    expect([for (final t in r.guestPlayer.state.queue) t.id], ['a', 'b', 'c']);
  });

  guestTest("the host's next moves the guest", (r) {
    r.hostPlays([track('a'), track('b'), track('c')]);
    r.join();
    expect(r.guestSong, 'a');
    r.hostPlayer.next();
    r.settle();
    expect(r.guestSong, 'b');
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('a host seek by 30 s moves the guest', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.hostBackend.setPosition(const Duration(seconds: 10));
    r.join();
    expect(r.guestMs, closeTo(10000, 1000));
    r.hostPlayer.seek(const Duration(seconds: 40));
    r.settle();
    expect(r.guestMs, closeTo(40000, 1000));
  });

  guestTest('host pause and play are followed', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.join();
    r.hostPlayer.pause();
    r.settle();
    expect(r.guestPlayer.state.playing, isFalse);
    r.hostPlayer.play();
    r.settle();
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('600 ms of drift is left alone, 1500 ms is one seek', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.hostBackend.setPosition(const Duration(seconds: 20));
    r.join();
    r.guestBackend.setPosition(Duration(milliseconds: r.hostMs + 600));
    r.guestBackend.clearCalls();
    r.async.elapse(const Duration(seconds: 5));
    expect(r.guestSeeks, isEmpty);
    r.guestBackend.setPosition(Duration(milliseconds: r.hostMs + 1500));
    r.async.elapse(const Duration(seconds: 5));
    expect(r.guestSeeks, ['seek:${r.hostMs}']);
    expect(r.guestMs, closeTo(r.hostMs, 1000));
  });

  guestTest('the host replaying the same playlist reloads the guest', (r) {
    r.hostPlays([track('a'), track('b')], start: 1);
    r.join();
    expect(r.guestSong, 'b');
    final before = r.guestPlayer.queueEpoch;
    r.hostPlays([track('a'), track('b')]);
    expect(r.guestPlayer.queueEpoch, greaterThan(before));
    expect(r.guestSong, 'a');
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('a host local file pauses the guest with one cantPlay, then it '
      'follows at the next YouTube song', (r) {
    r.hostPlays([track('a'), track('L', yt: false), track('b')]);
    r.join();
    expect(r.guestSong, 'a');
    r.hostPlayer.next();
    r.settle();
    expect(r.hostPlayer.state.current?.id, 'L');
    expect(r.guestPlayer.state.playing, isFalse);
    r.async.elapse(const Duration(seconds: 20));
    expect(r.cantPlay, ['Title L']);
    expect(r.guestPlayer.state.playing, isFalse);
    r.hostPlayer.next();
    r.settle();
    expect(r.guestSong, 'b');
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.cantPlay, ['Title L']);
  });

  guestTest('a host that starts on a local file is waited for', (r) {
    r.guestPlayer.playQueue([track('x')]);
    r.hostPlays([track('L', yt: false), track('a')]);
    r.join();
    expect(r.guestPlayer.state.playing, isFalse);
    expect(r.cantPlay, ['Title L']);
    r.hostPlayer.next();
    r.settle();
    expect(r.guestSong, 'a');
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('a stream failing on the guest pauses it until the next song, '
      'without retrying on each heartbeat', (r) {
    r.guestResolver.failing.add('b');
    r.hostPlays([track('a'), track('b'), track('c')]);
    r.join();
    expect(r.guestSong, 'a');
    r.hostPlayer.next();
    r.settle();
    expect(r.hostPlayer.state.current?.id, 'b');
    expect(r.guestPlayer.state.playing, isFalse);
    expect(r.cantPlay, ['Title b']);
    final tries = r.guestResolver.resolved.where((id) => id == 'b').length;
    expect(tries, 1);
    r.async.elapse(const Duration(seconds: 20)); // 10 heartbeats
    expect(r.guestResolver.resolved.where((id) => id == 'b').length, tries);
    expect(r.guestPlayer.state.playing, isFalse);
    expect(r.cantPlay, ['Title b']);
    r.hostPlayer.next();
    r.settle();
    expect(r.guestSong, 'c');
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('a guest that reached the next song first is not sent back', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.hostBackend.setPosition(const Duration(milliseconds: kSongMs - 600));
    r.join();
    expect(r.guestSong, 'a');
    r.guestBackend.complete();
    r.async.flushMicrotasks();
    expect(r.guestSong, 'b');
    r.async.elapse(const Duration(seconds: 2));
    expect(r.guestSong, 'b');
    expect(r.guestResolver.resolved.where((id) => id == 'a').length, 1);
  });

  guestTest("a listener's next sends nothing; a queue guest's addToEnd sends "
      'one song and one local-files notice', (r) {
    r.hostPlays([track('a')]);
    r.join();
    expect(r.guest.role, RoomRole.listener);
    r.view.next();
    r.view.addToEnd([track('z')]);
    r.async.flushMicrotasks();
    expect(r.requests, isEmpty);
    r.host.setRole('g', RoomRole.queue);
    r.async.flushMicrotasks();
    expect(r.guest.role, RoomRole.queue);
    r.view.addToEnd([track('z'), track('L', yt: false)]);
    r.view.next();
    r.async.flushMicrotasks();
    final sent = r.requests.single;
    expect(sent.op, RoomOp.addToEnd);
    expect(sent.from, 'g');
    expect((sent.args['songs']! as List).length, 1);
    expect(r.notices, ["Local files can't be shared in a room"]);
    r.settle();
    expect([for (final t in r.hostPlayer.state.queue) t.id], ['a', 'z']);
  });

  guestTest("a full guest's playAt names the host's index, video id and "
      'epoch', (r) {
    r.hostPlays([track('a'), track('L', yt: false), track('b')]);
    r.join();
    r.host.setRole('g', RoomRole.full);
    r.async.flushMicrotasks();
    // The guest's queue has no local song: its index 1 is the host's 2.
    expect([for (final t in r.view.state.queue) t.id], ['a', 'b']);
    r.view.playAt(1);
    r.settle();
    final sent = r.requests.single;
    expect(sent.args, {'index': 2, 'videoId': 'vb'});
    expect(sent.epoch, r.hostPlayer.stateEpoch);
    expect(r.hostPlayer.state.current?.id, 'b');
    expect(r.guestSong, 'b');
  });

  guestTest('setVolume stays local', (r) {
    r.hostPlays([track('a')]);
    r.join();
    r.view.setVolume(0.5);
    r.async.flushMicrotasks();
    expect(r.guestPlayer.state.volume, 0.5);
    expect(r.requests, isEmpty);
  });

  guestTest('kick ends with removed and the player keeps playing', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.join();
    r.host.removeGuest(who('ug', 'g'));
    r.settle();
    expect(r.ended, [RoomLeaveReason.removed]);
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.guestSong, 'a');
    expect(r.hub.channelFor('h').present.map((p) => p.deviceId), ['h']);
  });

  guestTest('end ends with ended', (r) {
    r.hostPlays([track('a')]);
    r.join();
    r.host.stop();
    r.settle();
    expect(r.ended, [RoomLeaveReason.ended]);
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('a host gone for 15 s ends with hostGone, still playing', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.join();
    r.hub.drop('h');
    r.async.elapse(const Duration(seconds: 14));
    expect(r.ended, isEmpty);
    r.async.elapse(const Duration(seconds: 2));
    expect(r.ended, [RoomLeaveReason.hostGone]);
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.guestSong, 'a');
  });

  guestTest('a host back within 15 s keeps the room', (r) {
    r.hostPlays([track('a')]);
    r.join();
    r.hub.drop('h');
    r.async.elapse(const Duration(seconds: 10));
    r.hub.restore('h');
    r.async.elapse(const Duration(seconds: 20));
    expect(r.ended, isEmpty);
  });

  guestTest('a host on another protocol version ends with outdated', (r) {
    r.hub.channelFor('h2').join(who('uh', 'h2', host: true, v: 2));
    r.guest.start();
    r.settle();
    expect(r.ended, [RoomLeaveReason.outdated]);
  }, withHost: false);

  guestTest('no state within 15 s ends with unreachable', (r) {
    r.guestPlayer.playQueue([track('x')]);
    r.guest.start();
    r.async.elapse(const Duration(seconds: 14));
    expect(r.ended, isEmpty);
    expect(r.hub.sent.whereType<RoomHelloMsg>().length, inInclusiveRange(7, 8));
    r.async.elapse(const Duration(seconds: 2));
    expect(r.ended, [RoomLeaveReason.unreachable]);
    expect(r.guestPlayer.state.playing, isFalse); // paused on start
  }, withHost: false);

  guestTest('hello stops after the first state', (r) {
    r.hostPlays([track('a')]);
    r.join();
    r.hub.sent.clear();
    r.async.elapse(const Duration(seconds: 10));
    expect(r.hub.sent.whereType<RoomHelloMsg>(), isEmpty);
  });
}
