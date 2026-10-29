import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lrc.dart';
import 'lyrics.dart';
import 'lyrics_sources.dart';

typedef HttpGet = Future<({int status, String body})> Function(
  Uri uri,
  Map<String, String> headers,
);

/// Plain `HttpClient` GET with a 10 s overall timeout.
Future<({int status, String body})> ioHttpGet(
  Uri uri,
  Map<String, String> headers,
) async {
  final client = HttpClient();
  try {
    return await () async {
      final req = await client.getUrl(uri);
      headers.forEach(req.headers.set);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return (status: res.statusCode, body: body);
    }().timeout(const Duration(seconds: 10));
  } finally {
    client.close(force: true);
  }
}

/// LRCLIB lyrics: an exact lookup by metadata, and a looser search.
class LrclibSource {
  LrclibSource(this._get, {required String userAgent})
    : _headers = {'User-Agent': userAgent};

  final HttpGet _get;
  final Map<String, String> _headers;

  static const _host = 'lrclib.net';
  static const _toleranceSec = 2;

  Future<SourceAnswer> exact(LyricsQuery q) async {
    final duration = q.durationSec;
    if (duration == null) return const Nothing();
    try {
      final uri = Uri.https(_host, '/api/get', {
        'artist_name': q.artist,
        'track_name': q.title,
        if (q.album != null) 'album_name': q.album!,
        'duration': '$duration',
      });
      final res = await _get(uri, _headers);
      if (res.status == 404) return const Nothing();
      if (res.status != 200) return Failed('LRCLIB status ${res.status}');
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (!_withinWindow(json, duration)) return const Nothing();
      return _answer(_lyricsOf(json));
    } catch (e) {
      return Failed(e);
    }
  }

  Future<SourceAnswer> search(LyricsQuery q) async {
    try {
      final uri = Uri.https(_host, '/api/search', {
        'track_name': q.title,
        'artist_name': q.artist,
      });
      final res = await _get(uri, _headers);
      if (res.status != 200) return Failed('LRCLIB status ${res.status}');
      final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      final duration = q.durationSec;
      final candidates = [
        for (final r in list)
          if (duration == null || _withinWindow(r, duration)) _lyricsOf(r),
      ];
      return _answer(
        candidates.firstWhere(
          (l) => l.kind == LyricsKind.synced,
          orElse: () => candidates.firstWhere(
            (l) => l.kind == LyricsKind.plain,
            orElse: () =>
                const TrackLyrics(kind: LyricsKind.none, source: null),
          ),
        ),
      );
    } catch (e) {
      return Failed(e);
    }
  }

  bool _withinWindow(Map<String, dynamic> json, int durationSec) {
    final d = json['duration'];
    if (d is! num) return false;
    return (d.round() - durationSec).abs() <= _toleranceSec;
  }

  /// Synced when the lyrics parse to at least two non-blank lines (a lone
  /// stub does not count), else plain, else none.
  TrackLyrics _lyricsOf(Map<String, dynamic> json) {
    if (json['instrumental'] == true) {
      return const TrackLyrics(kind: LyricsKind.none, source: null);
    }
    final synced = json['syncedLyrics'];
    if (synced is String) {
      final lines = parseLrc(synced);
      if (lines != null &&
          lines.where((l) => l.text.trim().isNotEmpty).length >= 2) {
        return TrackLyrics(
          kind: LyricsKind.synced,
          source: LyricsSource.lrclib,
          lines: lines,
        );
      }
    }
    final plain = json['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) {
      return TrackLyrics(
        kind: LyricsKind.plain,
        source: LyricsSource.lrclib,
        text: plain,
      );
    }
    return const TrackLyrics(kind: LyricsKind.none, source: null);
  }

  SourceAnswer _answer(TrackLyrics l) =>
      l.kind == LyricsKind.none ? const Nothing() : Found(l);
}
