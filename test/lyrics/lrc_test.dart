import 'package:flutter_test/flutter_test.dart';
import 'package:songies/lyrics/lrc.dart';
import 'package:songies/lyrics/lyrics.dart';

void main() {
  group('parseLrc', () {
    test('parses mm:ss.xx', () {
      final l = parseLrc('[00:12.34]a')!;
      expect(l.single.time, const Duration(seconds: 12, milliseconds: 340));
      expect(l.single.text, 'a');
    });

    test('three digit fraction is milliseconds', () {
      expect(
        parseLrc('[01:02.345]b')!.single.time,
        const Duration(seconds: 62, milliseconds: 345),
      );
    });

    test('no fraction', () {
      expect(parseLrc('[00:05]c')!.single.time, const Duration(seconds: 5));
    });

    test('one digit fraction is tenths', () {
      expect(
        parseLrc('[00:05.5]c')!.single.time,
        const Duration(seconds: 5, milliseconds: 500),
      );
    });

    test('multiple stamps give multiple lines', () {
      final l = parseLrc('[00:01.00][00:09.00]x')!;
      expect(l.map((e) => e.time.inSeconds), [1, 9]);
      expect(l.every((e) => e.text == 'x'), isTrue);
    });

    test('metadata tags are ignored', () {
      final l = parseLrc('[ar:A]\n[ti:T]\n[length:3:00]\n[00:01.00]a')!;
      expect(l, hasLength(1));
      expect(l.single.text, 'a');
    });

    test('positive offset shifts lyrics 500 ms earlier', () {
      final l = parseLrc('[offset:+500]\n[00:01.00]a\n[00:00.20]b')!;
      expect(l[0].time, Duration.zero);
      expect(l[1].time, const Duration(milliseconds: 500));
    });

    test('negative offset shifts later', () {
      final l = parseLrc('[offset:-500]\n[00:01.00]a')!;
      expect(l.single.time, const Duration(milliseconds: 1500));
    });

    test('inline word stamps are stripped', () {
      expect(
        parseLrc('[00:01.00]<00:01.00>w1 <00:01.50>w2')!.single.text,
        'w1 w2',
      );
    });

    test('blank line keeps empty text', () {
      final l = parseLrc('[00:03.00]')!;
      expect(l.single.text, '');
    });

    test('text is trimmed', () {
      expect(parseLrc('[00:03.00]   hi  \r')!.single.text, 'hi');
    });

    test('output is sorted by time', () {
      final l = parseLrc('[00:09.00]b\n[00:01.00]a')!;
      expect(l.map((e) => e.text), ['a', 'b']);
    });

    test('no stamps gives null', () {
      expect(parseLrc('just text\nno stamps'), isNull);
    });
  });

  group('toLrc', () {
    test('formats mm:ss.xx per line', () {
      expect(
        toLrc(const [
          LyricLine(Duration(seconds: 62, milliseconds: 340), 'b'),
          LyricLine(Duration(seconds: 5), ''),
        ]),
        '[01:02.34]b\n[00:05.00]',
      );
    });
  });

  group('currentLineIndex', () {
    const lines = [
      LyricLine(Duration(seconds: 5), 'a'),
      LyricLine(Duration(seconds: 10), 'b'),
      LyricLine(Duration(seconds: 15), 'c'),
    ];
    int at(int s) => currentLineIndex(lines, Duration(seconds: s));

    test('finds the last line at or before position', () {
      expect(at(0), -1);
      expect(at(5), 0);
      expect(at(12), 1);
      expect(at(99), 2);
    });

    test('backward seek', () {
      expect(at(12), 1);
      expect(at(6), 0);
    });

    test('empty list', () {
      expect(currentLineIndex(const [], const Duration(seconds: 1)), -1);
    });
  });

  group('search text', () {
    test('searchTitle strips video decorations', () {
      expect(searchTitle('Song (Official Video)'), 'Song');
      expect(searchTitle('Song [Official Music Video]'), 'Song');
      expect(searchTitle('Song (Lyric Video)'), 'Song');
      expect(searchTitle('Song (Official Audio)'), 'Song');
    });

    test('searchTitle keeps feat.', () {
      expect(searchTitle('Song (feat. X)'), 'Song (feat. X)');
    });

    test('searchArtist', () {
      expect(searchArtist('Name - Topic'), 'Name');
      expect(searchArtist('NameVEVO'), 'Name');
      expect(searchArtist('Plain Name'), 'Plain Name');
    });
  });
}
