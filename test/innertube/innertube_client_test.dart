import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/clients.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/transport.dart';
import 'package:songies/youtube/yt_models.dart';

import '../helpers/fake_innertube_transport.dart';
import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeTransport transport;
  late InnertubeClient client;

  setUp(() {
    db = testDb();
    settings = SettingsRepository(db);
    transport = FakeTransport();
    client = InnertubeClient(transport, settings);
  });
  tearDown(() async {
    client.dispose();
    await db.close();
  });

  Future<Result<Map<String, Object?>>> search() =>
      client.call(kWebRemix, 'search', {'query': 'daft punk'});

  test('kPlayerClients starts with the clients that gave plain urls', () {
    expect(kPlayerClients.map((c) => c.name), ['VISIONOS', 'ANDROID_VR']);
    expect(kWebRemix.name, 'WEB_REMIX');
    expect(kWebRemix.host, 'music.youtube.com');
  });

  test('call sends the identity in context and headers', () async {
    transport.reply(fixture('search_songs'));
    final r = await search();
    expect(r, isA<Ok<Map<String, Object?>>>());

    final req = transport.requests.single;
    expect(
      req.url.toString(),
      'https://music.youtube.com/youtubei/v1/search?prettyPrint=false',
    );
    expect(req.body['query'], 'daft punk');
    expect(req.contextClient['clientName'], 'WEB_REMIX');
    expect(req.contextClient['clientVersion'], kWebRemix.version);
    expect(req.headers['X-YouTube-Client-Name'], '${kWebRemix.nameId}');
    expect(req.headers['X-YouTube-Client-Version'], kWebRemix.version);
    expect(req.headers['User-Agent'], kWebRemix.userAgent);
    expect(req.headers['Origin'], 'https://music.youtube.com');
    expect(req.headers.containsKey('X-Goog-Visitor-Id'), isFalse);
  });

  test('extra query params are merged after prettyPrint', () async {
    transport.reply(fixture('search_songs'));
    await client.call(
      kWebRemix,
      'search',
      {'continuation': 'T'},
      query: {'ctoken': 'T', 'type': 'next'},
    );
    expect(
      transport.requests.single.url.toString(),
      'https://music.youtube.com/youtubei/v1/search'
      '?prettyPrint=false&ctoken=T&type=next',
    );
  });

  test('a player identity sends its extra client fields', () async {
    transport.reply(fixture('player_visionos_4D7u5KF7SP8'));
    await client.call(kPlayerClients.first, 'player', {
      'videoId': '4D7u5KF7SP8',
    });
    final req = transport.requests.single;
    expect(req.url.host, 'www.youtube.com');
    expect(req.contextClient['clientName'], 'VISIONOS');
    expect(req.contextClient['deviceModel'], 'RealityDevice17,1');
    expect(req.headers['User-Agent'], kPlayerClients.first.userAgent);
  });

  test('a stored visitor id is sent as header and in context', () async {
    await settings.setString(kYtVisitorData, 'STORED_VISITOR');
    transport.reply(fixture('search_songs'));
    await search();
    final req = transport.requests.single;
    expect(req.headers['X-Goog-Visitor-Id'], 'STORED_VISITOR');
    expect(req.contextClient['visitorData'], 'STORED_VISITOR');
  });

  test('visitorData is never overwritten', () async {
    await settings.setString(kYtVisitorData, 'STORED_VISITOR');
    final first = fixture('search_songs');
    (first.json!['responseContext']! as Map)['visitorData'] = 'DIFFERENT_ONE';
    transport.reply(first);
    await search();
    expect(await settings.getString(kYtVisitorData), 'STORED_VISITOR');
    expect(await client.visitorData(), 'STORED_VISITOR');

    transport.reply(fixture('search_songs'));
    await search();
    expect(
      transport.requests.last.headers['X-Goog-Visitor-Id'],
      'STORED_VISITOR',
    );
    expect(
      transport.requests.last.contextClient['visitorData'],
      'STORED_VISITOR',
    );
  });

  test('two concurrent calls: the first visitorData wins', () async {
    InnertubeResponse withVisitor(String vd) {
      final r = fixture('search_songs');
      (r.json!['responseContext']! as Map)['visitorData'] = vd;
      return r;
    }

    transport.reply(withVisitor('FIRST_VISITOR'));
    transport.reply(withVisitor('SECOND_VISITOR'));
    await Future.wait([search(), search()]);
    expect(await settings.getString(kYtVisitorData), 'FIRST_VISITOR');
    expect(await client.visitorData(), 'FIRST_VISITOR');
  });

  test('the first visitorData seen is stored and then sent', () async {
    expect(await client.visitorData(), isNull);
    transport.reply(fixture('browse_home'));
    await client.call(kWebRemix, 'browse', {'browseId': 'FEmusic_home'});
    expect(await settings.getString(kYtVisitorData), 'FAKE_VISITOR_DATA');
    expect(await client.visitorData(), 'FAKE_VISITOR_DATA');

    final second = fixture('search_songs');
    (second.json!['responseContext']! as Map)['visitorData'] = 'OTHER';
    transport.reply(second);
    await search();
    expect(
      transport.requests.last.headers['X-Goog-Visitor-Id'],
      'FAKE_VISITOR_DATA',
    );
    expect(await settings.getString(kYtVisitorData), 'FAKE_VISITOR_DATA');
  });

  test('resetVisitor deletes the key so no visitor header is sent', () async {
    await settings.setString(kYtVisitorData, 'STORED_VISITOR');
    expect(await client.visitorData(), 'STORED_VISITOR');
    await client.resetVisitor();
    expect(await settings.getString(kYtVisitorData), isNull);
    expect(await client.visitorData(), isNull);

    transport.reply(const InnertubeResponse(200, {}));
    await search();
    final req = transport.requests.single;
    expect(req.headers.containsKey('X-Goog-Visitor-Id'), isFalse);
    expect(req.contextClient.containsKey('visitorData'), isFalse);
  });

  for (final status in [400, 403, 500]) {
    test('HTTP $status gives a network Err', () async {
      transport.reply(InnertubeResponse(status, const {'error': {}}));
      final r = await search();
      final f = (r as Err).failure;
      expect(f.kind, FailureKind.network);
      expect(f.message, contains('$status'));
      expect(ytErrorKindOf(f), isNot(YtErrorKind.throttled));
    });
  }

  test('HTTP 429 gives a network Err tagged throttled', () async {
    transport.reply(const InnertubeResponse(429, null));
    final f = ((await search()) as Err).failure;
    expect(f.kind, FailureKind.network);
    expect(ytErrorKindOf(f), YtErrorKind.throttled);
  });

  test('a body that is not JSON gives an unknown Err', () async {
    transport.reply(const InnertubeResponse(200, null));
    expect(((await search()) as Err).failure.kind, FailureKind.unknown);
    transport.reply(const FormatException('Unexpected character'));
    expect(((await search()) as Err).failure.kind, FailureKind.unknown);
  });

  test('transport errors become Err, never a throw', () async {
    transport.reply(const SocketException('Failed host lookup'));
    expect(((await search()) as Err).failure.kind, FailureKind.network);
    transport.reply(const HttpException('Connection closed'));
    expect(((await search()) as Err).failure.kind, FailureKind.network);
    transport.reply(StateError('boom'));
    expect(((await search()) as Err).failure.kind, FailureKind.unknown);
  });

  group('consent', () {
    late List<bool> seen;

    setUp(() => seen = []);

    Future<void> listen() async {
      client.consentRequired.listen(seen.add);
    }

    test('ordinary responses do not ask for consent', () async {
      await listen();
      for (final name in ['browse_home', 'search_all', 'next_radio']) {
        transport.reply(fixture(name));
        await client.call(kWebRemix, 'browse', const {});
      }
      transport.reply(fixture('player_visionos_fOT0BUpITw8'));
      await client.call(kPlayerClients.first, 'player', const {});
      await pumpEventQueue();
      expect(seen, isEmpty);
    });

    test('a redirect to consent.youtube.com asks for consent', () async {
      await listen();
      transport.reply(
        InnertubeResponse(
          302,
          null,
          redirect: Uri.parse('https://consent.youtube.com/m?continue=x'),
        ),
      );
      final r = await search();
      await pumpEventQueue();
      expect(r, isA<Err<Map<String, Object?>>>());
      expect(seen, [true]);
    });

    test('a consent flow inside a response asks for consent', () async {
      await listen();
      // Recorded: the IOS client's player response carries a
      // startEomFlowCommand pointing at consent.youtube.com.
      transport.reply(fixture('player_ios_fOT0BUpITw8'));
      final r = await client.call(kPlayerClients.first, 'player', const {});
      await pumpEventQueue();
      expect(r, isA<Ok<Map<String, Object?>>>());
      expect(seen, [true]);
    });

    test('an FEconsent browse asks for consent', () async {
      await listen();
      transport.reply(fixture('consent_browse_handcrafted'));
      final r = await client.call(kWebRemix, 'browse', {
        'browseId': 'FEmusic_home',
      });
      await pumpEventQueue();
      expect(r, isA<Ok<Map<String, Object?>>>());
      expect(seen, [true]);
    });

    test('without consent no cookie is sent', () async {
      transport.reply(fixture('search_all'));
      await search();
      expect(transport.requests.single.headers.containsKey('Cookie'), isFalse);
      expect(await client.consentGiven(), isFalse);
    });

    test('accepting stores yt_consent_given and sends SOCS=CAI', () async {
      await client.acceptConsent();
      expect(await settings.getString(kYtConsentGiven), isNotNull);
      expect(await client.consentGiven(), isTrue);
      transport.reply(fixture('search_all'));
      await search();
      expect(transport.requests.single.headers['Cookie'], 'SOCS=CAI');
    });

    test(
      'accepted consent survives a restart and is never asked again',
      () async {
        await client.acceptConsent();
        // A new client on the same device settings, as after a restart.
        final again = InnertubeClient(transport, settings);
        addTearDown(again.dispose);
        final asked = <bool>[];
        again.consentRequired.listen(asked.add);
        expect(await again.consentGiven(), isTrue);
        transport.reply(fixture('consent_browse_handcrafted'));
        await again.call(kWebRemix, 'browse', {'browseId': 'FEmusic_home'});
        transport.reply(
          InnertubeResponse(
            302,
            null,
            redirect: Uri.parse('https://consent.youtube.com/m?continue=x'),
          ),
        );
        await again.call(kWebRemix, 'search', const {});
        await pumpEventQueue();
        expect(transport.requests.first.headers['Cookie'], 'SOCS=CAI');
        expect(asked, isEmpty);
      },
    );
  });
}
