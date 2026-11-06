import 'package:collection/collection.dart';

import 'lrc.dart';

enum LyricsKind { synced, plain, none }

enum LyricsSource { file, lrclib, youtube }

class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LyricLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);
}

/// Starts YouTube's credit line at the end of a stored plain body. A private
/// use character, so no lyrics contain it (and Postgres takes it, unlike NUL).
const _plainCreditPrefix = '\uE001credit:';

/// The marker stored before schema 10; still read.
const _oldPlainCreditPrefix = '\u0000credit:';

/// [body] with the old NUL credit marker swapped for today's, or null when
/// it has none.
String? upgradeCreditMarker(String body) {
  final at = body.lastIndexOf(_oldPlainCreditPrefix);
  if (at < 0 || (at > 0 && body[at - 1] != '\n')) return null;
  return body.replaceRange(
    at,
    at + _oldPlainCreditPrefix.length,
    _plainCreditPrefix,
  );
}

final _byTag = RegExp(r'^\[by:(.*)\]$');

/// Lyrics for one track. [lines] is used for synced, [text] for plain, and
/// [credit] holds YouTube's own credit line.
class TrackLyrics {
  const TrackLyrics({
    required this.kind,
    required this.source,
    this.lines = const [],
    this.text = '',
    this.credit,
  });

  final LyricsKind kind;
  final LyricsSource? source;
  final List<LyricLine> lines;
  final String text;
  final String? credit;

  /// Rebuilds lyrics from their stored form. Unknown kinds, and synced bodies
  /// that no longer parse, degrade to [LyricsKind.none].
  factory TrackLyrics.fromStored(String kind, String body, String? source) {
    final src = LyricsSource.values.asNameMap()[source];
    switch (kind) {
      case 'synced':
        final lines = parseLrc(body);
        if (lines == null) break;
        String? credit;
        for (final raw in body.split('\n')) {
          final m = _byTag.firstMatch(raw.trim());
          if (m != null) credit = m.group(1);
        }
        return TrackLyrics(
          kind: LyricsKind.synced,
          source: src,
          lines: lines,
          credit: credit,
        );
      case 'plain':
        body = upgradeCreditMarker(body) ?? body;
        var text = body;
        String? credit;
        final at = body.lastIndexOf(_plainCreditPrefix);
        if (at >= 0 && (at == 0 || body[at - 1] == '\n')) {
          credit = body.substring(at + _plainCreditPrefix.length);
          text = at == 0 ? '' : body.substring(0, at - 1);
        }
        return TrackLyrics(
          kind: LyricsKind.plain,
          source: src,
          text: text,
          credit: credit,
        );
    }
    return const TrackLyrics(kind: LyricsKind.none, source: null);
  }

  ({String kind, String body}) toStored() {
    switch (kind) {
      case LyricsKind.synced:
        final lrc = toLrc(lines);
        final c = credit;
        return (
          kind: 'synced',
          body: c == null ? lrc : '${lrc.isEmpty ? '' : '$lrc\n'}[by:$c]',
        );
      case LyricsKind.plain:
        final c = credit;
        return (
          kind: 'plain',
          body: c == null ? text : '$text\n$_plainCreditPrefix$c',
        );
      case LyricsKind.none:
        return (kind: 'none', body: '');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TrackLyrics &&
      other.kind == kind &&
      other.source == source &&
      other.text == text &&
      other.credit == credit &&
      const ListEquality<LyricLine>().equals(other.lines, lines);

  @override
  int get hashCode => Object.hash(
    kind,
    source,
    text,
    credit,
    const ListEquality<LyricLine>().hash(lines),
  );
}
