import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/clients.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/player_stream_source.dart';
import 'package:songies/innertube/transport.dart';
import 'package:songies/youtube/yt_models.dart';

import '../helpers/fake_innertube_transport.dart';
import '../helpers/test_db.dart';

const _id = '4D7u5KF7SP8';

/// The visionOS fixture with its audio formats changed by [edit].
InnertubeResponse editedFormats(
  void Function(List<Map<String, Object?>> formats) edit,
) {
  final r = fixture('player_visionos_$_id');
  final formats =
      ((r.json!['streamingData']! as Map)['adaptiveFormats']! as List)
          .cast<Map<String, Object?>>();
  edit(formats);
  return r;
}

String? _itag(Uri u) => u.queryParameters['itag'];

InnertubeResponse status(String status, String reason) =>
    InnertubeResponse(200, {
      'playabilityStatus': {'status': status, 'reason': reason},
    });

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeTransport transport;
  late InnertubeClient client;
  late InnertubeStreamSource source;

  final visionOs = kPlayerClients[0];
  final androidVr = kPlayerClients[1];

  setUp(() async {
    db = testDb();
    settings = SettingsRepository(db);
    await settings.setString(kYtVisitorData, 'STORED_VISITOR');
    transport = FakeTransport();
    client = InnertubeClient(transport, settings);
    source = InnertubeStreamSource(client);
  });
  tearDown(() async {
    client.dispose();
    await db.close();
  });

  Future<Result<YtStream>> go([String id = _id]) => source.resolveStream(id);

  test('is named innertube', () => expect(source.name, 'innertube'));

  group('picking the format', () {
    test('opus 251 is chosen over m4a 140, with expire and the UA', () async {
      transport.reply(fixture('player_visionos_$_id'));
      final s = (await go() as Ok<YtStream>).value;
      expect(_itag(s.url), '251');
      expect(s.url.host, 'rr1---sn-fake.googlevideo.com');
      expect(
        s.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1792908126 * 1000, isUtc: true),
      );
      expect(s.headers['User-Agent'], visionOs.userAgent);
      // Innertube gives no metadata: onStreamMetadata stays yt-dlp only.
      expect(s.title, isNull);
      expect(s.durationMs, isNull);

      final req = transport.requests.single;
      expect(req.url.path, '/youtubei/v1/player');
      expect(req.contextClient['clientName'], 'VISIONOS');
      expect(req.body['videoId'], _id);
      expect(req.body['contentCheckOk'], isTrue);
      expect(req.body['racyCheckOk'], isTrue);
      expect(
        ((req.body['playbackContext']! as Map)['contentPlaybackContext']!
            as Map)['html5Preference'],
        'HTML5_PREF_WANTS',
      );
    });

    test('without opus the best m4a wins (140 over 139)', () async {
      transport.reply(
        editedFormats(
          (f) =>
              f.removeWhere((m) => (m['mimeType']! as String).contains('opus')),
        ),
      );
      final s = (await go() as Ok<YtStream>).value;
      expect(_itag(s.url), '140');
    });

    test('without opus or m4a the best other audio wins', () async {
      transport.reply(
        editedFormats((f) {
          f.removeWhere((m) => (m['mimeType']! as String).startsWith('audio'));
          f.add({
            'itag': 600,
            'mimeType': 'audio/ogg; codecs="vorbis"',
            'bitrate': 1000,
            'url':
                'https://rr1---sn-fake.googlevideo.com/videoplayback?itag=600',
          });
        }),
      );
      final s = (await go() as Ok<YtStream>).value;
      expect(_itag(s.url), '600');
      expect(s.expiresAt, isNull);
    });

    test('an out-of-range expire does not throw (expiry unknown)', () async {
      for (final expire in ['99999999999999999', '-5', '0']) {
        transport.reply(
          editedFormats((f) {
            final opus = f.firstWhere((m) => m['itag'] == 251);
            opus['url'] = (opus['url']! as String).replaceFirst(
              RegExp(r'expire=\d+'),
              'expire=$expire',
            );
          }),
        );
        final s = (await go() as Ok<YtStream>).value;
        expect(_itag(s.url), '251');
        expect(s.expiresAt, isNull, reason: 'expire=$expire');
      }
    });

    test('a format with only signatureCipher is skipped', () async {
      transport.reply(
        editedFormats((f) {
          final opus = f.firstWhere((m) => m['itag'] == 251);
          opus['signatureCipher'] = 's=FAKE&sp=sig&url=${opus.remove('url')}';
        }),
      );
      final s = (await go() as Ok<YtStream>).value;
      expect(_itag(s.url), '250');
    });

    test('no plain url counts as a failed client', () async {
      transport
        ..reply(fixture('player_ios_$_id'))
        ..reply(fixture('player_android_vr_$_id'));
      final s = (await go() as Ok<YtStream>).value;
      expect(_itag(s.url), '251');
      expect(s.headers['User-Agent'], androidVr.userAgent);
      expect(s.url.queryParameters['c'], 'ANDROID_VR');
    });
  });

  group('falling through clients', () {
    test('403 then OK; the next call tries the working client first', () async {
      transport
        ..reply(const InnertubeResponse(403, {'error': {}}))
        ..reply(fixture('player_android_vr_$_id'));
      expect(await go(), isA<Ok<YtStream>>());
      expect(transport.requests.map((r) => r.contextClient['clientName']), [
        'VISIONOS',
        'ANDROID_VR',
      ]);

      transport.reply(fixture('player_android_vr_fOT0BUpITw8'));
      expect(await go('fOT0BUpITw8'), isA<Ok<YtStream>>());
      expect(transport.requests[2].contextClient['clientName'], 'ANDROID_VR');
      expect(transport.requests, hasLength(3));
    });

    test('a transport error falls through to the next client', () async {
      transport
        ..reply(const SocketException('Failed host lookup'))
        ..reply(fixture('player_android_vr_$_id'));
      expect(await go(), isA<Ok<YtStream>>());
    });

    test('every client failing is an Err that is not notFound', () async {
      transport
        ..reply(const InnertubeResponse(403, {'error': {}}))
        ..reply(fixture('player_tv_$_id'));
      final r = await go() as Err<YtStream>;
      expect(ytErrorKindOf(r.failure), isNot(YtErrorKind.notFound));
      expect(r.failure.kind, isNot(FailureKind.notFound));
      expect(transport.requests, hasLength(2));
    });
  });

  group('playabilityStatus', () {
    test('UNPLAYABLE from every client is notFound', () async {
      transport
        ..reply(fixture('player_unplayable_handcrafted'))
        ..reply(fixture('player_unplayable_handcrafted'));
      final r = await go() as Err<YtStream>;
      expect(ytErrorKindOf(r.failure), YtErrorKind.notFound);
      expect(r.failure.kind, FailureKind.notFound);
    });

    test('ERROR from every client is notFound', () async {
      transport
        ..reply(status('ERROR', 'Video unavailable'))
        ..reply(status('ERROR', 'This video has been removed'));
      final r = await go() as Err<YtStream>;
      expect(ytErrorKindOf(r.failure), YtErrorKind.notFound);
    });

    test('LOGIN_REQUIRED with an age reason is notFound', () async {
      transport
        ..reply(status('LOGIN_REQUIRED', 'Sign in to confirm your age'))
        ..reply(status('LOGIN_REQUIRED', 'Sign in to confirm your age'));
      final r = await go() as Err<YtStream>;
      expect(ytErrorKindOf(r.failure), YtErrorKind.notFound);
    });

    test('LOGIN_REQUIRED "not a bot" is client-level: falls through', () async {
      transport
        ..reply(fixture('player_visionos_no_visitor_$_id'))
        ..reply(fixture('player_visionos_no_visitor_$_id'));
      final r = await go() as Err<YtStream>;
      expect(ytErrorKindOf(r.failure), isNot(YtErrorKind.notFound));
    });

    test('"page needs to be reloaded" UNPLAYABLE is client-level', () async {
      transport
        ..reply(fixture('player_tv_$_id'))
        ..reply(fixture('player_tv_$_id'));
      final r = await go() as Err<YtStream>;
      expect(ytErrorKindOf(r.failure), isNot(YtErrorKind.notFound));
    });

    test('clients that disagree fall through, not notFound', () async {
      transport
        ..reply(fixture('player_unplayable_handcrafted'))
        ..reply(const InnertubeResponse(403, {'error': {}}));
      final r = await go() as Err<YtStream>;
      expect(ytErrorKindOf(r.failure), isNot(YtErrorKind.notFound));
    });

    test('a video-level status still tries the next client', () async {
      transport
        ..reply(fixture('player_unplayable_handcrafted'))
        ..reply(fixture('player_android_vr_$_id'));
      expect(await go(), isA<Ok<YtStream>>());
    });
  });

  group('playbackTracking', () {
    test('trackingFor returns the last playback and watchtime urls', () async {
      expect(source.trackingFor(_id), isNull);
      transport.reply(fixture('player_visionos_$_id'));
      await go();
      final t = source.trackingFor(_id)!;
      expect(t.playbackUrl.path, '/api/stats/playback');
      expect(t.playbackUrl.queryParameters['docid'], _id);
      expect(t.watchtimeUrl.path, '/api/stats/watchtime');
      expect(source.trackingFor('other'), isNull);
    });
  });

  test(
    'an exception inside resolveStream becomes a non-notFound Err',
    () async {
      // A closed database makes the visitor id read throw.
      await settings.setString(kYtVisitorData, null);
      client.dispose();
      client = InnertubeClient(transport, settings);
      source = InnertubeStreamSource(client);
      await db.close();
      final r = await go() as Err<YtStream>;
      expect(ytErrorKindOf(r.failure), YtErrorKind.extractor);
      expect(transport.requests, isEmpty);
      db = testDb(); // for tearDown
    },
  );

  group('visitor id bootstrap', () {
    setUp(() async {
      client.dispose();
      await settings.setString(kYtVisitorData, null);
      client = InnertubeClient(transport, settings);
      source = InnertubeStreamSource(client);
    });

    test('a WEB_REMIX browse stores a visitor id before player', () async {
      transport
        ..reply(fixture('browse_home'))
        ..reply(fixture('player_visionos_$_id'));
      expect(await go(), isA<Ok<YtStream>>());
      final browse = transport.requests[0];
      expect(browse.url.host, 'music.youtube.com');
      expect(browse.url.path, '/youtubei/v1/browse');
      expect(browse.body['browseId'], 'FEmusic_home');
      expect(browse.contextClient['clientName'], 'WEB_REMIX');
      final player = transport.requests[1];
      expect(player.headers['X-Goog-Visitor-Id'], 'FAKE_VISITOR_DATA');
      expect(player.contextClient['visitorData'], 'FAKE_VISITOR_DATA');

      // Stored: the next play needs no bootstrap.
      transport.reply(fixture('player_visionos_fOT0BUpITw8'));
      await go('fOT0BUpITw8');
      expect(transport.requests, hasLength(3));
      expect(transport.requests[2].url.path, '/youtubei/v1/player');
    });

    test('a failed bootstrap still tries player', () async {
      transport
        ..reply(const SocketException('Failed host lookup'))
        ..reply(fixture('player_visionos_$_id'));
      expect(await go(), isA<Ok<YtStream>>());
      expect(transport.requests[1].url.path, '/youtubei/v1/player');
    });
  });
}
