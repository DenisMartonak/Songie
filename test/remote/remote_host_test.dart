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
import 'package:songies/remote/remote_channel.dart';
import 'package:songies/remote/remote_controller.dart';
import 'package:songies/remote/remote_host.dart';
import 'package:songies/remote/remote_protocol.dart';

import '../helpers/fake_audio_backend.dart';
import '../helpers/fake_remote_hub.dart';

Track track(String id) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist',
  durationMs: 0,
  unavailable: false,
  searchText: 'title $id artist',
);

class _Resolver extends TrackResolver {
  /// While set, every resolve waits for it: holds the player's lock.
  Completer<void>? gate;

  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async {
    final g = gate;
    if (g != null) await g.future;
    return Ok(FileSource('/music/${t.id}.mp3'));
  }

  @override
  Future<void> prefetch(Track t) async {}

  @override
  void invalidate(Track t) {}
}

List<String> ids(List<Track> q) => [for (final t in q) t.id];

/// Counts [updatePresence] calls on the host's channel.
class SpyChannel implements RemoteChannel {
  SpyChannel(this._inner);

  final RemoteChannel _inner;
  final List<RemotePresence> updates = [];

  @override
  Future<void> join(RemotePresence me) => _inner.join(me);

  @override
  Future<void> updatePresence(RemotePresence me) {
    updates.add(me);
    return _inner.updatePresence(me);
  }

  @override
  Stream<List<RemotePresence>> get presences => _inner.presences;

  @override
  List<RemotePresence> get present => _inner.present;

  @override
  Future<void> send(RemoteMessage m) => _inner.send(m);

  @override
  Stream<RemoteMessage> get messages => _inner.messages;

  @override
  Future<void> leave() => _inner.leave();
}

RemotePresence _presenceOf(String id) => RemotePresence(
  deviceId: id,
  name: 'Device $id',
  platform: 'linux',
  appVersion: '1.0.0',
  playing: false,
);

class Rig {
  Rig(this.async, {bool controller = true}) {
    backend = FakeAudioBackend();
    player = PlayerService(backend, resolver, random: Random(3));
    channel = SpyChannel(hub.channelFor('h'));
    ctl = hub.channelFor('c');
    host = RemoteHost(
      channel: channel,
      player: player,
      presence: (s) => RemotePresence(
        deviceId: 'h',
        name: 'Host',
        platform: 'linux',
        appVersion: '1.0.0',
        playing: s.playing,
        title: s.current?.title,
      ),
      lookup: (want) async {
        if (failLookups > 0) {
          failLookups--;
          throw StateError('database busy');
        }
        return {
          for (final id in want)
            if (library[id] != null) id: library[id]!,
        };
      },
      nowMs: () => 1000000 + async.elapsed.inMilliseconds,
    );
    for (final id in ['a', 'b', 'c', 'd', 'e', 'y']) {
      library[id] = track(id);
    }
    if (controller) ctl.join(_presenceOf('c'));
    host.start();
    async.flushMicrotasks();
  }

  final FakeAsync async;
  final hub = FakeRemoteHub();
  final library = <String, Track>{};
  final resolver = _Resolver();

  /// How many lookups still throw before they work again.
  var failLookups = 0;
  late final FakeAudioBackend backend;
  late final PlayerService player;
  late final SpyChannel channel;
  late final RemoteChannel ctl;
  late final RemoteHost host;
  var _n = 0;

  List<RemoteState> get states => hub.sent.whereType<RemoteState>().toList();

  /// Plays [queue] (by id) and lets every state it caused go out.
  void playQueue(List<String> queue, {int start = 0}) {
    player.playQueue([for (final id in queue) track(id)], startIndex: start);
    settle();
  }

  /// Lets pending debounced state go out, then forgets what was sent.
  void settle() {
    async.elapse(const Duration(milliseconds: 300));
    hub.sent.clear();
  }

  void command(
    RemoteOp op, [
    Map<String, Object?> args = const {},
    int? epoch,
    String to = 'h',
  ]) {
    ctl.send(
      RemoteCommand(to: to, id: 'cmd${_n++}', op: op, args: args, epoch: epoch),
    );
    async.flushMicrotasks();
  }

