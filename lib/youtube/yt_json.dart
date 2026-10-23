import 'dart:convert';

import 'yt_models.dart';

String cleanArtist(String channel) {
  const suffix = ' - Topic';
  final t = channel.trim();
  return t.endsWith(suffix)
      ? t.substring(0, t.length - suffix.length).trim()
      : t;
}

/// Cover urls to try, best first. YouTube serves the large ones for most
/// videos; the flat-playlist thumbnail (at most 336x188) is the last resort.
List<String> thumbnailCandidates(String videoId, String? flatThumbnail) => [
  'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg',
  'https://i.ytimg.com/vi/$videoId/hq720.jpg',
  'https://i.ytimg.com/vi/$videoId/sddefault.jpg',
  ?flatThumbnail,
];

/// Prefers a square thumbnail, else the largest; null when none have a url.
String? pickThumbnail(List thumbnails) {
  Map? best;
  var bestScore = -1;
  var bestSquare = false;
  for (final t in thumbnails) {
    if (t is! Map || t['url'] is! String) continue;
    final w = (t['width'] as num?)?.toInt() ?? 0;
    final h = (t['height'] as num?)?.toInt() ?? 0;
    final square = w > 0 && w == h;
    final score = w * h;
    if (best == null ||
        (square && !bestSquare) ||
        (square == bestSquare && score > bestScore)) {
      best = t;
      bestScore = score;
      bestSquare = square;
    }
  }
  return best?['url'] as String?;
}

YtEntry _entry(Map e) {
  final id = e['id'] as String;
  final title = (e['title'] as String?) ?? '';
  final channel = (e['channel'] as String?) ?? (e['uploader'] as String?);
  final duration = e['duration'] as num?;
  final unavailable =
      title == '[Private video]' ||
      title == '[Deleted video]' ||
      (duration == null && e['channel'] == null);
  final thumbs = e['thumbnails'];
  return YtEntry(
    videoId: id,
    title: title,
    artist: channel == null ? '' : cleanArtist(channel),
    durationMs: duration == null ? 0 : (duration * 1000).round(),
    thumbnailUrl: thumbs is List ? pickThumbnail(thumbs) : null,
    unavailable: unavailable,
  );
}

/// Parses a decoded flat-playlist object. Throws [FormatException] when it
/// has no `entries` list.
YtPlaylist playlistFromMap(Map m) {
  final entries = m['entries'];
  if (entries is! List) throw const FormatException('no entries');
  return YtPlaylist(
    id: (m['id'] as String?) ?? '',
    title: (m['title'] as String?) ?? '',
    entries: [
      for (final e in entries)
        if (e is Map && e['id'] is String) _entry(e),
    ],
  );
}

YtPlaylist parsePlaylistJson(String json) {
  final d = jsonDecode(json);
  if (d is! Map) throw const FormatException('not an object');
  return playlistFromMap(d);
}

YtStream parseStreamJson(String json) {
  final d = jsonDecode(json);
  if (d is! Map) throw const FormatException('not an object');
  final urlStr = d['url'];
  if (urlStr is! String || urlStr.isEmpty) {
    throw const FormatException('no stream url');
  }
  final url = Uri.parse(urlStr);
  final expire = int.tryParse(url.queryParameters['expire'] ?? '');
  final headers = <String, String>{};
  final h = d['http_headers'];
  if (h is Map) {
    h.forEach((k, v) {
      if (v != null) headers['$k'] = '$v';
    });
  }
  final channel = (d['channel'] as String?) ?? (d['uploader'] as String?);
  final duration = d['duration'] as num?;
  return YtStream(
    url: url,
    headers: headers,
    expiresAt: expire == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true),
    title: d['title'] as String?,
    artist: channel == null ? null : cleanArtist(channel),
    album: d['album'] as String?,
    durationMs: duration == null ? null : (duration * 1000).round(),
  );
}
