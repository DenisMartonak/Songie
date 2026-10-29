import 'lyrics.dart';

final _stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
final _leadingStamps = RegExp(r'^(?:\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\])+');
final _wordStamp = RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>');
final _offsetTag = RegExp(
  r'^\[offset:\s*([+-]?\d+)\s*\]$',
  caseSensitive: false,
);

Duration _stampTime(RegExpMatch m) {
  final frac = m.group(3);
  // 1-3 digits scale to milliseconds by length: ".5" is 500, ".34" is 340.
  final ms = frac == null ? 0 : int.parse(frac.padRight(3, '0'));
  return Duration(
    minutes: int.parse(m.group(1)!),
    seconds: int.parse(m.group(2)!),
    milliseconds: ms,
  );
}

/// Parses LRC text into lines sorted by time, or null when no line carries a
/// timestamp. A positive `[offset:]` shifts every line earlier.
List<LyricLine>? parseLrc(String text) {
  var offset = Duration.zero;
  final out = <LyricLine>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final off = _offsetTag.firstMatch(line);
    if (off != null) {
      offset = Duration(milliseconds: int.parse(off.group(1)!));
      continue;
    }
    final lead = _leadingStamps.firstMatch(line);
    if (lead == null) continue;
    final body = line.substring(lead.end).replaceAll(_wordStamp, '').trim();
    for (final m in _stamp.allMatches(lead.group(0)!)) {
      out.add(LyricLine(_stampTime(m), body));
    }
  }
  if (out.isEmpty) return null;
  final shifted = [
    for (final l in out)
      LyricLine(l.time > offset ? l.time - offset : Duration.zero, l.text),
  ];
  // Dart's List.sort is not stable; sort on (time, original index).
  final order = List<int>.generate(shifted.length, (i) => i)
    ..sort((a, b) {
      final c = shifted[a].time.compareTo(shifted[b].time);
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final i in order) shifted[i]];
}

String _two(int n) => n.toString().padLeft(2, '0');

/// One `[mm:ss.xx]text` line per lyric line.
String toLrc(List<LyricLine> lines) => lines
    .map((l) {
      final ms = l.time.inMilliseconds;
      return '[${_two(ms ~/ 60000)}:${_two(ms ~/ 1000 % 60)}.'
          '${_two(ms % 1000 ~/ 10)}]${l.text}';
    })
    .join('\n');

/// Index of the last line with `time <= position`, or -1. Binary search.
int currentLineIndex(List<LyricLine> lines, Duration position) {
  var lo = 0, hi = lines.length - 1, best = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time <= position) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best;
}

final _decoration = RegExp(
  r'\s*[\(\[]\s*(?:(?:official|music|lyric|lyrics|video|audio|visuali[sz]er|hd|hq|4k)\s*)+[\)\]]',
  caseSensitive: false,
);

/// Title with video decorations like "(Official Video)" removed. Credits such
/// as "(feat. X)" stay.
String searchTitle(String title) {
  final t = title.replaceAll(_decoration, '').trim();
  return t.isEmpty ? title.trim() : t;
}

final _topic = RegExp(r'\s*-\s*Topic$', caseSensitive: false);
final _vevo = RegExp(r'\s*VEVO$', caseSensitive: false);

/// Artist without YouTube's " - Topic" and "VEVO" channel suffixes.
String searchArtist(String artist) {
  final a = artist.trim().replaceAll(_topic, '').replaceAll(_vevo, '').trim();
  return a.isEmpty ? artist.trim() : a;
}
