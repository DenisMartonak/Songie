import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/remote/remote_channel.dart';
import 'package:songies/remote/remote_controller.dart';
import 'package:songies/remote/remote_protocol.dart';

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

RemotePresence presenceOf(String id) => RemotePresence(
  deviceId: id,
  name: 'Device $id',
  platform: 'linux',
  appVersion: '1.0.0',
  playing: false,
);

/// A host on [hub] as device 'h' that answers `hello` with [reply] (none
/// while it is null) and records the commands it gets.
class ScriptedHost {
  ScriptedHost(this.hub, this.now) : channel = hub.channelFor('h') {
    channel.join(presenceOf('h'));
    channel.messages.listen((m) {
      switch (m) {
        case RemoteHello(:final to) when to == 'h':
          final r = reply;
          if (r != null) send(r);
        case RemoteCommand(:final to) when to == 'h':
          commands.add(m);
        default:
          break;
      }
    });
  }

  final FakeRemoteHub hub;
  final int Function() now;
  final RemoteChannel channel;
  RemoteState? reply;
  final commands = <RemoteCommand>[];

  void send(RemoteState s) => channel.send(s);
}

RemoteState stateOf({
  String from = 'h',
  int epoch = 1,
  int offset = 0,
  int index = 0,
  List<String> queue = const ['a', 'b', 'c'],
  bool playing = true,
  int positionMs = 10000,
  required int atMs,
  int? durationMs = 200000,
  double volume = 1,
  bool shuffle = false,
  RepeatMode repeat = RepeatMode.off,
}) => RemoteState(
  from: from,
  epoch: epoch,
  offset: offset,
  index: index,
  queue: queue,
  playing: playing,
  buffering: false,
  shuffle: shuffle,
  positionMs: positionMs,
  atMs: atMs,
  durationMs: durationMs,
  volume: volume,
  repeat: repeat,
);

class Rig {
  Rig(this.async) {
    host = ScriptedHost(hub, now);
    hub.channelFor('c').join(presenceOf('c'));
    for (final id in ['a', 'b', 'c', 'd']) {
      library[id] = track(id);
    }
    ctl = RemoteController(
      channel: hub.channelFor('c'),
      deviceId: 'c',
      lookup: (want) async {
        if (failLookups) throw StateError('database busy');
        return {
          for (final id in want)
            if (library[id] != null) id: library[id]!,
        };
      },
      nowMs: now,
      newId: () => 'cmd${_n++}',
    );
    ctl.links.listen(links.add);
    ctl.ended.listen(ended.add);
    async.flushMicrotasks();
  }

  final FakeAsync async;
  final hub = FakeRemoteHub();
  final library = <String, Track>{};
  var failLookups = false;
  late final ScriptedHost host;
  late final RemoteController ctl;
  final links = <RemoteLink?>[];
  final ended = <RemoteEndReason>[];
  var _n = 0;

  int now() => 1000000 + async.elapsed.inMilliseconds;

  List<RemoteHello> get hellos => hub.sent.whereType<RemoteHello>().toList();

  List<RemoteCommand> get commands =>
      hub.sent.whereType<RemoteCommand>().toList();

  /// Selects 'h' with [reply] as its answer to hello.
  void connect(RemoteState? reply) {
    host.reply = reply;
    ctl.select(presenceOf('h'));
    async.flushMicrotasks();
  }

  void flush() => async.flushMicrotasks();
}

/// Log lines printed during the current test (AppLog has no file in tests,
/// so its warnings go to [debugPrint]).
final logs = <String>[];

/// Runs [body] on a fresh [Rig]; fails if anything was logged other than
/// lines matching one of [expectLogs].
void ctlTest(
  String name,
  void Function(Rig r) body, {
  List<Pattern> expectLogs = const [],
}) {
  test(name, () {
    fakeAsync((async) {
      final r = Rig(async);
      body(r);
      r.ctl.deselect();
      async.flushMicrotasks();
    });
    final unexpected = [
      for (final l in logs)
        if (!expectLogs.any((p) => l.contains(p))) l,
    ];
    expect(unexpected, isEmpty, reason: 'unexpected log lines');
  });
}

