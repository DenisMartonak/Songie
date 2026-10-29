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
    expect(l.toStored().body, 'a\nb\n\u0000credit:Source: Nobody');
    expect(roundTrip(l), l);
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
