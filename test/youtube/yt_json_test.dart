import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/youtube/yt_json.dart';
import 'package:songies/youtube/yt_models.dart';

String fixture(String n) => File('test/fixtures/ytdlp/$n').readAsStringSync();

void main() {
  test('parsePlaylistJson reads the flat fixture', () {
    final p = parsePlaylistJson(fixture('playlist_flat.json'));
    expect(p.id, 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
    expect(p.title, 'Popular Music Videos');
    expect(p.entries, hasLength(5));
    final e = p.entries.first;
    expect(e.videoId, 'fOT0BUpITw8');
    expect(e.title, 'BELLAKEO (Video Oficial) - Peso Pluma, Anitta');
    expect(e.durationMs, 235000);
    expect(e.artist, 'Peso Pluma');
    expect(e.thumbnailUrl, isNotNull);
    expect(p.entries.every((x) => !x.unavailable), isTrue);
  });

  test('private and deleted entries are kept as unavailable', () {
    final p = parsePlaylistJson(fixture('playlist_with_private.json'));
    final byId = {for (final e in p.entries) e.videoId: e};
    expect(byId['ETbOX50t0kw']!.unavailable, isTrue);
    expect(byId['RcUnmaanrNM']!.unavailable, isTrue);
    expect(byId['H6T1FW7qMxA']!.unavailable, isFalse);
    expect(byId['H6T1FW7qMxA']!.title, startsWith('[ORIGINAL]'));
    expect(byId['FzG4uDgje3M']!.unavailable, isFalse);
    expect(byId['feA64wXhbjo']!.unavailable, isFalse);
  });

  test('null title/duration/channel are tolerated', () {
    final p = parsePlaylistJson(
      '{"id":"P","title":"T","entries":[{"id":"a","title":null,'
      '"duration":null,"channel":null,"uploader":null}]}',
    );
    expect(p.entries.single.unavailable, isTrue);
    expect(p.entries.single.title, '');
    expect(p.entries.single.durationMs, 0);
  });

  test('a null duration with a channel stays available', () {
    final p = parsePlaylistJson(
      '{"id":"P","title":"T","entries":[{"id":"a","title":"Live",'
      '"duration":null,"channel":"C"}]}',
    );
    expect(p.entries.single.unavailable, isFalse);
  });

  test('" - Topic" channels become the artist', () {
    final p = parsePlaylistJson(
      '{"id":"P","title":"T","entries":[{"id":"a","title":"Song",'
      '"duration":10,"channel":"Daft Punk - Topic"}]}',
    );
    expect(p.entries.single.artist, 'Daft Punk');
    expect(cleanArtist('X - Topic'), 'X');
    expect(cleanArtist('Plain'), 'Plain');
  });

  test('parsePlaylistJson throws when entries are missing', () {
    expect(
      () => parsePlaylistJson('{"id":"v","title":"t"}'),
      throwsFormatException,
    );
  });

  test('pickThumbnail prefers square, else largest', () {
    expect(
      pickThumbnail([
        {'url': 'a', 'width': 100, 'height': 50},
        {'url': 'b', 'width': 60, 'height': 60},
        {'url': 'c', 'width': 400, 'height': 200},
      ]),
      'b',
    );
    expect(
      pickThumbnail([
        {'url': 'a', 'width': 100, 'height': 50},
        {'url': 'c', 'width': 400, 'height': 200},
      ]),
      'c',
    );
    expect(
      pickThumbnail([
        {'url': 'a', 'width': 60, 'height': 60},
        {'url': 'd', 'width': 120, 'height': 120},
      ]),
      'd',
    );
    expect(pickThumbnail([]), isNull);
  });

  test('parseStreamJson reads url, headers, expiry and metadata', () {
    final s = parseStreamJson(fixture('stream_opus.json'));
    expect(s.url.toString(), isNotEmpty);
    expect(s.headers, contains('User-Agent'));
    expect(s.expiresAt, isNotNull);
    expect(
      s.expiresAt!.millisecondsSinceEpoch ~/ 1000,
      int.parse(s.url.queryParameters['expire']!),
    );
    expect(s.title, 'BELLAKEO (Video Oficial) - Peso Pluma, Anitta');
    expect(s.artist, 'Peso Pluma');
    expect(s.album, isNull);
    expect(s.durationMs, 234000);
  });

  test('parseStreamJson rejects a missing url', () {
    expect(() => parseStreamJson('{"title":"x"}'), throwsFormatException);
  });

  group('ytdlp errors', () {
    test('failure encoding round-trips and maps FailureKind', () {
      final f = ytFailure(YtErrorKind.notAPlaylist, 'x');
      expect(f.message, 'ytdlp:notAPlaylist:x');
      expect(f.kind, FailureKind.notFound);
      expect(ytErrorKindOf(f), YtErrorKind.notAPlaylist);
      expect(ytFailure(YtErrorKind.notFound, '').kind, FailureKind.notFound);
      expect(ytFailure(YtErrorKind.network, '').kind, FailureKind.network);
      for (final k in [
        YtErrorKind.extractor,
        YtErrorKind.missingBinary,
        YtErrorKind.unknown,
      ]) {
        expect(ytFailure(k, '').kind, FailureKind.unknown);
        expect(ytErrorKindOf(ytFailure(k, 'a:b')), k);
      }
    });

    test('user messages', () {
      expect(
        ytErrorUserMessage(ytFailure(YtErrorKind.notAPlaylist, '')),
        "That's a video link — paste a playlist link",
      );
      expect(
        ytErrorUserMessage(ytFailure(YtErrorKind.notFound, '')),
        'Not found on YouTube — it may be private or deleted',
      );
      expect(
        ytErrorUserMessage(ytFailure(YtErrorKind.network, '')),
        "Couldn't reach YouTube — check your connection",
      );
      expect(
        ytErrorUserMessage(ytFailure(YtErrorKind.extractor, '')),
        'YouTube changed something — try Settings → Update yt-dlp',
      );
      expect(
        ytErrorUserMessage(ytFailure(YtErrorKind.missingBinary, '')),
        "yt-dlp isn't installed — install it in Settings",
      );
      expect(
        ytErrorUserMessage(ytFailure(YtErrorKind.unknown, '')),
        'Something went wrong with yt-dlp',
      );
      const other = Failure(FailureKind.io, 'disk full');
      expect(ytErrorKindOf(other), isNull);
      expect(ytErrorUserMessage(other), 'disk full');
    });
  });
}
