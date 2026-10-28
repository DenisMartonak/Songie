import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/innertube/play_reporter.dart';
import 'package:songies/innertube/player_stream_source.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/player/play_rules.dart';
import 'package:songies/player/player_service.dart';

import 'package:songies/innertube/transport.dart';

import '../helpers/fake_innertube_transport.dart';

Track _track(String id, {String source = 'yt', int durationMs = 200000}) =>
    Track(
      id: id,
      clock: '0000000000001-00000-dev',
      originDevice: 'dev',
      deleted: false,
      localSeq: 1,
      source: source,
      ytVideoId: source == 'yt' ? 'vid_$id' : null,
      title: 'T',
      artist: 'A',
      durationMs: durationMs,
      unavailable: false,
      searchText: 't a',
    );

class _FakeSrc implements InnertubeStreamSource {
  final tracking = <String, PlaybackTracking>{};
  @override
  PlaybackTracking? trackingFor(String videoId) => tracking[videoId];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late StreamController<PlayerState> states;
  late _FakeSrc src;
  late FakeTransport transport;
  late PlayReporter reporter;

  setUp(() {
    states = StreamController<PlayerState>.broadcast(sync: true);
    src = _FakeSrc()
      ..tracking['vid_a'] = PlaybackTracking(
        playbackUrl: Uri.parse(
          'https://s.youtube.com/api/stats/playback?docid=vid_a&ns=yt',
        ),
        watchtimeUrl: Uri.parse(
          'https://s.youtube.com/api/stats/watchtime?docid=vid_a&ns=yt',
        ),
      );
    transport = FakeTransport();
    reporter = PlayReporter(states.stream, src, transport);
  });
  tearDown(() {
    reporter.dispose();
    states.close();
  });

  /// Plays [from]..[to] seconds in 1 s steps.
  void play(Track t, int from, int to, {Duration? duration}) {
    for (var s = from; s <= to; s++) {
      states.add(
        PlayerState(
          queue: [t],
          index: 0,
          playing: true,
          position: Duration(seconds: s),
          duration: duration,
        ),
      );
    }
  }

  test('reachedPlay: threshold, or the whole song when shorter', () {
    expect(reachedPlay(const Duration(seconds: 29), null), isFalse);
    expect(reachedPlay(kPlayThreshold, null), isTrue);
    expect(
      reachedPlay(const Duration(seconds: 20), const Duration(seconds: 20)),
      isTrue,
    );
    expect(
      reachedPlay(const Duration(seconds: 19), const Duration(seconds: 20)),
      isFalse,
    );
  });

  test('31 s of a YouTube track sends a playback and a watchtime GET', () async {
    play(_track('a'), 0, 31);
    await _settle();
    expect(transport.gets, hasLength(2));
    final p = transport.gets[0].url;
    expect(p.path, '/api/stats/playback');
    expect(p.queryParameters['ver'], '2');
    expect(p.queryParameters['cpn'], matches(RegExp(r'^[A-Za-z0-9_-]{16}$')));
    expect(p.queryParameters['docid'], 'vid_a');
    final w = transport.gets[1].url;
    expect(w.path, '/api/stats/watchtime');
    expect(w.queryParameters['cpn'], p.queryParameters['cpn']);
    expect(w.queryParameters['st'], '0');
    expect(w.queryParameters['et'], '30');
    expect(w.queryParameters['cmt'], '30');
    expect(transport.gets[0].headers['User-Agent'], contains('Macintosh'));
  });

  test('no second report for the same play, even after a seek', () async {
    final t = _track('a');
    play(t, 0, 31);
    play(t, 0, 31);
    await _settle();
    expect(transport.gets, hasLength(2));
  });

  test('a seek forward does not count as heard time', () {
    final t = _track('a');
    play(t, 0, 10);
    play(t, 100, 110);
    expect(transport.gets, isEmpty);
  });

  test('paused time does not count', () async {
    final t = _track('a');
    play(t, 0, 29);
    for (var i = 0; i < 5; i++) {
      states.add(
        PlayerState(
          queue: [t],
          index: 0,
          position: const Duration(seconds: 29),
        ),
      );
    }
    expect(transport.gets, isEmpty);
    play(t, 29, 29);
    await _settle();
    expect(transport.gets, isEmpty);
    play(t, 30, 30);
    await _settle();
    expect(transport.gets, hasLength(2));
  });

  test('a 20 s song played to the end is reported', () async {
    play(
      _track('a', durationMs: 20000),
      0,
      20,
      duration: const Duration(seconds: 20),
    );
    await _settle();
    expect(transport.gets, hasLength(2));
  });

  test('local tracks and tracks without tracking send nothing', () {
    play(_track('l', source: 'local'), 0, 40);
    play(_track('b'), 0, 40);
    expect(transport.gets, isEmpty);
  });

  test('a transport error is swallowed and not retried', () async {
    transport.reply(Exception('offline'));
    play(_track('a'), 0, 31);
    await _settle();
    play(_track('a'), 32, 40);
    await _settle();
    // The playback GET failed; the watchtime GET still went out once.
    expect(transport.gets, hasLength(2));
  });

