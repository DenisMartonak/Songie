import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/transport.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/innertube/ytm_service.dart';

import '../helpers/fake_innertube_transport.dart';
import '../helpers/test_db.dart';

List<Object?> _shelfRows(InnertubeResponse r) {
  final sections =
      (((((r.json!['contents']! as Map)['tabbedSearchResultsRenderer']!
                          as Map)['tabs']!
                      as List)[0]
                  as Map)['tabRenderer']!
              as Map)['content']!
          as Map;
  final list = (sections['sectionListRenderer']! as Map)['contents']! as List;
  return ((list[1] as Map)['musicShelfRenderer']! as Map)['contents']!
      as List<Object?>;
}

void main() {
  late AppDatabase db;
  late FakeTransport transport;
  late InnertubeClient client;
  late YtmService ytm;

  setUp(() async {
    db = testDb();
    transport = FakeTransport();
    client = InnertubeClient(transport, SettingsRepository(db));
    ytm = YtmService(client);
  });
  tearDown(() async {
    client.dispose();
    await db.close();
  });

  Future<YtmSearchPage> search(
    InnertubeResponse r,
    YtmSearchKind kind, {
    String? continuation,
  }) async {
    transport.reply(r);
    final res = await ytm.search('daft punk', kind, continuation: continuation);
    return (res as Ok<YtmSearchPage>).value;
  }

  test('songs: rich rows, UC artist ids, largest thumbnail at 544', () async {
    final page = await search(fixture('search_songs'), YtmSearchKind.songs);
    final songs = page.items.cast<YtmSong>();
    expect(songs.length, greaterThanOrEqualTo(10));
    for (final s in songs) {
      expect(s.videoId, isNotEmpty);
      expect(s.title, isNotEmpty);
      expect(s.artists, isNotEmpty);
      expect(s.durationMs, isNotNull);
      for (final a in s.artists) {
        if (a.browseId != null) expect(a.browseId, startsWith('UC'));
      }
    }
    final first = songs.first;
    expect(first.videoId, 'khnokW3Mw24');
    expect(first.title, 'Instant Crush (feat. Julian Casablancas)');
    expect(first.artistLine, 'Daft Punk, Julian Casablancas');
    expect(first.artists.first.browseId, 'UCRr1xG_2WIDs18a6cIiCxeA');
    expect(first.album, 'Random Access Memories');
    expect(first.albumBrowseId, 'MPREb_K8qWMWVqXGi');
    expect(first.durationMs, (5 * 60 + 38) * 1000);
    expect(first.isVideo, isFalse);
    expect(first.thumbnailUrl, endsWith('=w544-h544-l90-rj'));
    expect(page.continuation, 'FAKE_CONTINUATION');
  });

  test('request body carries the songs filter; continuation is sent', () async {
    await search(fixture('search_songs'), YtmSearchKind.songs);
    expect(
      transport.requests.last.body['params'],
      'EgWKAQIIAWoSEAUQCRADEAQQEBAKEA4QFRAR',
    );
    expect(transport.requests.last.body['query'], 'daft punk');
    expect(transport.requests.last.url.path, endsWith('/search'));
    await search(
      fixture('search_songs'),
      YtmSearchKind.songs,
      continuation: 'TOKEN',
    );
    expect(transport.requests.last.body['continuation'], 'TOKEN');
    final q = transport.requests.last.url.queryParameters;
    expect(q['ctoken'], 'TOKEN');
    expect(q['continuation'], 'TOKEN');
    expect(q['type'], 'next');
    expect(q['prettyPrint'], 'false');
    expect(transport.requests.last.body.containsKey('query'), isFalse);
  });

  test('filter params per kind', () async {
    const expected = {
      YtmSearchKind.videos: 'EgWKAQIQAWoSEAUQCRADEAQQEBAKEA4QFRAR',
      YtmSearchKind.albums: 'EgWKAQIYAWoSEAUQCRADEAQQEBAKEA4QFRAR',
      YtmSearchKind.artists: 'EgWKAQIgAWoSEAUQCRADEAQQEBAKEA4QFRAR',
      YtmSearchKind.playlists: 'EgeKAQQoAEABahIQBRAJEAMQBBAQEAoQDhAVEBE%3D',
    };
    for (final e in expected.entries) {
      await search(fixture('search_${e.key.name}_handcrafted'), e.key);
      expect(transport.requests.last.body['params'], e.value);
    }
  });

  test('videos parse to YtmSong with isVideo', () async {
    final page = await search(
      fixture('search_videos_handcrafted'),
      YtmSearchKind.videos,
    );
    final v = page.items.cast<YtmSong>();
    expect(v, hasLength(3));
    expect(v.first.videoId, 'PwILkY9gRrc');
    expect(v.first.title, 'Da Funk');
    expect(v.first.artistLine, 'Daft Punk');
    expect(v.every((s) => s.isVideo), isTrue);
  });

  test('albums parse to YtmAlbum', () async {
    final page = await search(
      fixture('search_albums_handcrafted'),
      YtmSearchKind.albums,
    );
    final a = page.items.cast<YtmAlbum>();
    expect(a, hasLength(3));
    expect(a.first.browseId, 'MPREb_K8qWMWVqXGi');
    expect(a.first.title, 'Random Access Memories');
    expect(a.first.artist, 'Daft Punk');
    expect(a.first.year, '2013');
    expect(a.first.playlistId, startsWith('OLAK5uy_'));
    expect(a.first.thumbnailUrl, contains('w544-h544'));
  });

  test('artists parse to YtmArtist', () async {
    final page = await search(
      fixture('search_artists_handcrafted'),
      YtmSearchKind.artists,
    );
    final a = page.items.cast<YtmArtist>();
    expect(a, hasLength(3));
    expect(a.first.browseId, 'UClYV6hHlupm_S_ObS1W-DYw');
    expect(a.first.name, 'The Weeknd');
    expect(a.first.thumbnailUrl, isNotNull);
  });

  test('playlists parse to YtmPlaylist', () async {
    final page = await search(
      fixture('search_playlists_handcrafted'),
      YtmSearchKind.playlists,
    );
    final p = page.items.cast<YtmPlaylist>();
    expect(p, hasLength(6));
    expect(p.first.browseId, 'VLPL-hvaaoSDXQJpFhQYRkEjc_Zh4Sd65c-e');
    expect(p.first.title, 'EVERY DAFT PUNK MUSIC VIDEO 🤖🤖🎬');
    expect(p.first.author, 'GotWub');
  });

  test('a row without a title is dropped, nothing throws', () async {
    final full = await search(fixture('search_songs'), YtmSearchKind.songs);
    final r = fixture('search_songs');
    final row = _shelfRows(r)[3]! as Map;
    final cols =
        (row['musicResponsiveListItemRenderer']! as Map)['flexColumns'] as List;
    ((cols[0] as Map)['musicResponsiveListItemFlexColumnRenderer']! as Map)
        .remove('text');
    final page = await search(r, YtmSearchKind.songs);
    expect(page.items.length, full.items.length - 1);
  });

  test('an unknown renderer type is skipped', () async {
    final full = await search(fixture('search_songs'), YtmSearchKind.songs);
    final r = fixture('search_songs');
    _shelfRows(r).insert(2, {
      'someFutureRenderer': {'x': 1},
    });
    final page = await search(r, YtmSearchKind.songs);
    expect(page.items.length, full.items.length);
  });

  test('a missing shelf gives an empty page', () async {
    transport.reply(InnertubeResponse(200, {'contents': {}}));
    final res = await ytm.search('q', YtmSearchKind.songs);
    final page = (res as Ok<YtmSearchPage>).value;
    expect(page.items, isEmpty);
    expect(page.continuation, isNull);
  });

  test('a continuation response parses its shelf', () async {
    transport.reply(
      InnertubeResponse(200, {
        'continuationContents': {
          'musicShelfContinuation': {
            'contents': _shelfRows(fixture('search_songs')).take(2).toList(),
          },
        },
      }),
    );
    final res = await ytm.search('q', YtmSearchKind.songs, continuation: 'T');
    final page = (res as Ok<YtmSearchPage>).value;
    expect(page.items, hasLength(2));
    expect(page.continuation, isNull);
  });

  test('a transport error is passed through', () async {
    transport.reply(InnertubeResponse(500, null));
    final res = await ytm.search('q', YtmSearchKind.songs);
    expect(res, isA<Err<YtmSearchPage>>());
    expect((res as Err).failure.message, contains('HTTP 500'));
  });
}
