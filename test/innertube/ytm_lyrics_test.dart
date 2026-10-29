import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/transport.dart';
import 'package:songies/innertube/ytm_parse.dart';
import 'package:songies/innertube/ytm_service.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_sources.dart';
import 'package:songies/lyrics/ytm_lyrics.dart';

import '../helpers/fake_innertube_transport.dart';
import '../helpers/test_db.dart';

Json lyricsFixture(String name) => (jsonDecode(
  File('test/fixtures/lyrics/$name.json').readAsStringSync(),
) as Map).cast<String, Object?>();

Json browseWithText(String text) => {
  'contents': {
    'sectionListRenderer': {
      'contents': [
        {
          'musicDescriptionShelfRenderer': {
            'description': {
              'runs': [
                {'text': text},
              ],
            },
          },
        },
      ],
    },
  },
};

Json nextWithTabs(List<Json> tabs) => {
  'contents': {
    'singleColumnMusicWatchNextResultsRenderer': {
      'tabbedRenderer': {
        'watchNextTabbedResultsRenderer': {
          'tabs': [
            for (final t in tabs) {'tabRenderer': t},
          ],
        },
      },
    },
  },
};

final noLyricsNext = nextWithTabs([
  {'title': 'Up next'},
  {'title': 'Lyrics'},
  {'title': 'Related', 'endpoint': endpoint('MPTRt_x')},
]);

Json endpoint(String id) => {
  'browseEndpoint': {'browseId': id},
};

void main() {
  late AppDatabase db;
  late FakeTransport transport;
  late InnertubeClient client;
  late YtmService ytm;

  setUp(() {
    db = testDb();
    transport = FakeTransport();
    client = InnertubeClient(transport, SettingsRepository(db));
    ytm = YtmService(client);
  });
  tearDown(() async {
    client.dispose();
    await db.close();
  });

  group('lyricsBrowseId', () {
    test('finds the Lyrics tab id', () {
      expect(
        lyricsBrowseId(lyricsFixture('ytm_next_lyrics_tab')),
        'MPLYtFixture0001',
      );
    });

    test('finds the id in the recorded radio response', () {
      expect(lyricsBrowseId(fixture('next_radio').json!), startsWith('MPLYt'));
    });

    test('null when there is no Lyrics tab', () {
      expect(lyricsBrowseId(noLyricsNext), isNull);
    });

    test('a Lyrics tab without an endpoint is null', () {
      final json = nextWithTabs([
        {'title': 'Lyrics'},
        {'title': 'Related', 'endpoint': endpoint('MPREb_x')},
      ]);
      expect(lyricsBrowseId(json), isNull);
    });

    test('falls back to an MPLY id when the title is localized', () {
      final json = nextWithTabs([
        {'title': 'Texty', 'endpoint': endpoint('MPLYtLocal')},
      ]);
      expect(lyricsBrowseId(json), 'MPLYtLocal');
    });

    test('null on an empty response', () {
      expect(lyricsBrowseId({}), isNull);
    });
  });

  group('parseLyricsBrowse', () {
    test('plain text and credit', () {
      final l = parseLyricsBrowse(lyricsFixture('ytm_browse_lyrics_plain'))!;
      expect(l.kind, LyricsKind.plain);
      expect(l.source, LyricsSource.youtube);
      expect(l.text, startsWith('First invented line\nSecond'));
      expect(l.credit, 'Source: Musixmatch');
    });

    test('null on {} and on whitespace-only text', () {
      expect(parseLyricsBrowse({}), isNull);
      expect(parseLyricsBrowse(browseWithText('  \n ')), isNull);
    });

    test('no footer means no credit', () {
      expect(parseLyricsBrowse(browseWithText('la la'))!.credit, isNull);
    });
  });

  group('YtmService.lyrics', () {
    test('calls next then browse and returns plain lyrics', () async {
      transport.reply(
        InnertubeResponse(200, lyricsFixture('ytm_next_lyrics_tab')),
      );
      transport.reply(
        InnertubeResponse(200, lyricsFixture('ytm_browse_lyrics_plain')),
      );
      final res = await ytm.lyrics('vid123');
      final l = (res as Ok<TrackLyrics?>).value!;
      expect(l.kind, LyricsKind.plain);
      expect(l.credit, 'Source: Musixmatch');
      expect(transport.requests, hasLength(2));
      expect(transport.requests[0].url.path, endsWith('/next'));
      expect(transport.requests[0].body['videoId'], 'vid123');
      expect(transport.requests[0].body['isAudioOnly'], true);
      expect(transport.requests[1].url.path, endsWith('/browse'));
      expect(transport.requests[1].body['browseId'], 'MPLYtFixture0001');
    });

    test('no lyrics tab is Ok(null) without a browse', () async {
      transport.reply(InnertubeResponse(200, noLyricsNext));
      final res = await ytm.lyrics('vid123');
      expect((res as Ok<TrackLyrics?>).value, isNull);
      expect(transport.requests, hasLength(1));
    });

    test('a next failure is Err', () async {
      transport.reply(const InnertubeResponse(500, null));
      expect(await ytm.lyrics('vid123'), isA<Err<TrackLyrics?>>());
    });

    test('a browse failure is Err', () async {
      transport.reply(
        InnertubeResponse(200, lyricsFixture('ytm_next_lyrics_tab')),
      );
      transport.reply(const InnertubeResponse(500, null));
      expect(await ytm.lyrics('vid123'), isA<Err<TrackLyrics?>>());
    });

    test('empty text is Ok(null)', () async {
      transport.reply(
        InnertubeResponse(200, lyricsFixture('ytm_next_lyrics_tab')),
      );
      transport.reply(InnertubeResponse(200, browseWithText('   ')));
      expect((await ytm.lyrics('v') as Ok<TrackLyrics?>).value, isNull);
    });
  });

  group('YtmLyricsSource', () {
    late YtmLyricsSource source;
    setUp(() => source = YtmLyricsSource(ytm));

    test('null id is Nothing without a request', () async {
      expect(await source.fetch(null), isA<Nothing>());
      expect(transport.requests, isEmpty);
    });

    test('Ok(null) is Nothing', () async {
      transport.reply(InnertubeResponse(200, noLyricsNext));
      expect(await source.fetch('v'), isA<Nothing>());
    });

    test('Ok(lyrics) is Found', () async {
      transport.reply(
        InnertubeResponse(200, lyricsFixture('ytm_next_lyrics_tab')),
      );
      transport.reply(
        InnertubeResponse(200, lyricsFixture('ytm_browse_lyrics_plain')),
      );
      final a = await source.fetch('v');
      expect((a as Found).lyrics.source, LyricsSource.youtube);
    });

    test('Err is Failed', () async {
      transport.reply(const InnertubeResponse(500, null));
      expect(await source.fetch('v'), isA<Failed>());
    });
  });
}
