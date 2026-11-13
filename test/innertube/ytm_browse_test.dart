import 'dart:convert';

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

/// A deep copy of a fixture's JSON, so a test can delete keys from it.
Map<String, Object?> mutable(String name) =>
    (jsonDecode(jsonEncode(fixture(name).json)) as Map).cast<String, Object?>();

InnertubeResponse ok(Map<String, Object?> json) => InnertubeResponse(200, json);

/// The `sectionListRenderer.contents` list of a single-column browse page.
List<Object?> homeSections(Map<String, Object?> json) {
  Object? v = json;
  for (final k in [
    'contents',
    'singleColumnBrowseResultsRenderer',
    'tabs',
    0,
    'tabRenderer',
    'content',
    'sectionListRenderer',
    'contents',
  ]) {
    v = k is int ? (v! as List)[k] : (v! as Map)[k];
  }
  return v! as List<Object?>;
}

Map<String, Object?> shelfBody(Object? section) =>
    ((section! as Map).values.first as Map).cast<String, Object?>();

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

  group('home', () {
    test(
      'a first page with no section list is an unexpected-shape Err',
      () async {
        final json = mutable('browse_home')..remove('contents');
        transport.reply(ok(json));
        final r = await ytm.home();
        expect(r, isA<Err<YtmHome>>());
        expect((r as Err<YtmHome>).failure.message, contains('unexpected'));
      },
    );

    test('a first page with an empty section list is an Err too', () async {
      final json = mutable('browse_home');
      homeSections(json).clear();
      transport.reply(ok(json));
      expect(await ytm.home(), isA<Err<YtmHome>>());
    });

    test('an empty continuation page is still Ok', () async {
      transport.reply(ok(const {}));
      final r = await ytm.home(continuation: 'TOK');
      expect((r as Ok<YtmHome>).value.shelves, isEmpty);
    });

    test('parses shelves of songs, playlists and albums', () async {
      transport.reply(fixture('browse_home'));
      final home = ((await ytm.home()) as Ok<YtmHome>).value;
      expect(home.shelves.length, greaterThanOrEqualTo(3));
      for (final s in home.shelves) {
        expect(s.title, isNotEmpty);
        expect(s.items, isNotEmpty);
      }
      expect(home.shelves.first.items.first, isA<YtmSong>());
      expect(home.shelves[1].items.first, isA<YtmPlaylist>());
      expect(home.continuation, 'FAKE_CONTINUATION');
      final req = transport.requests.single;
      expect(req.url.path, endsWith('/browse'));
      expect(req.body['browseId'], 'FEmusic_home');
    });

    for (final name in ['home_signed_in', 'home_signed_out_marker']) {
      test('the Plan 7 fixture $name parses like the Plan 5 Home', () async {
        transport.reply(fixture(name));
        final home = ((await ytm.home()) as Ok<YtmHome>).value;
        expect(home.shelves.length, greaterThanOrEqualTo(3));
        for (final s in home.shelves) {
          expect(s.title, isNotEmpty);
          expect(s.items, isNotEmpty);
        }
      });
    }

    test('two-row items carry ids, titles and 544 px art', () async {
      transport.reply(fixture('browse_home'));
      final home = ((await ytm.home()) as Ok<YtmHome>).value;
      final p = home.shelves[1].items.first as YtmPlaylist;
      expect(p.browseId, startsWith('VL'));
      expect(p.title, isNotEmpty);
      expect(p.thumbnailUrl, contains('w544-h544'));
    });

    test('a shelf without contents drops alone', () async {
      final json = mutable('browse_home');
      shelfBody(homeSections(json)[1]).remove('contents');
      transport.reply(ok(json));
      final home = ((await ytm.home()) as Ok<YtmHome>).value;
      expect(home.shelves.length, 2);
    });

    test('a shelf whose items all fail to parse is dropped', () async {
      final json = mutable('browse_home');
      final body = shelfBody(homeSections(json)[2]);
      body['contents'] = [
        for (final _ in body['contents']! as List)
          {
            'musicTwoRowItemRenderer': {'title': 5},
          },
      ];
      transport.reply(ok(json));
      final home = ((await ytm.home()) as Ok<YtmHome>).value;
      expect(home.shelves.length, 2);
    });

    test('one bad row drops alone, an unknown shelf type is skipped', () async {
      final json = mutable('browse_home');
      final sections = homeSections(json);
      final items = shelfBody(sections[1])['contents']! as List;
      final before = items.length;
      items[0] = {
        'musicTwoRowItemRenderer': {'title': null},
      };
      sections.add({'someNewShelfRenderer': {}});
      transport.reply(ok(json));
      final home = ((await ytm.home()) as Ok<YtmHome>).value;
      expect(home.shelves.length, 3);
      expect(home.shelves[1].items.length, before - 1);
    });

    test(
      'continuation: token in query and body, parses more shelves',
      () async {
        final json = mutable('browse_home');
        final more = {
          'continuationContents': {
            'sectionListContinuation': {
              'contents': homeSections(json).sublist(1, 2),
              'continuations': [
                {
                  'nextContinuationData': {'continuation': 'NEXT_TOKEN'},
                },
              ],
            },
          },
        };
        transport.reply(ok(more));
        final home =
            ((await ytm.home(continuation: 'TOK')) as Ok<YtmHome>).value;
        expect(home.shelves.length, 1);
        expect(home.continuation, 'NEXT_TOKEN');
        final req = transport.requests.single;
        expect(req.body['continuation'], 'TOK');
        expect(req.url.queryParameters['ctoken'], 'TOK');
        expect(req.url.queryParameters['continuation'], 'TOK');
        expect(req.url.queryParameters['type'], 'next');
      },
    );
  });

  group('artist', () {
    test('parses header, top songs, albums, singles, similar', () async {
      transport.reply(fixture('browse_artist'));
      final page = ((await ytm.artist(
        'UCRr1xG_2WIDs18a6cIiCxeA',
      )) as Ok<YtmArtistPage>).value;
      expect(page.artist.name, 'Daft Punk');
      expect(page.artist.browseId, 'UCRr1xG_2WIDs18a6cIiCxeA');
      expect(page.artist.thumbnailUrl, isNotNull);
      expect(page.topSongs, isNotEmpty);
      expect(page.topSongs.first.videoId, 'khnokW3Mw24');
      expect(page.topSongs.first.album, 'Random Access Memories');
      expect(page.albums, isNotEmpty);
      expect(page.albums.first.playlistId, startsWith('OLAK5uy_'));
      expect(page.albums.first.year, matches(r'^\d{4}$'));
      expect(page.albums.first.artist, 'Daft Punk');
      expect(page.singles, isNotEmpty);
      expect(page.similar, isNotEmpty);
      expect(page.similar.first.browseId, startsWith('UC'));
      expect(page.radioPlaylistId, startsWith('RDEM'));
      expect(page.monthlyListeners, '68M');
      final req = transport.requests.single;
      expect(req.body['browseId'], 'UCRr1xG_2WIDs18a6cIiCxeA');
    });

    test('no monthlyListenerCount: monthlyListeners is null', () async {
      final json = mutable('browse_artist');
      ((json['header']! as Map)['musicImmersiveHeaderRenderer'] as Map).remove(
        'monthlyListenerCount',
      );
      transport.reply(ok(json));
      final page = ((await ytm.artist(
        'UCRr1xG_2WIDs18a6cIiCxeA',
      )) as Ok<YtmArtistPage>).value;
      expect(page.monthlyListeners, isNull);
    });

    test('a carousel without contents drops alone', () async {
      final json = mutable('browse_artist');
      final sections = homeSections(json);
      shelfBody(sections[1]).remove('contents');
      transport.reply(ok(json));
      final page = ((await ytm.artist(
        'UCRr1xG_2WIDs18a6cIiCxeA',
      )) as Ok<YtmArtistPage>).value;
      expect(page.albums, isEmpty);
      expect(page.topSongs, isNotEmpty);
      expect(page.singles, isNotEmpty);
    });

    group('album shelf titles match "EP" as a word', () {
      void retitle(Map<String, Object?> json, int section, String title) {
        final header = shelfBody(homeSections(json)[section])['header']! as Map;
        final runs =
            ((header['musicCarouselShelfBasicHeaderRenderer']! as Map)['title']!
                    as Map)['runs']!
                as List;
        (runs.first as Map)['text'] = title;
      }

      Future<YtmArtistPage> load(Map<String, Object?> json) async {
        transport.reply(ok(json));
        return ((await ytm.artist(
          'UCRr1xG_2WIDs18a6cIiCxeA',
        )) as Ok<YtmArtistPage>).value;
      }

      test('"Deep cuts" is not singles', () async {
        final base = await load(mutable('browse_artist'));
        final json = mutable('browse_artist');
        retitle(json, 1, 'Deep cuts');
        final page = await load(json);
        expect(page.albums, isEmpty);
        expect(page.singles.length, base.singles.length);
      });

      test('"EPs" and "Singles & EPs" are singles', () async {
        final json = mutable('browse_artist');
        retitle(json, 1, 'EPs');
        final page = await load(json);
        expect(page.albums, isEmpty);
        expect(page.singles, isNotEmpty);
        expect(
          page.singles.length,
          greaterThan((await load(mutable('browse_artist'))).singles.length),
        );
      });
    });

    test('no header and no name is an Err', () async {
      final json = mutable('browse_artist')..remove('header');
      transport.reply(ok(json));
      expect(await ytm.artist('UCx'), isA<Err<YtmArtistPage>>());
    });
  });

  group('album', () {
    test('parses header and the whole tracklist', () async {
      final json = fixture('browse_album').json!;
      final shelf =
          (((((((json['contents']! as Map)['twoColumnBrowseResultsRenderer']!
                                  as Map)['secondaryContents']!
                              as Map)['sectionListRenderer']!
                          as Map)['contents']!
                      as List)[0]
                  as Map)['musicShelfRenderer']!
              as Map);
      final rows = (shelf['contents']! as List).length;
      transport.reply(fixture('browse_album'));
      final page =
          ((await ytm.album('MPREb_K8qWMWVqXGi')) as Ok<YtmAlbumPage>).value;
      expect(page.tracks.length, rows);
      expect(page.album.title, 'Random Access Memories');
      expect(page.album.browseId, 'MPREb_K8qWMWVqXGi');
      expect(page.album.playlistId, startsWith('OLAK5uy_'));
      expect(page.album.artist, 'Daft Punk');
      expect(page.album.year, '2013');
      expect(page.album.thumbnailUrl, contains('w544-h544'));
      for (final t in page.tracks) {
        expect(t.album, 'Random Access Memories');
        expect(t.albumBrowseId, 'MPREb_K8qWMWVqXGi');
        expect(t.thumbnailUrl, page.album.thumbnailUrl);
        expect(t.artists, isNotEmpty);
      }
      expect(page.tracks.first.title, 'Give Life Back to Music');
      expect(page.tracks.first.durationMs, (4 * 60 + 36) * 1000);
    });

    test('a bad track row drops alone', () async {
      final json = mutable('browse_album');
      final shelf = shelfBody(
        (((((json['contents']! as Map)['twoColumnBrowseResultsRenderer']!
                        as Map)['secondaryContents']!
                    as Map)['sectionListRenderer']!
                as Map)['contents']!
            as List)[0],
      );
      final rows = shelf['contents']! as List;
      final n = rows.length;
      rows[2] = {
        'musicResponsiveListItemRenderer': {'flexColumns': 'x'},
      };
      transport.reply(ok(json));
      final page =
          ((await ytm.album('MPREb_K8qWMWVqXGi')) as Ok<YtmAlbumPage>).value;
      expect(page.tracks.length, n - 1);
    });
  });

  group('playlist', () {
    test('parses header, first page and continuation', () async {
      transport.reply(fixture('browse_playlist'));
      final page = ((await ytm.playlist(
        'PL-hvaaoSDXQJpFhQYRkEjc_Zh4Sd65c-e',
      )) as Ok<YtmPlaylistPage>).value;
      expect(page.playlist.title, startsWith('EVERY DAFT PUNK'));
      expect(page.playlist.browseId, 'VLPL-hvaaoSDXQJpFhQYRkEjc_Zh4Sd65c-e');
      expect(page.playlist.author, 'GotWub');
      // 42 rows; row 39 is an unavailable video with no watch endpoint.
      expect(page.tracks.length, 41);
      expect(page.tracks.first.title, 'Da Funk');
      expect(page.tracks.first.durationMs, (5 * 60 + 35) * 1000);
      expect(page.continuation, 'FAKE_CONTINUATION');
      expect(
        transport.requests.single.body['browseId'],
        'VLPL-hvaaoSDXQJpFhQYRkEjc_Zh4Sd65c-e',
      );
    });

    test('continuation page: rows, next token, query params', () async {
      final json = fixture('browse_playlist').json!;
      final rows =
          ((((((((json['contents']! as Map)['twoColumnBrowseResultsRenderer']!
                                      as Map)['secondaryContents']!
                                  as Map)['sectionListRenderer']!
                              as Map)['contents']!
                          as List)[0]
                      as Map)['musicPlaylistShelfRenderer']!
                  as Map)['contents']!
              as List);
      transport.reply(
        ok({
          'continuationContents': {
            'musicPlaylistShelfContinuation': {
              'contents': rows.sublist(0, 5),
              'continuations': [
                {
                  'nextContinuationData': {'continuation': 'NEXT'},
                },
              ],
            },
          },
        }),
      );
      final page = ((await ytm.playlist(
        'VLPLx',
        continuation: 'TOK',
      )) as Ok<YtmPlaylistPage>).value;
      expect(page.tracks.length, 5);
      expect(page.continuation, 'NEXT');
      final req = transport.requests.single;
      expect(req.body['continuation'], 'TOK');
      expect(req.url.queryParameters['ctoken'], 'TOK');
      expect(req.url.queryParameters['type'], 'next');
    });

    test('the appendContinuationItemsAction shape also works', () async {
      final json = fixture('browse_playlist').json!;
      final rows =
          ((((((((json['contents']! as Map)['twoColumnBrowseResultsRenderer']!
                                      as Map)['secondaryContents']!
                                  as Map)['sectionListRenderer']!
                              as Map)['contents']!
                          as List)[0]
                      as Map)['musicPlaylistShelfRenderer']!
                  as Map)['contents']!
              as List);
      transport.reply(
        ok({
          'onResponseReceivedActions': [
            {
              'appendContinuationItemsAction': {
                'continuationItems': [
                  ...rows.sublist(0, 3),
                  {
                    'continuationItemRenderer': {
                      'continuationEndpoint': {
                        'continuationCommand': {'token': 'T2'},
                      },
                    },
                  },
                ],
              },
            },
          ],
        }),
      );
      final page = ((await ytm.playlist(
        'VLPLx',
        continuation: 'TOK',
      )) as Ok<YtmPlaylistPage>).value;
      expect(page.tracks.length, 3);
      expect(page.continuation, 'T2');
    });
  });
}
