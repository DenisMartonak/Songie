import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/lyrics/lrclib.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_sources.dart';

const _ua = 'Songies/1.0.0 (test)';
const _q = LyricsQuery(
  title: 'Invented Song',
  artist: 'Invented Artist',
  album: 'Invented Album',
  durationSec: 213,
);

String _fixture(String n) => File('test/fixtures/lyrics/$n').readAsStringSync();

void main() {
  final uris = <Uri>[];
  final headers = <Map<String, String>>[];

  LrclibSource source(Future<({int status, String body})> Function() answer) =>
      LrclibSource((uri, h) {
        uris.add(uri);
        headers.add(h);
        return answer();
      }, userAgent: _ua);

  LrclibSource ok(String body, [int status = 200]) =>
      source(() async => (status: status, body: body));

  setUp(() {
    uris.clear();
    headers.clear();
  });

  group('exact', () {
    test('sends user agent and query', () async {
      await ok(_fixture('lrclib_get.json')).exact(_q);
      expect(headers.single['User-Agent'], _ua);
      expect(uris.single.path, '/api/get');
      expect(uris.single.queryParameters, {
        'artist_name': 'Invented Artist',
        'track_name': 'Invented Song',
        'album_name': 'Invented Album',
        'duration': '213',
      });
    });

    test('album_name is left out when null', () async {
      await ok(_fixture('lrclib_get.json'))
          .exact(const LyricsQuery(title: 't', artist: 'a', durationSec: 213));
      expect(uris.single.queryParameters.containsKey('album_name'), isFalse);
    });

    test('null duration skips the request', () async {
      final a = await ok('{}')
          .exact(const LyricsQuery(title: 't', artist: 'a'));
      expect(a, isA<Nothing>());
      expect(uris, isEmpty);
    });

    test('duration 3 s off is Nothing', () async {
      final a = await ok(_fixture('lrclib_get.json'))
          .exact(const LyricsQuery(title: 't', artist: 'a', durationSec: 216));
      expect(a, isA<Nothing>());
    });

    test('synced', () async {
      final l =
          (await ok(_fixture('lrclib_get.json')).exact(_q) as Found).lyrics;
      expect(l.kind, LyricsKind.synced);
      expect(l.source, LyricsSource.lrclib);
      expect(l.lines.first.text, 'First invented line');
      expect(l.credit, isNull);
    });

    test('plain only', () async {
      final l = (await ok(
        '{"duration":213,"plainLyrics":"a\\nb","syncedLyrics":null}',
      ).exact(_q) as Found).lyrics;
      expect(l.kind, LyricsKind.plain);
      expect(l.text, 'a\nb');
    });

    test('one-line synced stub falls back to plain', () async {
      final l = (await ok(
        '{"duration":213,"plainLyrics":"a\\nb",'
        '"syncedLyrics":"[00:01.00] only"}',
      ).exact(_q) as Found).lyrics;
      expect(l.kind, LyricsKind.plain);
    });

    test('one-line synced stub without plain is Nothing', () async {
      final a = await ok(
        '{"duration":213,"plainLyrics":null,'
        '"syncedLyrics":"[00:01.00] only"}',
      ).exact(_q);
      expect(a, isA<Nothing>());
    });

    test('404 is Nothing', () async {
      expect(await ok('{}', 404).exact(_q), isA<Nothing>());
    });

    test('500 is Failed', () async {
      expect(await ok('{}', 500).exact(_q), isA<Failed>());
    });

    test('socket error is Failed', () async {
      final a = await source(() async => throw const SocketException('down'))
          .exact(_q);
      expect(a, isA<Failed>());
    });

    test('malformed JSON is Failed', () async {
      expect(await ok('{nope').exact(_q), isA<Failed>());
    });
  });

  group('search', () {
    test('uses track and artist names', () async {
      await ok(_fixture('lrclib_search.json')).search(_q);
      expect(uris.single.path, '/api/search');
      expect(uris.single.queryParameters, {
        'track_name': 'Invented Song',
        'artist_name': 'Invented Artist',
      });
      expect(headers.single['User-Agent'], _ua);
    });

    test(
      'prefers in-window synced over earlier plain, skips out-of-window',
      () async {
        final l = (await ok(
          _fixture('lrclib_search.json'),
        ).search(_q) as Found).lyrics;
        expect(l.kind, LyricsKind.synced);
      },
    );

    test('null duration considers all results', () async {
      final l = (await ok(
        _fixture('lrclib_search.json'),
      ).search(const LyricsQuery(title: 't', artist: 'a')) as Found).lyrics;
      expect(l.kind, LyricsKind.synced);
    });

    test('instrumental only is Nothing', () async {
      final a = await ok(
        '[{"duration":213,"instrumental":true,"plainLyrics":null,'
        '"syncedLyrics":null}]',
      ).search(_q);
      expect(a, isA<Nothing>());
    });

    test('only out-of-window results is Nothing', () async {
      final a = await ok(
        '[{"duration":300,"plainLyrics":"x","syncedLyrics":null}]',
      ).search(_q);
      expect(a, isA<Nothing>());
    });

    test('500 is Failed', () async {
      expect(await ok('[]', 500).search(_q), isA<Failed>());
    });
  });
}
