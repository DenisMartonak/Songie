import 'package:flutter_test/flutter_test.dart';
import 'package:songies/lyrics/lyrics.dart';

void main() {
  TrackLyrics roundTrip(TrackLyrics l) {
    final s = l.toStored();
    return TrackLyrics.fromStored(s.kind, s.body, l.source?.name);
  }

  test('synced with credit round trips', () {
    const l = TrackLyrics(
      kind: LyricsKind.synced,
      source: LyricsSource.lrclib,
      lines: [
        LyricLine(Duration(seconds: 1), 'one'),
        LyricLine(Duration(seconds: 2, milliseconds: 500), ''),
      ],
      credit: 'Someone',
    );
    expect(l.toStored().kind, 'synced');
    expect(l.toStored().body, endsWith('[by:Someone]'));
    expect(roundTrip(l), l);
  });

  test('plain with credit round trips', () {
    const l = TrackLyrics(
      kind: LyricsKind.plain,
      source: LyricsSource.youtube,
      text: 'a\nb',
      credit: 'Source: Nobody',
    );
    expect(l.toStored().body, 'a\nb\n\uE001credit:Source: Nobody');
    expect(l.toStored().body, isNot(contains('\u0000')));
    expect(roundTrip(l), l);
  });

  test('plain lyrics stored with the old NUL credit marker still read', () {
    final l = TrackLyrics.fromStored(
      'plain',
      'a\nb\n\u0000credit:Source: Nobody',
      'youtube',
    );
    expect(l.text, 'a\nb');
    expect(l.credit, 'Source: Nobody');
    expect(TrackLyrics.fromStored('plain', '\u0000credit:X', null).text, '');
  });

  test('upgradeCreditMarker swaps the old marker for the new one', () {
    expect(upgradeCreditMarker('a\n\u0000credit:Me'), 'a\n\uE001credit:Me');
    expect(upgradeCreditMarker('\u0000credit:Me'), '\uE001credit:Me');
    expect(upgradeCreditMarker('no marker'), isNull);
  });

  test('plain without credit round trips', () {
    const l = TrackLyrics(
      kind: LyricsKind.plain,
      source: LyricsSource.file,
      text: 'a\nb',
    );
    expect(roundTrip(l), l);
  });

  test('none round trips', () {
    const l = TrackLyrics(kind: LyricsKind.none, source: null);
    expect(l.toStored(), (kind: 'none', body: ''));
    expect(roundTrip(l), l);
  });

  test('equality distinguishes content', () {
    const a = TrackLyrics(
      kind: LyricsKind.synced,
      source: LyricsSource.file,
      lines: [LyricLine(Duration(seconds: 1), 'x')],
    );
    const b = TrackLyrics(
      kind: LyricsKind.synced,
      source: LyricsSource.file,
      lines: [LyricLine(Duration(seconds: 1), 'y')],
    );
    expect(a == b, isFalse);
    expect(a.hashCode == a.hashCode, isTrue);
  });
}
