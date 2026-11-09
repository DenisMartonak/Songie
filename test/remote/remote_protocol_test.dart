import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/remote/remote_protocol.dart';

Object? wire(RemoteMessage m) => jsonDecode(jsonEncode(m.toJson()));

RemoteState state({
  int? durationMs = 1000,
  ({String title, String reason})? notice,
}) => RemoteState(
  from: 'a',
  epoch: 3,
  offset: 5,
  index: 6,
  queue: const ['x', 'y'],
  playing: true,
  buffering: false,
  shuffle: true,
  positionMs: 40,
  atMs: 99,
  durationMs: durationMs,
  volume: 0.5,
  repeat: RepeatMode.all,
  notice: notice,
);

RemoteCommand cmd(
  RemoteOp op, [
  Map<String, Object?> args = const {},
  int? epoch,
]) => RemoteCommand(to: 'b', id: 'c1', op: op, args: args, epoch: epoch);

void main() {
  group('round trips', () {
    void checkState(RemoteState s) {
      final r = RemoteMessage.decode(s.event, wire(s)) as RemoteState;
      expect(r.from, s.from);
      expect(r.epoch, s.epoch);
      expect(r.offset, s.offset);
      expect(r.index, s.index);
      expect(r.queue, s.queue);
      expect(r.playing, s.playing);
      expect(r.buffering, s.buffering);
      expect(r.shuffle, s.shuffle);
      expect(r.positionMs, s.positionMs);
      expect(r.atMs, s.atMs);
      expect(r.durationMs, s.durationMs);
      expect(r.volume, s.volume);
      expect(r.repeat, s.repeat);
      expect(r.notice?.title, s.notice?.title);
      expect(r.notice?.reason, s.notice?.reason);
    }

    test('state', () {
      checkState(state());
      checkState(state(durationMs: null));
      checkState(state(notice: (title: 'T', reason: 'R')));
      expect(state().event, 'state');
    });

    test('command', () {
      final cases = <RemoteCommand>[
        cmd(RemoteOp.play),
        cmd(RemoteOp.pause),
        cmd(RemoteOp.toggle),
        cmd(RemoteOp.next),
        cmd(RemoteOp.previous),
        cmd(RemoteOp.seek, {'ms': 10}),
        cmd(RemoteOp.volume, {'v': 0.3}),
        cmd(RemoteOp.shuffle, {'on': true}),
        cmd(RemoteOp.repeat, {'mode': 'one'}),
        cmd(RemoteOp.playAt, {'index': 2, 'track': 't'}, 4),
        cmd(RemoteOp.remove, {'index': 2, 'track': 't'}, 4),
        cmd(RemoteOp.move, {'from': 1, 'to': 3, 'track': 't'}, 4),
        cmd(RemoteOp.playTracks, {
          'ids': ['a', 'b'],
          'start': 1,
          'playlist': 'p',
        }),
        cmd(RemoteOp.playTracks, {
          'ids': ['a'],
          'start': 0,
          'playlist': null,
        }),
        cmd(RemoteOp.addNext, {
          'ids': ['a'],
        }),
        cmd(RemoteOp.addToEnd, {
          'ids': ['a'],
        }),
      ];
      for (final c in cases) {
        final r = RemoteMessage.decode(c.event, wire(c)) as RemoteCommand;
        expect(r.to, c.to);
        expect(r.id, c.id);
        expect(r.op, c.op);
        expect(r.args, c.args);
        expect(r.epoch, c.epoch);
      }
      expect(cases.first.event, 'command');
    });

    test('hello', () {
      final h = RemoteHello(to: 'z');
      final r = RemoteMessage.decode(h.event, wire(h)) as RemoteHello;
      expect(r.to, 'z');
      expect(h.event, 'hello');
    });

    test('presence', () {
      const p = RemotePresence(
        deviceId: 'd',
        name: 'Desk',
        platform: 'linux',
        appVersion: '1.0',
        playing: true,
        title: null,
      );
      final r = RemotePresence.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
      expect(r.deviceId, 'd');
      expect(r.name, 'Desk');
      expect(r.platform, 'linux');
      expect(r.appVersion, '1.0');
      expect(r.playing, true);
      expect(r.title, isNull);
      expect(r.compatible, true);
      expect(r.inRoom, false);
    });

    test('inRoom round-trips and an old payload decodes with false', () {
      const p = RemotePresence(
        deviceId: 'd',
        name: 'Desk',
        platform: 'linux',
        appVersion: '1.0',
        playing: false,
        inRoom: true,
      );
      final json = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      expect(RemotePresence.fromJson(json)!.inRoom, true);
      expect(json['v'], kRemoteProtocol);
      json.remove('inRoom');
      expect(RemotePresence.fromJson(json)!.inRoom, false);
      json['inRoom'] = 'yes';
      expect(RemotePresence.fromJson(json)!.inRoom, false);
    });
  });

  group('rejects', () {
    Map<String, Object?> sj() => state().toJson();
    Map<String, Object?> cj(
      RemoteOp op,
      Map<String, Object?> args, [
      int? epoch,
    ]) => cmd(op, args, epoch).toJson();

    test('malformed input', () {
      expect(RemoteMessage.decode('state', {...sj(), 'v': 2}), isNull);
      expect(RemoteMessage.decode('ping', {'v': 1}), isNull);
      expect(
        RemoteMessage.decode('command', {
          ...cj(RemoteOp.play, {}),
          'op': 'explode',
        }),
        isNull,
      );
      expect(
        RemoteMessage.decode('command', cj(RemoteOp.seek, {'ms': '10'})),
        isNull,
      );
      expect(
        RemoteMessage.decode('command', cj(RemoteOp.seek, {'ms': -1})),
        isNull,
      );
      expect(
        RemoteMessage.decode('command', cj(RemoteOp.volume, {'v': 1.5})),
        isNull,
      );
      expect(
        RemoteMessage.decode(
          'command',
          cj(RemoteOp.playAt, {'index': 1, 'track': 't'}),
        ),
        isNull,
      );
      expect(
        RemoteMessage.decode(
          'command',
          cj(RemoteOp.playTracks, {'ids': [], 'start': 0}),
        ),
        isNull,
      );
      expect(RemoteMessage.decode('state', 'nope'), isNull);
      expect(RemoteMessage.decode('state', null), isNull);
      expect(
        RemoteMessage.decode('state', {
          ...sj(),
          'queue': [1, 2],
        }),
        isNull,
      );
    });
  });

  group('presence keeps other versions', () {
    test('v 2 decodes as incompatible', () {
      final p = RemotePresence.fromJson({
        'v': 2,
        'deviceId': 'd',
        'name': 'Desk',
        'platform': 'linux',
        'appVersion': '2.0',
        'playing': false,
        'title': null,
      })!;
      expect(p.compatible, false);
      expect(p.v, 2);
    });

    test('missing deviceId is null', () {
      expect(
        RemotePresence.fromJson({
          'v': 1,
          'name': 'Desk',
          'platform': 'x',
          'appVersion': '1',
        }),
        isNull,
      );
    });
  });
}