void main() {
  setUp(() {
    logs.clear();
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = original);
  });

  ctlTest('addNextOn commands a device without a link', (r) {
    r.ctl.addNextOn(presenceOf('h'), ['a']);
    r.flush();
    expect(r.ctl.link, isNull);
    expect(r.commands.single.to, 'h');
    expect(r.commands.single.op, RemoteOp.addNext);
    expect(r.commands.single.args, {
      'ids': ['a'],
    });
    expect(r.commands.single.id, 'cmd0');
    expect(r.commands.single.epoch, isNull);
  });

  group('long lists go in windows of $kRemoteQueueWindow ids', () {
    final many = [for (var i = 0; i < 5000; i++) 'id$i'];

    List<String> idsOf(RemoteCommand c) => c.args['ids']! as List<String>;

    ctlTest('playTracks from deep in the list: the first message holds the '
        'start song, the rest follow in order', (r) {
      r.connect(stateOf(atMs: r.now()));
      r.ctl.playTracks(many, startIndex: 2500, sourcePlaylistId: 'p1');
      r.flush();
      final sent = r.commands;
      expect(sent.first.op, RemoteOp.playTracks);
      final first = idsOf(sent.first);
      expect(first.length, lessThanOrEqualTo(kRemoteQueueWindow));
      expect(first[sent.first.args['start']! as int], 'id2500');
      expect(sent.first.args['playlist'], 'p1');
      for (final c in sent.skip(1)) {
        expect(c.op, RemoteOp.addToEnd);
        expect(idsOf(c).length, lessThanOrEqualTo(kRemoteQueueWindow));
      }
      // In order from the window's start (up to 1,000 songs before the
      // start song) to the end of the list.
      final all = [for (final c in sent) ...idsOf(c)];
      final from = many.indexOf(first.first);
      expect(from, 2500 - kRemoteQueueWindow ~/ 2);
      expect(all, many.sublist(from));
    });

    ctlTest('playTracks near the start keeps the whole list', (r) {
      r.connect(stateOf(atMs: r.now()));
      r.ctl.playTracks(many, startIndex: 10);
      r.flush();
      final sent = r.commands;
      expect(sent.first.args['start'], 10);
      expect([for (final c in sent) ...idsOf(c)], many);
      expect(sent, hasLength(3));
    });

    ctlTest('playTracks near the end fills the window from before', (r) {
      r.connect(stateOf(atMs: r.now()));
      r.ctl.playTracks(many, startIndex: 4990);
      r.flush();
      final sent = r.commands;
      expect(sent, hasLength(1));
      expect(idsOf(sent.single), many.sublist(5000 - kRemoteQueueWindow));
      expect(idsOf(sent.single)[sent.single.args['start']! as int], 'id4990');
    });

    ctlTest('addNext and addToEnd are chunked in order', (r) {
      r.connect(stateOf(atMs: r.now()));
      r.ctl.addNext(many);
      r.flush();
      var sent = r.commands;
      expect(sent.map((c) => c.op).toSet(), {RemoteOp.addNext});
      expect(sent.map((c) => idsOf(c).length), [2000, 2000, 1000]);
      expect([for (final c in sent) ...idsOf(c)], many);

      r.hub.sent.clear();
      r.ctl.addToEnd(many);
      r.flush();
      sent = r.commands;
      expect(sent.map((c) => c.op).toSet(), {RemoteOp.addToEnd});
      expect([for (final c in sent) ...idsOf(c)], many);
    });

    ctlTest('playTracksOn windows the same way without a link', (r) {
      r.ctl.playTracksOn(presenceOf('h'), many, startIndex: 2500);
      r.flush();
      final sent = r.commands;
      expect(r.ctl.link, isNull);
      expect(sent.every((c) => c.to == 'h'), isTrue);
      expect(sent.first.op, RemoteOp.playTracks);
      expect(idsOf(sent.first)[sent.first.args['start']! as int], 'id2500');
      expect([for (final c in sent) ...idsOf(c)], many.sublist(1500));
    });
  });

  ctlTest('hello on select, connected on first state', (r) {
    r.host.reply = null;
    r.ctl.select(presenceOf('h'));
    r.flush();
    expect(r.hellos.map((h) => h.to), ['h']);
    expect(r.ctl.link?.status, RemoteLinkStatus.connecting);
    expect(r.ctl.link?.device.deviceId, 'h');

    r.host.send(stateOf(atMs: r.now()));
    r.flush();
    expect(r.ctl.link?.status, RemoteLinkStatus.connected);
    expect(r.links.map((l) => l?.status), [
      RemoteLinkStatus.connecting,
      RemoteLinkStatus.connected,
    ]);
    final s = r.ctl.state;
    expect(s.queue.map((t) => t.id), ['a', 'b', 'c']);
    expect(s.index, 0);
    expect(s.playing, isTrue);
    expect(s.position, const Duration(seconds: 10));
    expect(s.duration, const Duration(seconds: 200));
  });

  ctlTest('no answer in 5 s ends with noAnswer', (r) {
    r.connect(null);
    r.async.elapse(const Duration(milliseconds: 4900));
    expect(r.ctl.link?.status, RemoteLinkStatus.connecting);
    expect(r.ended, isEmpty);
    r.async.elapse(const Duration(milliseconds: 200));
    expect(r.ended, [RemoteEndReason.noAnswer]);
    expect(r.ctl.link, isNull);
    expect(r.links.last, isNull);
  });

  ctlTest('position runs on while playing and stops at the duration', (r) {
    r.connect(stateOf(atMs: r.now(), positionMs: 10000, durationMs: 12000));
    expect(r.ctl.state.position, const Duration(seconds: 10));
    final emitted = <PlayerState>[];
    r.ctl.states.listen(emitted.add);
    r.async.elapse(const Duration(seconds: 1));
    expect(r.ctl.state.position, const Duration(seconds: 11));
    expect(emitted, isNotEmpty);
    expect(emitted.last.position, const Duration(seconds: 11));
    r.async.elapse(const Duration(seconds: 2));
    expect(r.ctl.state.position, const Duration(seconds: 12));
  });

  ctlTest('position runs on uncapped below the duration', (r) {
    r.connect(stateOf(atMs: r.now(), positionMs: 10000));
    r.async.elapse(const Duration(seconds: 3));
    expect(r.ctl.state.position, const Duration(seconds: 13));
  });

  ctlTest('paused position stays', (r) {
    r.connect(stateOf(atMs: r.now(), playing: false));
    final emitted = <PlayerState>[];
    r.ctl.states.listen(emitted.add);
    r.async.elapse(const Duration(seconds: 3));
    expect(r.ctl.state.position, const Duration(seconds: 10));
    expect(emitted, isEmpty);
  });

  ctlTest('optimistic seek then corrected by the next state', (r) {
    r.connect(stateOf(atMs: r.now()));
    r.ctl.seek(const Duration(seconds: 50));
    expect(r.ctl.state.position, const Duration(seconds: 50));
    r.flush();
    final seek = r.commands.single;
    expect(seek.op, RemoteOp.seek);
    expect(seek.to, 'h');
    expect(seek.args, {'ms': 50000});
    r.async.elapse(const Duration(seconds: 1));
    expect(r.ctl.state.position, const Duration(seconds: 51));

    // The host could not seek: its state says 11 s.
    r.host.send(stateOf(atMs: r.now(), positionMs: 11000));
    r.flush();
    expect(r.ctl.state.position, const Duration(seconds: 11));
  });

  ctlTest('optimistic transport and settings', (r) {
    r.connect(stateOf(atMs: r.now()));
    r.ctl.pause();
    expect(r.ctl.state.playing, isFalse);
    r.ctl.togglePlay();
    expect(r.ctl.state.playing, isTrue);
    r.ctl.next();
    expect(r.ctl.state.index, 1);
    expect(r.ctl.state.position, Duration.zero);
    r.ctl.previous();
    r.ctl.previous();
    expect(r.ctl.state.index, 0);
    r.ctl.setVolume(0.5);
    r.ctl.setShuffle(true);
    r.ctl.setRepeat(RepeatMode.one);
    expect(r.ctl.state.volume, 0.5);
    expect(r.ctl.state.shuffle, isTrue);
    expect(r.ctl.state.repeat, RepeatMode.one);
    r.flush();
    expect(r.commands.map((c) => c.op), [
      RemoteOp.pause,
      RemoteOp.toggle,
      RemoteOp.next,
      RemoteOp.previous,
      RemoteOp.previous,
      RemoteOp.volume,
      RemoteOp.shuffle,
      RemoteOp.repeat,
    ]);
    expect(r.commands[6].args, {'on': true});
    expect(r.commands[7].args, {'mode': 'one'});
    expect({for (final c in r.commands) c.id}.length, r.commands.length);
  });

  ctlTest('queue adds wait for the host', (r) {
    r.connect(stateOf(atMs: r.now()));
    r.ctl.addToEnd(['d']);
    r.ctl.addNext(['d']);
    r.ctl.playTracks(['c', 'd'], startIndex: 1, sourcePlaylistId: 'p');
    r.flush();
    expect(r.ctl.state.queue.map((t) => t.id), ['a', 'b', 'c']);
    expect(r.commands.map((c) => c.op), [
      RemoteOp.addToEnd,
      RemoteOp.addNext,
      RemoteOp.playTracks,
    ]);
    expect(r.commands[2].args, {
      'ids': ['c', 'd'],
      'start': 1,
      'playlist': 'p',
    });
  });

  ctlTest('offset keeps indexes absolute', (r) {
    final window = [for (var i = 0; i < 10; i++) 'w$i'];
    r.connect(
      stateOf(
        atMs: r.now(),
        epoch: 7,
        offset: 1000,
        index: 1003,
        queue: window,
      ),
    );
    expect(r.ctl.state.index, 3);
    r.ctl.removeAt(5);
    expect(r.ctl.state.queue.map((t) => t.id), [
      for (final id in window)
        if (id != 'w5') id,
    ]);
    expect(r.ctl.state.index, 3);
    r.flush();
    final remove = r.commands.single;
    expect(remove.op, RemoteOp.remove);
    expect(remove.epoch, 7);
    expect(remove.args, {'index': 1005, 'track': 'w5'});

    r.ctl.playAt(2);
    expect(r.ctl.state.index, 2);
    r.ctl.move(0, 4);
    expect(r.ctl.state.queue[4].id, 'w0');
    expect(r.ctl.state.current?.id, 'w2');
    r.flush();
    expect(r.commands[1].args, {'index': 1002, 'track': 'w2'});
    expect(r.commands[1].epoch, 7);
    expect(r.commands[2].op, RemoteOp.move);
    expect(r.commands[2].args, {'from': 1000, 'to': 1004, 'track': 'w0'});
    expect(r.commands[2].epoch, 7);
  });

  ctlTest('unknown ids show as Unknown song', (r) {
    r.connect(stateOf(atMs: r.now(), queue: ['a', 'zz']));
    final q = r.ctl.state.queue;
    expect(q[0].title, 'Title a');
    expect(q[1].id, 'zz');
    expect(q[1].title, 'Unknown song');
    expect(q[1].artist, '');
    expect(q[1].source, kRemoteUnknownSource);
  });

  ctlTest('presence lost shows lost and ends after 15 s', (r) {
    r.connect(stateOf(atMs: r.now()));
    r.hub.drop('h');
    r.flush();
    expect(r.ctl.link?.status, RemoteLinkStatus.lost);
    r.async.elapse(const Duration(milliseconds: 14900));
    expect(r.ended, isEmpty);
    r.async.elapse(const Duration(milliseconds: 200));
    expect(r.ended, [RemoteEndReason.lost]);
    expect(r.ctl.link, isNull);
  });

  ctlTest('presence returns within 15 s', (r) {
    r.connect(stateOf(atMs: r.now()));
    expect(r.hellos, hasLength(1));
    r.hub.drop('h');
    r.flush();
    expect(r.ctl.link?.status, RemoteLinkStatus.lost);
    r.async.elapse(const Duration(seconds: 10));
    r.host.reply = stateOf(atMs: r.now(), positionMs: 20000);
    r.hub.restore('h');
    r.flush();
    expect(r.hellos, hasLength(2));
    expect(r.ctl.link?.status, RemoteLinkStatus.connected);
    expect(r.ctl.state.position, const Duration(seconds: 20));
    r.async.elapse(const Duration(seconds: 20));
    expect(r.ended, isEmpty);
    expect(r.ctl.link?.status, RemoteLinkStatus.connected);
  });

  ctlTest('states from another device are ignored', (r) {
    r.connect(null);
    r.hub.channelFor('x').join(presenceOf('x'));
    r.hub.channelFor('x').send(stateOf(from: 'x', atMs: r.now()));
    r.flush();
    expect(r.ctl.link?.status, RemoteLinkStatus.connecting);
    expect(r.ctl.state.queue, isEmpty);

    r.host.send(stateOf(atMs: r.now(), queue: ['a']));
    r.flush();
    r.hub.channelFor('x').send(stateOf(from: 'x', atMs: r.now()));
    r.flush();
    expect(r.ctl.state.queue.map((t) => t.id), ['a']);
  });

  ctlTest('deselect stops the ticker and sends nothing more', (r) {
    r.connect(stateOf(atMs: r.now()));
    final emitted = <PlayerState>[];
    r.ctl.states.listen(emitted.add);
    r.ctl.deselect();
    r.flush();
    expect(r.ended, [RemoteEndReason.deselected]);
    expect(r.ctl.link, isNull);
    r.hub.sent.clear();
    emitted.clear();
    r.async.elapse(const Duration(seconds: 3));
    expect(emitted, isEmpty);
    r.ctl.play();
    r.ctl.seek(const Duration(seconds: 1));
    r.ctl.removeAt(0);
    r.ctl.addToEnd(['a']);
    r.host.send(stateOf(atMs: r.now()));
    r.flush();
    r.async.elapse(const Duration(seconds: 6));
    expect(r.hub.sent.whereType<RemoteCommand>(), isEmpty);
    expect(r.hub.sent.whereType<RemoteHello>(), isEmpty);
    expect(emitted, isEmpty);
    expect(r.ended, [RemoteEndReason.deselected]);
  });
  ctlTest('previous mid-song restarts the current one, as the host does', (r) {
    r.connect(stateOf(atMs: r.now(), index: 1, positionMs: 10000));
    r.ctl.previous();
    expect(r.ctl.state.index, 1);
    expect(r.ctl.state.position, Duration.zero);

    r.async.elapse(const Duration(seconds: 2));
    expect(r.ctl.state.position, const Duration(seconds: 2));
    r.ctl.previous();
    expect(r.ctl.state.index, 0);
    expect(r.ctl.state.position, Duration.zero);
    r.flush();
    expect(r.commands.map((c) => c.op), [RemoteOp.previous, RemoteOp.previous]);
  });

  ctlTest('position runs on from arrival, whatever the host clock says', (r) {
    // The host's clock is 1 s behind this one (or the state took 1 s).
    r.connect(stateOf(atMs: r.now() - 1000, positionMs: 10000));
    expect(r.ctl.state.position, const Duration(seconds: 10));
    r.async.elapse(const Duration(seconds: 1));
    expect(r.ctl.state.position, const Duration(seconds: 11));
  });

  ctlTest('while lost, commands are neither sent nor guessed', (r) {
    r.connect(stateOf(atMs: r.now()));
    r.hub.drop('h');
    r.flush();
    expect(r.ctl.link?.status, RemoteLinkStatus.lost);
    final before = r.ctl.state;
    r.ctl.pause();
    r.ctl.seek(const Duration(seconds: 50));
    r.ctl.next();
    r.ctl.setVolume(0.2);
    r.ctl.removeAt(0);
    r.ctl.addToEnd(['d']);
    r.flush();
    expect(r.ctl.state.playing, before.playing);
    expect(r.ctl.state.position, before.position);
    expect(r.ctl.state.index, before.index);
    expect(r.ctl.state.volume, before.volume);
    expect(r.ctl.state.queue, hasLength(3));
    // Nothing went out (a dropped sender's messages are not recorded
    // either, so check the controller asked for nothing).
    r.hub.restore('h');
    r.flush();
    expect(r.commands, isEmpty);
  });

  ctlTest('select and deselect emit the empty state', (r) {
    final emitted = <PlayerState>[];
    r.ctl.states.listen(emitted.add);
    r.connect(stateOf(atMs: r.now()));
    expect(emitted.first.queue, isEmpty);
    expect(emitted.last.queue, hasLength(3));
    r.ctl.deselect();
    r.flush();
    expect(emitted.last.queue, isEmpty);
    expect(emitted.last.index, -1);
    expect(r.ctl.state.queue, isEmpty);
  });

  ctlTest('a failing lookup shows placeholders and logs it', (r) {
    r.failLookups = true;
    r.connect(stateOf(atMs: r.now(), queue: ['a']));
    expect(r.ctl.state.queue.single.title, 'Unknown song');
    expect(r.ctl.link?.status, RemoteLinkStatus.connected);
    expect(logs.where((l) => l.contains('lookup failed')), hasLength(1));
  }, expectLogs: ['remote controller: lookup failed']);
}
