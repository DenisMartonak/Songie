import 'package:flutter_test/flutter_test.dart';
import 'package:songies/youtube/yt_links.dart';

void main() {
  const canon = 'https://music.youtube.com/playlist?list=PLx';

  group('parsePlaylistLink', () {
    test('accepts the supported shapes', () {
      for (final s in [
        'https://music.youtube.com/playlist?list=PLx',
        'https://www.youtube.com/playlist?list=PLx&si=abc',
        '  youtube.com/playlist?list=PLx  ',
        'https://m.youtube.com/playlist?list=PLx',
        'https://youtu.be/abc?list=PLx',
      ]) {
        expect(parsePlaylistLink(s), canon, reason: s);
      }
    });

    test('rejects non-playlist input', () {
      for (final s in [
        'https://www.youtube.com/watch?v=abc',
        'hello',
        '',
        'https://example.com/playlist?list=PLx',
        'https://youtube.com/playlist?list=',
        'ftp://youtube.com/playlist?list=PLx',
      ]) {
        expect(parsePlaylistLink(s), isNull, reason: s);
      }
    });
  });

  group('extractLinkFromSharedText', () {
    test('finds the link in share text', () {
      expect(
        extractLinkFromSharedText(
          'Check this https://music.youtube.com/playlist?list=PLx',
        ),
        canon,
      );
      expect(
        extractLinkFromSharedText(
          'https://www.youtube.com/playlist?list=PLx&si=z lovely',
        ),
        canon,
      );
    });

    test('null when there is no playlist link', () {
      expect(extractLinkFromSharedText('no link here'), isNull);
      expect(
        extractLinkFromSharedText('see https://youtube.com/watch?v=abc'),
        isNull,
      );
    });
  });
}
