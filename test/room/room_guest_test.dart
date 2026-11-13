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
      guestPlayer.trackStarts.listen((t) => guestStarts.add(t.id)),
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

  /// Songs the guest's player started (each one a recorded play).
  final guestStarts = <String>[];

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
    // No other song was loaded, played or counted in the failed one's stead.
    expect(r.guestBackend.sources, isNot(contains('/music/c.mp3')));
    expect(r.guestStarts, ['a']);
    // An edit of the host's queue keeps the failed song failed.
    r.hostPlayer.appendToQueue([track('d')]);
    r.async.elapse(const Duration(seconds: 4));
    expect(r.guestResolver.resolved.where((id) => id == 'b').length, tries);
    expect(r.guestBackend.sources, isNot(contains('/music/c.mp3')));
    expect(r.cantPlay, ['Title b']);
    r.hostPlayer.next();
    r.settle();
    expect(r.guestSong, 'c');
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('a stream dying mid-song silences the guest without loading the '
      'next song', (r) {
    r.hostPlays([track('a'), track('b'), track('c')]);
    r.join();
    r.hostPlayer.next();
    r.settle();
    expect(r.guestSong, 'b');
    r.guestBackend.clearCalls();
    r.guestBackend.emitError();
    r.async.elapse(const Duration(seconds: 20)); // 10 heartbeats
    expect(r.guestPlayer.state.playing, isFalse);
    expect(r.cantPlay, ['Title b']);
    expect(r.guestBackend.sources, isEmpty);
    expect(r.guestBackend.calls, isNot(contains('play')));
    expect(r.guestStarts, ['a', 'b']);
    r.hostPlayer.next();
    r.settle();
    expect(r.guestSong, 'c');
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('an addToEnd on the host updates the guest queue without '
      'restarting its song', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.hostBackend.setPosition(const Duration(seconds: 20));
    r.join();
    expect(r.guestSong, 'a');
    final epoch = r.guestPlayer.queueEpoch;
    r.guestBackend.clearCalls();
    r.hostPlayer.appendToQueue([track('z')]);
    r.async.elapse(const Duration(seconds: 3));
    expect([for (final t in r.guestPlayer.state.queue) t.id], ['a', 'b', 'z']);
    expect(r.guestSong, 'a');
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.guestBackend.sources, isEmpty);
    expect(r.guestBackend.calls, isNot(contains('play')));
    expect(r.guestBackend.calls, isNot(contains('seek:0')));
    expect(r.guestPlayer.queueEpoch, epoch);
    expect(r.guestMs, closeTo(20000, 1000));
    // It still follows the edited queue.
    r.hostPlayer.playAt(2);
    r.settle();
    expect(r.guestSong, 'z');
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

  guestTest('a host present that sends no state within 15 s ends with '
      'unreachable', (r) {
    r.guestPlayer.playQueue([track('x')]);
    r.hub.channelFor('h2').join(who('uh', 'h2', host: true));
    r.guest.start();
    r.async.elapse(const Duration(seconds: 14));
    expect(r.ended, isEmpty);
    expect(r.hub.sent.whereType<RoomHelloMsg>().length, inInclusiveRange(7, 8));
    r.async.elapse(const Duration(seconds: 2));
    expect(r.ended, [RoomLeaveReason.unreachable]);
    expect(r.guestPlayer.state.playing, isFalse); // paused once the host showed
  }, withHost: false);

  guestTest('a stale room (its host never there) leaves the music playing '
      'and ends as stale', (r) {
    r.guestPlayer.playQueue([track('x')]);
    r.settle();
    r.guest.start();
    r.async.elapse(const Duration(seconds: 14));
    expect(r.ended, isEmpty);
    expect(r.guestPlayer.state.playing, isTrue);
    r.async.elapse(const Duration(seconds: 2));
    expect(r.ended, [RoomLeaveReason.stale]);
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.guestSong, 'x');
  }, withHost: false);

  guestTest("a channel that never joins ends with unreachable, the guest's "
      'music untouched', (r) {
    r.guestPlayer.playQueue([track('x')]);
    r.settle();
    r.hub.drop('g');
    r.guest.start();
    r.async.elapse(const Duration(seconds: 16));
    expect(r.ended, [RoomLeaveReason.unreachable]);
    expect(r.guestPlayer.state.playing, isTrue);
  }, withHost: false);

  guestTest("the guest's own music plays on until the host shows", (r) {
    r.guestPlayer.playQueue([track('x')]);
    r.settle();
    r.guest.start();
    r.async.elapse(const Duration(seconds: 5));
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.guestSong, 'x');
    r.host.start();
    r.hostPlays([track('a')]);
    r.settle();
    expect(r.guestSong, 'a');
    expect(r.ended, isEmpty);
  }, withHost: false);

  guestTest('a local hold (headphones out) keeps the guest quiet until it '
      'resumes locally, then it rejoins in step', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.hostBackend.setPosition(const Duration(seconds: 20));
    r.join();
    expect(r.guestPlayer.state.playing, isTrue);
    r.view.holdLocally();
    r.settle();
    expect(r.guestPlayer.state.playing, isFalse);
    r.async.elapse(const Duration(seconds: 10)); // 5 heartbeats
    expect(r.guestPlayer.state.playing, isFalse);
    // A listener's play rejoins locally: no request to the host.
    r.view.play();
    r.settle();
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.guestSong, 'a');
    expect(r.guestMs, closeTo(r.hostMs, 1000));
    expect(r.requests, isEmpty);
    // Held again: the host's next is not played here until it rejoins.
    r.view.holdLocally();
    r.settle();
    r.hostPlayer.next();
    r.async.elapse(const Duration(seconds: 4));
    expect(r.guestPlayer.state.playing, isFalse);
    r.view.togglePlay();
    r.settle();
    expect(r.guestSong, 'b');
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.requests, isEmpty);
  });

  guestTest('an interruption that ends with resume rejoins at the '
      "host's position", (r) {
    r.hostPlays([track('a'), track('b')]);
    r.join();
    r.view.holdLocally();
    r.settle();
    r.hostBackend.setPosition(const Duration(seconds: 30));
    r.async.elapse(const Duration(seconds: 6)); // heartbeats carry 30 s
    expect(r.guestPlayer.state.playing, isFalse);
    expect(r.guestMs, lessThan(5000));
    r.guestBackend.clearCalls();
    r.view.resumeLocally();
    r.settle();
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.guestSeeks, isNotEmpty);
    expect(r.guestMs, closeTo(r.hostMs, 1000));
  });

  guestTest("a full guest's play while held rejoins and asks the host to "
      'play', (r) {
    r.hostPlays([track('a')]);
    r.join();
    r.host.setRole('g', RoomRole.full);
    r.async.flushMicrotasks();
    r.view.holdLocally();
    r.settle();
    r.view.play();
    r.settle();
    expect(r.guestPlayer.state.playing, isTrue);
    expect(r.requests.single.op, RoomOp.play);
  });

  guestTest("a full guest's playSongs sends at most a window around the "
      'start', (r) {
    r.hostPlays([track('a')]);
    r.join();
    r.host.setRole('g', RoomRole.full);
    r.async.flushMicrotasks();
    final many = [for (var i = 0; i < 1200; i++) track('t$i')];
    r.view.playTracks(many, startIndex: 1000);
    r.async.flushMicrotasks();
    final sent = r.requests.single;
    final songs = sent.args['songs']! as List;
    final start = sent.args['startIndex']! as int;
    expect(songs.length, kRoomQueueWindow);
    expect((songs[start] as Map)['videoId'], 'vt1000');
    expect((songs.first as Map)['videoId'], 'vt700');
    r.view.playTracks(many.take(10).toList(), startIndex: 3);
    r.async.flushMicrotasks();
    expect((r.requests.last.args['songs']! as List).length, 10);
    expect(r.requests.last.args['startIndex'], 3);
  });

  guestTest('a guest follows beats, and asks again for a full state it '
      'lost', (r) {
    r.hostPlays([track('a'), track('b')]);
    r.join();
    expect(r.guestSong, 'a');
    // Heartbeats are beats; they keep the guest in step.
    r.hostBackend.setPosition(const Duration(seconds: 40));
    r.async.elapse(const Duration(seconds: 3));
    expect(r.hub.sent.whereType<RoomBeatMsg>(), isNotEmpty);
    expect(r.guestMs, closeTo(r.hostMs, 1000));
    // The full state for an added song is lost on the way.
    r.hub.lose = (m) => m is RoomStateMsg;
    r.hostPlayer.appendToQueue([track('c')]);
    r.settle();
    r.hub.lose = null;
    r.hub.sent.clear();
    expect(r.guestPlayer.state.queue.length, 2);
    // The next beat has a revision this guest does not hold: it says hello
    // (once) and gets the full state.
    r.async.elapse(const Duration(seconds: 2));
    r.settle();
    expect(r.hub.sent.whereType<RoomHelloMsg>().length, 1);
    expect(r.guestPlayer.state.queue.map((t) => t.id), ['a', 'b', 'c']);
    expect(r.guestSong, 'a');
    expect(r.guestPlayer.state.playing, isTrue);
  });

  guestTest('hello stops after the first state', (r) {
    r.hostPlays([track('a')]);
    r.join();
    r.hub.sent.clear();
    r.async.elapse(const Duration(seconds: 10));
    expect(r.hub.sent.whereType<RoomHelloMsg>(), isEmpty);
  });
}
