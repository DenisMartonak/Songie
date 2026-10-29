// Plan 7: a signed-in Innertube call (SAPISIDHASH auth) and what never goes
// out signed in.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/clients.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/player_stream_source.dart';
import 'package:songies/innertube/sapisid_hash.dart';
import 'package:songies/innertube/transport.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/innertube/ytm_service.dart';

import '../helpers/fake_innertube_transport.dart';
import '../helpers/test_db.dart';

String sha1hex(String s) => sha1.convert(utf8.encode(s)).toString();

const _authHeaders = ['Authorization', 'X-Goog-AuthUser', 'X-Origin', 'Cookie'];

void main() {
  test('sapisidHash is SAPISIDHASH <ts>_<sha1("<ts> <sapisid> <origin>")>', () {
    expect(
      sapisidHash('abc', 'https://music.youtube.com', DateTime.utc(2026, 1, 1)),
      'SAPISIDHASH 1767225600_'
      '${sha1hex('1767225600 abc https://music.youtube.com')}',
    );
  });

  late AppDatabase db;
  late SettingsRepository settings;
  late FakeTransport transport;
  late InnertubeClient client;
  final now = DateTime.utc(2026, 1, 1);
  final session = YtSession({
    'SID': 'SIDSECRET',
    'SAPISID': 'SAPISECRET',
    '__Secure-3PAPISID': 'P3SECRET',
  });
  final hash = sapisidHash('SAPISECRET', 'https://music.youtube.com', now);

  setUp(() {
    db = testDb();
    settings = SettingsRepository(db);
    transport = FakeTransport();
    client = InnertubeClient(transport, settings, now: () => now);
  });
  tearDown(() async {
    client.dispose();
    await db.close();
  });

  group('headers', () {
    test(
      'a call with a session sends cookies, hash, AuthUser and X-Origin',
      () async {
        transport.reply(fixture('home_signed_in'));
        await client.call(kWebRemix, 'browse', {
          'browseId': 'FEmusic_home',
        }, session: session);
        final h = transport.requests.single.headers;
        expect(h['Cookie'], session.cookieHeader());
        expect(h['Authorization'], hash);
        expect(h['X-Goog-AuthUser'], '0');
        expect(h['X-Origin'], 'https://music.youtube.com');
        expect(h['Origin'], 'https://music.youtube.com');
      },
    );

    test(
      'consented: SOCS=CAI joins the session cookie, one Cookie header',
      () async {
        await client.acceptConsent();
        transport.reply(fixture('home_signed_in'));
        await client.call(kWebRemix, 'browse', {
          'browseId': 'FEmusic_home',
        }, session: session);
        final h = transport.requests.single.headers;
        expect(h['Cookie'], '${session.cookieHeader()}; SOCS=CAI');
      },
    );

    test('the visitor id is kept when signed in', () async {
      await settings.setString(kYtVisitorData, 'VIS');
      transport.reply(fixture('home_signed_in'));
      await client.call(kWebRemix, 'browse', {
        'browseId': 'FEmusic_home',
      }, session: session);
      expect(transport.requests.single.headers['X-Goog-Visitor-Id'], 'VIS');
    });

    test('a call without a session sends none of them', () async {
      transport.reply(fixture('browse_home'));
      await client.call(kWebRemix, 'browse', {'browseId': 'FEmusic_home'});
      final h = transport.requests.single.headers;
      for (final k in _authHeaders) {
        expect(h.containsKey(k), isFalse, reason: k);
      }
    });

    test('player, search and next never carry Authorization', () async {
      final ytm = YtmService(client);
      final source = InnertubeStreamSource(client);
      transport
        ..reply(fixture('search_songs'))
        ..reply(const InnertubeResponse(200, {}))
        ..reply(fixture('player_visionos_4D7u5KF7SP8'));
      await ytm.search('x', YtmSearchKind.songs);
      await ytm.radio('4D7u5KF7SP8');
      await source.resolveStream('4D7u5KF7SP8');
      expect(transport.requests, hasLength(greaterThanOrEqualTo(3)));
      for (final r in transport.requests) {
        expect(r.headers.containsKey('Authorization'), isFalse);
        expect(r.headers['Cookie'] ?? '', isNot(contains('SAPISID')));
      }
    });

    test('Home and its continuation go out signed in', () async {
      final ytm = YtmService(client);
      transport
        ..reply(fixture('home_signed_in'))
        ..reply(const InnertubeResponse(200, {}));
      await ytm.home(session: session);
      await ytm.home(continuation: 'TOK', session: session);
      for (final r in transport.requests) {
        expect(r.headers['Authorization'], hash);
      }
    });
  });

  test(
    'an invalid cookie character is "invalid session cookie", no value',
    () async {
      final bad = YtSession({
        'SID': 'BAD\nVALUESECRET',
        'SAPISID': 'SAPISECRET',
      });
      final r = await client.call(kWebRemix, 'browse', {
        'browseId': 'FEmusic_home',
      }, session: bad);
      final msg = (r as Err).failure.message;
      expect(msg, contains('invalid session cookie'));
      expect(msg, isNot(contains('bad JSON')));
      expect(msg, isNot(contains('VALUESECRET')));
      expect((r as Err).failure.cause, isNull);
      expect(transport.requests, isEmpty);
    },
  );

  test('a DQUOTE-wrapped cookie value goes out as is (RFC 6265)', () async {
    transport.reply(InnertubeResponse(200, {'contents': {}}));
    final quoted = YtSession({'SAPISID': 'SAPISECRET', 'Q': '"abc"'});
    final r = await client.call(kWebRemix, 'browse', {
      'browseId': 'FEmusic_home',
    }, session: quoted);
    expect(r, isA<Ok>());
    expect(transport.requests.single.headers['Cookie'], contains('Q="abc"'));
  });

  group('accountTracking', () {
    late YtmService ytm;
    setUp(() => ytm = YtmService(client));

    test('a signed-in WEB_REMIX player call; both URLs parsed', () async {
      transport.reply(
        InnertubeResponse(200, {
          'playbackTracking': {
            'videostatsPlaybackUrl': {
              'baseUrl': 'https://s.youtube.com/api/stats/playback?docid=v1',
            },
            'videostatsWatchtimeUrl': {
              'baseUrl': 'https://s.youtube.com/api/stats/watchtime?docid=v1',
            },
          },
        }),
      );
      final t = await ytm.accountTracking('v1', session);
      final req = transport.requests.single;
      expect(req.url.path, endsWith('/player'));
      expect(req.url.host, 'music.youtube.com');
      expect(req.body['videoId'], 'v1');
      expect(req.body['contentCheckOk'], true);
      expect(req.body['racyCheckOk'], true);
      final client_ = (req.body['context'] as Map)['client'] as Map;
      expect(client_['clientName'], 'WEB_REMIX');
      expect(req.headers['Cookie'], contains('SAPISID=SAPISECRET'));
      expect(req.headers['Authorization'], hash);
      expect(
        t!.playbackUrl,
        Uri.parse('https://s.youtube.com/api/stats/playback?docid=v1'),
      );
      expect(
        t.watchtimeUrl,
        Uri.parse('https://s.youtube.com/api/stats/watchtime?docid=v1'),
      );
    });

    test('HTTP 401 gives null', () async {
      transport.reply(const InnertubeResponse(401, null));
      expect(await ytm.accountTracking('v1', session), isNull);
    });

    test('no playbackTracking gives null', () async {
      transport.reply(InnertubeResponse(200, {'videoDetails': {}}));
      expect(await ytm.accountTracking('v1', session), isNull);
    });

    test('a missing watchtime URL gives null', () async {
      transport.reply(
        InnertubeResponse(200, {
          'playbackTracking': {
            'videostatsPlaybackUrl': {'baseUrl': 'https://s.youtube.com/p'},
          },
        }),
      );
      expect(await ytm.accountTracking('v1', session), isNull);
    });
  });

  group('no secrets in failures', () {
    void clean(Result<Object?> r) {
      final msg = (r as Err).failure.message;
      for (final secret in ['SIDSECRET', 'SAPISECRET', 'P3SECRET', hash]) {
        expect(msg, isNot(contains(secret)));
      }
      expect('${r.failure}', isNot(contains('SAPISECRET')));
    }

    Future<Result<Map<String, Object?>>> go() => client.call(
      kWebRemix,
      'browse',
      {'browseId': 'FEmusic_home'},
      session: session,
    );

    test('a socket error that echoes the headers', () async {
      transport.reply(
        SocketException('failed: Cookie: ${session.cookieHeader()} $hash'),
      );
      clean(await go());
    });

    test('an HTTP error that echoes the headers', () async {
      transport.reply(
        HttpException('bad request Authorization: $hash SAPISID=SAPISECRET'),
      );
      clean(await go());
    });

    test('HTTP 403', () async {
      transport.reply(const InnertubeResponse(403, null));
      final r = await go();
      clean(r);
      expect(httpStatusOf((r as Err).failure), 403);
    });

    test('bad JSON', () async {
      transport.reply(FormatException('Unexpected SAPISECRET', 'SIDSECRET'));
      clean(await go());
    });
  });
}