  void dispose() {
    host.stop();
    async.flushMicrotasks();
    player.dispose();
    async.flushMicrotasks();
  }
}

void hostTest(
  String name,
  void Function(Rig r) body, {
  bool controller = true,
}) {
  test(name, () {
    fakeAsync((async) {
      final r = Rig(async, controller: controller);
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

  group('each op reaches the player', () {
    hostTest('play', (r) {
      r.playQueue(['a', 'b']);
      r.player.pause();
      r.settle();
      expect(r.player.state.playing, isFalse);
      r.command(RemoteOp.play);
      expect(r.player.state.playing, isTrue);
    });

    hostTest('pause', (r) {
      r.playQueue(['a', 'b']);
      expect(r.player.state.playing, isTrue);
      r.command(RemoteOp.pause);
      expect(r.player.state.playing, isFalse);
    });

    hostTest('toggle', (r) {
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.toggle);
      expect(r.player.state.playing, isFalse);
      r.command(RemoteOp.toggle);
      expect(r.player.state.playing, isTrue);
    });

    hostTest('next', (r) {
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.next);
      expect(r.player.state.current?.id, 'b');
    });

    hostTest('previous', (r) {
      r.playQueue(['a', 'b'], start: 1);
      r.command(RemoteOp.previous);
      expect(r.player.state.current?.id, 'a');
    });

    hostTest('seek', (r) {
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.seek, {'ms': 30000});
      expect(r.player.state.position, const Duration(seconds: 30));
    });

    hostTest('volume', (r) {
      r.command(RemoteOp.volume, {'v': 0.25});
      expect(r.player.state.volume, 0.25);
    });

    hostTest('shuffle', (r) {
      r.playQueue(['a', 'b', 'c']);
      r.command(RemoteOp.shuffle, {'on': true});
      expect(r.player.state.shuffle, isTrue);
      r.command(RemoteOp.shuffle, {'on': false});
      expect(r.player.state.shuffle, isFalse);
    });

    hostTest('repeat', (r) {
      r.command(RemoteOp.repeat, {'mode': 'one'});
      expect(r.player.state.repeat, RepeatMode.one);
      r.command(RemoteOp.repeat, {'mode': 'all'});
      expect(r.player.state.repeat, RepeatMode.all);
      r.command(RemoteOp.repeat, {'mode': 'all'});
      expect(r.player.state.repeat, RepeatMode.all);
      r.command(RemoteOp.repeat, {'mode': 'off'});
      expect(r.player.state.repeat, RepeatMode.off);
    });

    hostTest('playAt', (r) {
      r.playQueue(['a', 'b', 'c']);
      r.command(RemoteOp.playAt, {
        'index': 2,
        'track': 'c',
      }, r.player.queueEpoch);
      expect(r.player.state.current?.id, 'c');
      expect(r.player.state.playing, isTrue);
    });

    hostTest('remove', (r) {
      r.playQueue(['a', 'b', 'c']);
      r.command(RemoteOp.remove, {
        'index': 1,
        'track': 'b',
      }, r.player.queueEpoch);
      expect(ids(r.player.state.queue), ['a', 'c']);
    });

    hostTest('move', (r) {
      r.playQueue(['a', 'b', 'c']);
      r.command(RemoteOp.move, {
        'from': 0,
        'to': 2,
        'track': 'a',
      }, r.player.queueEpoch);
      expect(ids(r.player.state.queue), ['b', 'c', 'a']);
      expect(r.player.state.index, 2);
      expect(r.player.state.current?.id, 'a');
    });

    hostTest('playTracks', (r) {
      r.playQueue(['e']);
      final before = r.player.queueEpoch;
      r.command(RemoteOp.playTracks, {
        'ids': ['a', 'b', 'c'],
        'start': 1,
        'playlist': 'p1',
      });
      expect(ids(r.player.state.queue), ['a', 'b', 'c']);
      expect(r.player.state.current?.id, 'b');
      expect(r.player.state.playing, isTrue);
      expect(r.player.state.sourcePlaylistId, 'p1');
      expect(r.player.queueEpoch, before + 1);
    });

    hostTest('addNext', (r) {
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.addNext, {
        'ids': ['c', 'd'],
      });
      expect(ids(r.player.state.queue), ['a', 'c', 'd', 'b']);
    });

    hostTest('addToEnd', (r) {
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.addToEnd, {
        'ids': ['c'],
      });
      expect(ids(r.player.state.queue), ['a', 'b', 'c']);
    });
  });

  hostTest('commands for another device are ignored', (r) {
    r.playQueue(['a', 'b']);
    r.command(RemoteOp.pause, const {}, null, 'z');
    r.command(RemoteOp.next, const {}, null, 'z');
    r.async.elapse(const Duration(seconds: 1));
    expect(r.player.state.playing, isTrue);
    expect(r.player.state.current?.id, 'a');
    r.ctl.send(const RemoteHello(to: 'z'));
    r.async.flushMicrotasks();
    expect(r.states, isEmpty);
  });

  hostTest('hello is answered at once with full state', (r) {
    r.playQueue(['a', 'b', 'c'], start: 1);
    r.player.setVolume(0.5);
    r.player.cycleRepeat();
    r.settle();
    r.ctl.send(const RemoteHello(to: 'h'));
    r.async.flushMicrotasks();
    expect(r.states, hasLength(1));
    final s = r.states.single;
    expect(s.from, 'h');
    expect(s.epoch, r.player.queueEpoch);
    expect(s.offset, 0);
    expect(s.index, 1);
    expect(s.queue, ['a', 'b', 'c']);
    expect(s.playing, isTrue);
    expect(s.buffering, isFalse);
    expect(s.volume, 0.5);
    expect(s.shuffle, isFalse);
    expect(s.repeat, RepeatMode.all);
    expect(s.positionMs, 0);
    expect(s.atMs, 1000000 + r.async.elapsed.inMilliseconds);
    expect(s.notice, isNull);
  });

  hostTest('no state while alone', controller: false, (r) {
    r.player.playQueue([track('a'), track('b')]);
    r.async.elapse(const Duration(seconds: 1));
    r.player.next();
    r.player.setVolume(0.3);
    r.async.elapse(const Duration(seconds: 12));
    expect(r.player.state.playing, isTrue);
    expect(r.states, isEmpty);
  });

  hostTest('changes are debounced to one state per 250 ms', (r) {
    for (var i = 1; i <= 5; i++) {
      r.player.setVolume(i / 10);
      r.async.elapse(const Duration(milliseconds: 20));
    }
    expect(r.states, isEmpty);
    r.async.elapse(const Duration(milliseconds: 160));
    expect(r.states, hasLength(1));
    expect(r.states.single.volume, 0.5);
    r.async.elapse(const Duration(seconds: 2));
    expect(r.states, hasLength(1));
  });

  hostTest('heartbeat every 5 s while playing, none while paused', (r) {
    r.playQueue(['a', 'b']);
    expect(r.player.state.playing, isTrue);
    r.async.elapse(const Duration(seconds: 20));
    expect(r.states, hasLength(4));
    r.player.pause();
    r.settle();
    r.async.elapse(const Duration(seconds: 20));
    expect(r.states, isEmpty);
  });

  hostTest('stale epoch is ignored with fresh state', (r) {
    r.playQueue(['a', 'b', 'c']);
    final seen = r.player.queueEpoch;
    r.playQueue(['a', 'b', 'c']);
    expect(r.player.queueEpoch, isNot(seen));
    r.command(RemoteOp.remove, {'index': 1, 'track': 'b'}, seen);
    r.command(RemoteOp.playAt, {'index': 2, 'track': 'c'}, seen);
    r.command(RemoteOp.move, {'from': 0, 'to': 2, 'track': 'a'}, seen);
    expect(ids(r.player.state.queue), ['a', 'b', 'c']);
    expect(r.player.state.current?.id, 'a');
    r.async.elapse(const Duration(milliseconds: 300));
    expect(r.states, isNotEmpty);
    expect(r.states.last.epoch, r.player.queueEpoch);
  });

  hostTest('rapid removes hit the tapped songs', (r) {
    r.playQueue(['a', 'b', 'c', 'd', 'e']);
    final epoch = r.player.queueEpoch;
    r.ctl.send(
      RemoteCommand(
        to: 'h',
        id: 'r1',
        op: RemoteOp.remove,
        args: const {'index': 2, 'track': 'c'},
        epoch: epoch,
      ),
    );
    r.ctl.send(
      RemoteCommand(
        to: 'h',
        id: 'r2',
        op: RemoteOp.remove,
        args: const {'index': 4, 'track': 'e'},
        epoch: epoch,
      ),
    );
    r.async.flushMicrotasks();
    expect(ids(r.player.state.queue), ['a', 'b', 'd', 'e']);
    r.async.elapse(const Duration(milliseconds: 300));
    expect(r.states, isNotEmpty);
    expect(r.states.last.queue, ['a', 'b', 'd', 'e']);
    r.command(RemoteOp.remove, {'index': 3, 'track': 'e'}, epoch);
    expect(ids(r.player.state.queue), ['a', 'b', 'd']);
  });

  hostTest('out-of-range indexes are no-ops with fresh state', (r) {
    r.playQueue(['a', 'b', 'c']);
    final epoch = r.player.queueEpoch;
    r.command(RemoteOp.remove, {'index': 3, 'track': 'c'}, epoch);
    r.command(RemoteOp.remove, {'index': -1, 'track': 'a'}, epoch);
    r.command(RemoteOp.playAt, {'index': 99, 'track': 'a'}, epoch);
    r.command(RemoteOp.move, {'from': 0, 'to': 3, 'track': 'a'}, epoch);
    r.command(RemoteOp.move, {'from': 0, 'to': -1, 'track': 'a'}, epoch);
    r.command(RemoteOp.playTracks, {
      'ids': ['a'],
      'start': 1,
    });
    r.command(RemoteOp.playTracks, {
      'ids': ['a'],
      'start': -1,
    });
    expect(ids(r.player.state.queue), ['a', 'b', 'c']);
    expect(r.player.state.current?.id, 'a');
    expect(r.player.queueEpoch, epoch);
    r.async.elapse(const Duration(milliseconds: 300));
    expect(r.states, isNotEmpty);
  });

  group('a long list sent in windows arrives in order', () {
    final many = [for (var i = 0; i < 5000; i++) 'id$i'];

    RemoteController controllerOn(Rig r) {
      for (final id in many) {
        r.library[id] = track(id);
      }
      return RemoteController(
        channel: r.hub.channelFor('c'),
        deviceId: 'c',
        lookup: (_) async => const {},
      );
    }

    hostTest('addNext parts follow each other after the current song', (r) {
      final ctl = controllerOn(r);
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.addNext, {
        'ids': ['q'],
      });
      r.library['q'] = track('q');
      r.async.elapse(const Duration(seconds: 1));
      expect(ids(r.player.state.queue), ['a', 'q', 'b']);
      ctl.addNextOn(_presenceOf('h'), many);
      r.async.elapse(const Duration(seconds: 1));
      expect(r.hub.sent.whereType<RemoteCommand>().length, greaterThan(3));
      expect(ids(r.player.state.queue), ['a', 'q', ...many, 'b']);
      ctl.dispose();
    });

    hostTest('playTracks then addToEnd parts give the windowed list', (r) {
      final ctl = controllerOn(r);
      r.playQueue(['a']);
      ctl.playTracksOn(_presenceOf('h'), many, startIndex: 2500);
      r.async.elapse(const Duration(seconds: 1));
      expect(ids(r.player.state.queue), many.sublist(1500));
      expect(r.player.state.current?.id, 'id2500');
      ctl.dispose();
    });
  });

  group('unknown ids are retried until they arrive', () {
    hostTest('an id that arrives at 2 s is queued', (r) {
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.addNext, {
        'ids': ['x'],
      });
      r.async.elapse(const Duration(seconds: 2));
      expect(ids(r.player.state.queue), ['a', 'b']);
      r.library['x'] = track('x');
      r.async.elapse(const Duration(milliseconds: 600));
      expect(ids(r.player.state.queue), ['a', 'x', 'b']);
    });

    hostTest('an id that never arrives is dropped at 5 s', (r) {
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.addToEnd, {
        'ids': ['y', 'zz'],
      });
      r.async.elapse(const Duration(milliseconds: 4900));
      expect(ids(r.player.state.queue), ['a', 'b']);
      r.async.elapse(const Duration(milliseconds: 200));
      expect(ids(r.player.state.queue), ['a', 'b', 'y']);
    });

    hostTest('playTracks starts at the first kept id at or after start', (r) {
      r.playQueue(['e']);
      r.command(RemoteOp.playTracks, {
        'ids': ['a', 'zz', 'c'],
        'start': 1,
      });
      r.async.elapse(const Duration(milliseconds: 5100));
      expect(ids(r.player.state.queue), ['a', 'c']);
      expect(r.player.state.current?.id, 'c');
    });

    hostTest('playTracks with nothing kept does nothing', (r) {
      r.playQueue(['e']);
      final epoch = r.player.queueEpoch;
      r.command(RemoteOp.playTracks, {
        'ids': ['a', 'zz'],
        'start': 1,
      });
      r.async.elapse(const Duration(milliseconds: 5100));
      expect(ids(r.player.state.queue), ['e']);
      expect(r.player.queueEpoch, epoch);
      expect(r.states, isNotEmpty);
    });

    hostTest('later commands wait their turn', (r) {
      r.playQueue(['a', 'b']);
      r.command(RemoteOp.addToEnd, {
        'ids': ['zz'],
      });
      r.command(RemoteOp.addToEnd, {
        'ids': ['c'],
      });
      r.async.elapse(const Duration(seconds: 1));
      expect(ids(r.player.state.queue), ['a', 'b']);
      r.async.elapse(const Duration(seconds: 5));
      expect(ids(r.player.state.queue), ['a', 'b', 'c']);
    });
  });

  hostTest('queue window', (r) {
    final many = [for (var i = 0; i < 3000; i++) 't$i'];
    r.playQueue(many, start: 2900);
    void hello() {
      r.hub.sent.clear();
      r.ctl.send(const RemoteHello(to: 'h'));
      r.async.flushMicrotasks();
    }

    hello();
    var s = r.states.single;
    expect(s.offset, 1000);
    expect(s.queue, hasLength(2000));
    expect(s.index, 2900);
    expect(s.queue[s.index - s.offset], 't2900');

    r.player.playAt(100);
    r.settle();
    hello();
    s = r.states.single;
    expect(s.offset, 0);
    expect(s.queue, hasLength(2000));
    expect(s.queue[s.index - s.offset], 't100');

    r.player.playAt(1500);
    r.settle();
    hello();
    s = r.states.single;
    expect(s.offset, 500);
    expect(s.queue[s.index - s.offset], 't1500');
  });

  hostTest('a failing command answers with state and doesn\'t throw', (r) {
    r.command(RemoteOp.seek, {'ms': 1000});
    r.async.elapse(const Duration(milliseconds: 300));
    expect(r.states, hasLength(1));
    r.hub.sent.clear();

    r.backend.failNext.add('setVolume');
    r.command(RemoteOp.volume, {'v': 0.4});
    r.async.elapse(const Duration(milliseconds: 300));
    expect(r.states, hasLength(1));

    r.hub.sent.clear();
    r.library.clear();
    r.command(RemoteOp.addNext, {
      'ids': ['a'],
    });
    r.async.elapse(const Duration(seconds: 6));
    expect(r.player.state.queue, isEmpty);
    expect(r.states, isNotEmpty);
  });

  test('a lookup that always throws answers with state after 5 s', () {
    fakeAsync((async) {
      final hub = FakeRemoteHub();
      final player = PlayerService(FakeAudioBackend(), _Resolver());
      final host = RemoteHost(
        channel: hub.channelFor('h'),
        player: player,
        presence: (s) => _presenceOf('h'),
        lookup: (_) async => throw StateError('db closed'),
      );
      hub.channelFor('c').join(_presenceOf('c'));
      host.start();
      async.flushMicrotasks();
      hub
          .channelFor('c')
          .send(
            const RemoteCommand(
              to: 'h',
              id: '1',
              op: RemoteOp.addNext,
              args: {
                'ids': ['a'],
              },
            ),
          );
      async.elapse(const Duration(milliseconds: 5300));
      expect(player.state.queue, isEmpty);
      expect(hub.sent.whereType<RemoteState>(), hasLength(1));
      host.stop();
      player.dispose();
      async.flushMicrotasks();
    });
  });

  hostTest('presence follows play and song changes only', (r) {
    r.playQueue(['a', 'b']);
    expect(r.channel.updates, isNotEmpty);
    expect(r.channel.updates.last.playing, isTrue);
    expect(r.channel.updates.last.title, 'Title a');
    expect(r.ctl.present.firstWhere((p) => p.deviceId == 'h').playing, isTrue);

    r.channel.updates.clear();
    r.player.setVolume(0.2);
    r.player.seek(const Duration(seconds: 10));
    r.player.cycleRepeat();
    r.settle();
    expect(r.channel.updates, isEmpty);

    r.player.pause();
    r.settle();
    expect(r.channel.updates, hasLength(1));
    expect(r.channel.updates.single.playing, isFalse);

    r.channel.updates.clear();
    r.player.playAt(1);
    r.settle();
    expect(r.channel.updates, isNotEmpty);
    expect(r.channel.updates.last.title, 'Title b');
    expect(r.channel.updates.last.playing, isTrue);
  });

  hostTest('stop leaves the channel and answers nothing', (r) {
    r.playQueue(['a']);
    r.host.stop();
    r.async.flushMicrotasks();
    expect(r.ctl.present.map((p) => p.deviceId), ['c']);
    r.async.elapse(const Duration(seconds: 10));
    expect(r.states, isEmpty);
  });
  group('edits checked when their turn comes', () {
    hostTest('a local removeAt held in the lock shifts nothing remote', (r) {
      r.playQueue(['a', 'b', 'c', 'd', 'e']);
      final epoch = r.player.queueEpoch;
      // A slow start holds the player's lock; a local swipe of 'a' waits in
      // it while the controller removes 'c', which it saw at index 2.
      r.resolver.gate = Completer<void>();
      r.player.next();
      r.async.flushMicrotasks();
      r.player.removeAt(0);
      r.command(RemoteOp.remove, {'index': 2, 'track': 'c'}, epoch);
      expect(ids(r.player.state.queue), ['a', 'b', 'c', 'd', 'e']);
      r.resolver.gate!.complete();
      r.resolver.gate = null;
      r.async.elapse(const Duration(milliseconds: 300));
      // Index 2 now holds 'd': the remote remove is a no-op, never 'd'.
      expect(ids(r.player.state.queue), ['b', 'c', 'd', 'e']);
      expect(r.states, isNotEmpty);
      expect(r.states.last.queue, ['b', 'c', 'd', 'e']);
    });

    hostTest('a pending playQueue is never matched by old indexes', (r) {
      r.playQueue(['a', 'b', 'c']);
      final old = r.player.queueEpoch;
      r.resolver.gate = Completer<void>();
      r.player.next();
      r.async.flushMicrotasks();
      r.player.playQueue([track('x'), track('y'), track('z')]);
      expect(r.player.queueEpoch, old + 1);

      // State sent while the new queue waits keeps the old epoch with the
      // old queue.
      r.hub.sent.clear();
      r.ctl.send(const RemoteHello(to: 'h'));
      r.async.flushMicrotasks();
      expect(r.states.single.epoch, old);
      expect(r.states.single.queue, ['a', 'b', 'c']);

      // A controller pairing the new epoch with an old index, and one with
      // the old epoch: neither touches the new queue.
      r.command(RemoteOp.remove, {'index': 1, 'track': 'b'}, old + 1);
      r.command(RemoteOp.playAt, {'index': 2, 'track': 'c'}, old + 1);
      r.command(RemoteOp.move, {'from': 0, 'to': 2, 'track': 'a'}, old + 1);
      r.command(RemoteOp.remove, {'index': 2, 'track': 'c'}, old);
      r.resolver.gate!.complete();
      r.resolver.gate = null;
      r.async.elapse(const Duration(milliseconds: 300));
      expect(ids(r.player.state.queue), ['x', 'y', 'z']);
      expect(r.player.state.current?.id, 'x');
      expect(r.states.last.epoch, old + 1);
      expect(r.states.last.queue, ['x', 'y', 'z']);
    });
  });

  group('seeks', () {
    hostTest('a small seek while paused sends state', (r) {
      r.playQueue(['a']);
      r.player.pause();
      r.settle();
      r.player.seek(const Duration(seconds: 1));
      r.async.elapse(const Duration(milliseconds: 300));
      expect(r.states, hasLength(1));
      expect(r.states.single.positionMs, 1000);
    });

    hostTest('ticks send nothing; a 1 s seek while playing does', (r) {
      r.playQueue(['a']);
      var pos = Duration.zero;
      for (var i = 0; i < 10; i++) {
        r.async.elapse(const Duration(milliseconds: 200));
        pos += const Duration(milliseconds: 200);
        r.backend.setPosition(pos);
      }
      r.async.elapse(const Duration(milliseconds: 100));
      expect(r.states, isEmpty);
      r.player.seek(pos + const Duration(seconds: 1));
      r.async.elapse(const Duration(milliseconds: 300));
      expect(r.states, hasLength(1));
      expect(r.states.single.positionMs, pos.inMilliseconds + 1000);
    });
  });

  hostTest('a transient lookup error is retried', (r) {
    r.playQueue(['a', 'b']);
    r.failLookups = 2;
    r.command(RemoteOp.addNext, {
      'ids': ['c'],
    });
    r.async.elapse(const Duration(milliseconds: 600));
    expect(ids(r.player.state.queue), ['a', 'b']);
    r.async.elapse(const Duration(milliseconds: 500));
    expect(ids(r.player.state.queue), ['a', 'c', 'b']);
  });

  test('a presence that throws leaves the host stopped, ready to retry', () {
    fakeAsync((async) {
      final hub = FakeRemoteHub();
      final player = PlayerService(FakeAudioBackend(), _Resolver());
      var calls = 0;
      final host = RemoteHost(
        channel: hub.channelFor('h'),
        player: player,
        presence: (s) {
          if (calls++ == 0) throw StateError('no device name yet');
          return _presenceOf('h');
        },
        lookup: (_) async => const {},
      );
      final ctl = hub.channelFor('c')..join(_presenceOf('c'));
      host.start();
      async.flushMicrotasks();
      expect(ctl.present.map((p) => p.deviceId), ['c']);
      ctl.send(const RemoteHello(to: 'h'));
      async.flushMicrotasks();
      expect(hub.sent.whereType<RemoteState>(), isEmpty);

      host.start();
      async.flushMicrotasks();
      expect(ctl.present.map((p) => p.deviceId), containsAll(['h', 'c']));
      ctl.send(const RemoteHello(to: 'h'));
      async.flushMicrotasks();
      expect(hub.sent.whereType<RemoteState>(), hasLength(1));
      host.stop();
      player.dispose();
      async.flushMicrotasks();
    });
  });

  test('a device in a room ignores commands, and says so in its presence', () {
    fakeAsync((async) {
      final hub = FakeRemoteHub();
      final player = PlayerService(FakeAudioBackend(), _Resolver());
      var inRoom = true;
      final host = RemoteHost(
        channel: SpyChannel(hub.channelFor('h')),
        player: player,
        presence: (s) => RemotePresence(
          deviceId: 'h',
          name: 'Host',
          platform: 'linux',
          appVersion: '1.0.0',
          playing: s.playing,
          inRoom: inRoom,
        ),
        lookup: (_) async => const {},
      );
      final ctl = hub.channelFor('c')..join(_presenceOf('c'));
      host.start();
      async.flushMicrotasks();
      player.playQueue([track('a')]);
      async.flushMicrotasks();
      ctl.send(const RemoteCommand(to: 'h', id: 'x', op: RemoteOp.pause));
      async.elapse(const Duration(seconds: 1));
      expect(player.state.playing, isTrue);
      expect(ctl.present.firstWhere((p) => p.deviceId == 'h').inRoom, isTrue);

      inRoom = false;
      host.refreshPresence();
      async.flushMicrotasks();
      expect(ctl.present.firstWhere((p) => p.deviceId == 'h').inRoom, isFalse);
      ctl.send(const RemoteCommand(to: 'h', id: 'y', op: RemoteOp.pause));
      async.elapse(const Duration(seconds: 1));
      expect(player.state.playing, isFalse);
      host.stop();
      player.dispose();
      async.flushMicrotasks();
    });
  });
}