  void tick(Track t, int ms, {bool playing = true, int? lengthMs}) => states.add(
    PlayerState(
      queue: [t],
      index: 0,
      playing: playing,
      position: Duration(milliseconds: ms),
      duration: lengthMs == null ? null : Duration(milliseconds: lengthMs),
    ),
  );

  test('20 s song with ticks 0.4..19.6 s then a track change is reported once',
      () async {
    final a = _track('a', durationMs: 20000);
    for (var ms = 400; ms <= 19600; ms += 1200) {
      tick(a, ms);
    }
    tick(a, 19600);
    states.add(
      PlayerState(
        queue: [a, _track('b')],
        index: 1,
        playing: true,
      ),
    );
    await _settle();
    expect(transport.gets, hasLength(2));
    expect(transport.gets[0].url.queryParameters['docid'], 'vid_a');
  });

  test('20 s song ending with playing=false at 19.5 s is reported once',
      () async {
    final a = _track('a', durationMs: 20000);
    for (var ms = 500; ms < 19500; ms += 1000) {
      tick(a, ms);
    }
    tick(a, 19500, playing: false);
    tick(a, 19500, playing: false);
    await _settle();
    expect(transport.gets, hasLength(2));
  });

  test('20 s of a long song A, a track change, 20 s of B sends nothing',
      () async {
    final a = _track('a');
    play(a, 0, 20);
    final b = _track('b');
    for (var s = 0; s <= 20; s++) {
      states.add(
        PlayerState(
          queue: [a, b],
          index: 1,
          playing: true,
          position: Duration(seconds: s),
        ),
      );
    }
    await _settle();
    expect(transport.gets, isEmpty);
  });

  group('signed in', () {
    final session = YtSession({
      'SAPISID': 'SAPISECRET1234',
      'SID': 'SIDSECRET5678',
    });
    final accountUrls = PlaybackTracking(
      playbackUrl: Uri.parse(
        'https://s.youtube.com/api/stats/playback?docid=vid_a&ns=yt&acct=1',
      ),
      watchtimeUrl: Uri.parse(
        'https://s.youtube.com/api/stats/watchtime?docid=vid_a&ns=yt&acct=1',
      ),
    );
    late int accountCalls;
    late PlayReporter signed;
    PlaybackTracking? accountResult;

    PlayReporter build({YtSession? Function()? s, bool withAccount = true}) =>
        PlayReporter(
          states.stream,
          src,
          transport,
          session: () async => (s ?? () => session)(),
          accountTracking: withAccount
              ? (id, sess) async {
                  accountCalls++;
                  return accountResult;
                }
              : null,
        );

    setUp(() {
      accountCalls = 0;
      accountResult = accountUrls;
      reporter.dispose();
      signed = build();
    });
    tearDown(() => signed.dispose());

    test('reports carry Cookie and Authorization and keep ver and cpn',
        () async {
      play(_track('a'), 0, 31);
      await _settle();
      await _settle();
      expect(transport.gets, hasLength(2));
      for (final g in transport.gets) {
        expect(g.headers['Cookie'], contains('SAPISID=SAPISECRET1234'));
        expect(g.headers['Authorization'], startsWith('SAPISIDHASH '));
        expect(g.headers['X-Goog-AuthUser'], '0');
        expect(g.headers['X-Origin'], 'https://music.youtube.com');
        expect(g.url.queryParameters['ver'], '2');
        expect(g.url.queryParameters['cpn'], hasLength(16));
      }
      expect(transport.gets[0].url.queryParameters['acct'], '1');
    });

    test('exactly one accountTracking call per qualifying play', () async {
      play(_track('a'), 0, 31);
      play(_track('a'), 32, 40);
      await _settle();
      expect(accountCalls, 1);
    });

    test('a play under 30 s makes no accountTracking call', () async {
      play(_track('a'), 0, 20);
      await _settle();
      expect(accountCalls, 0);
      expect(transport.gets, isEmpty);
    });

    test('accountTracking failing falls back to anonymous, no session',
        () async {
      accountResult = null;
      play(_track('a'), 0, 31);
      await _settle();
      await _settle();
      expect(accountCalls, 1);
      expect(transport.gets, hasLength(2));
      for (final g in transport.gets) {
        expect(g.headers.containsKey('Cookie'), isFalse);
        expect(g.headers.containsKey('Authorization'), isFalse);
      }
    });

    test('signed out (no session) sends no account call and no headers',
        () async {
      signed.dispose();
      signed = build(s: () => null);
      play(_track('a'), 0, 31);
      await _settle();
      await _settle();
      expect(accountCalls, 0);
      expect(transport.gets, hasLength(2));
      expect(transport.gets[0].headers.containsKey('Cookie'), isFalse);
      expect(transport.gets[0].headers.containsKey('Authorization'), isFalse);
    });

    test('a failing signed-in report logs no cookie or hash value', () async {
      final lines = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      addTearDown(() => debugPrint = old);
      transport.reply(Exception('boom'));
      transport.reply(const InnertubeResponse(403, null));
      play(_track('a'), 0, 31);
      await _settle();
      await _settle();
      expect(lines, isNotEmpty);
      final all = lines.join('\n');
      expect(all, isNot(contains('SAPISECRET1234')));
      expect(all, isNot(contains('SIDSECRET5678')));
      expect(all, isNot(contains('SAPISIDHASH')));
    });
  });
}
