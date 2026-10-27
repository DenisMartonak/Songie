import '../core/result.dart';

class YtEntry {
  const YtEntry({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.thumbnailUrl,
    this.unavailable = false,
  });

  final String videoId;
  final String title;
  final String artist;
  final int durationMs;
  final String? thumbnailUrl;
  final bool unavailable;
}

class YtPlaylist {
  const YtPlaylist({
    required this.id,
    required this.title,
    required this.entries,
  });

  final String id;
  final String title;
  final List<YtEntry> entries;
}

class YtStream {
  const YtStream({
    required this.url,
    this.headers = const {},
    this.expiresAt,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
  });

  final Uri url;
  final Map<String, String> headers;
  final DateTime? expiresAt;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;

  /// Whether any rough metadata came with the stream. Only yt-dlp sets it;
  /// Innertube streams carry none.
  bool get hasMetadata =>
      title != null || artist != null || album != null || durationMs != null;
}

enum YtErrorKind {
  notAPlaylist,
  notFound,
  network,
  extractor,
  missingBinary,

  /// HTTP 429 from YouTube: back off and retry.
  throttled,

  /// The disk is full (ENOSPC).
  diskFull,
  unknown,
}

/// A finished yt-dlp download.
class YtDownload {
  const YtDownload({
    required this.path,
    required this.bytes,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
  });

  final String path;
  final int bytes;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
}

const _prefix = 'ytdlp:';

/// Builds a [Failure] whose message starts with `ytdlp:<kind>:`.
Failure ytFailure(YtErrorKind kind, String detail, {Object? cause}) {
  final fk = switch (kind) {
    YtErrorKind.network || YtErrorKind.throttled => FailureKind.network,
    YtErrorKind.diskFull => FailureKind.io,
    YtErrorKind.notFound || YtErrorKind.notAPlaylist => FailureKind.notFound,
    _ => FailureKind.unknown,
  };
  return Failure(fk, '$_prefix${kind.name}:$detail', cause: cause);
}

/// The yt-dlp error kind encoded in [f], or null for other failures.
YtErrorKind? ytErrorKindOf(Failure f) {
  if (!f.message.startsWith(_prefix)) return null;
  final rest = f.message.substring(_prefix.length);
  final end = rest.indexOf(':');
  final name = end < 0 ? rest : rest.substring(0, end);
  for (final k in YtErrorKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

String ytErrorUserMessage(Failure f) => ytErrorUserMessageFromText(f.message);

/// Like [ytErrorUserMessage] for a bare message string (e.g. a player error).
String ytErrorUserMessageFromText(String message) {
  final kind = ytErrorKindOf(Failure(FailureKind.unknown, message));
  if (kind == null) return message;
  return switch (kind) {
    YtErrorKind.notAPlaylist => "That's a video link — paste a playlist link",
    YtErrorKind.notFound =>
      'Not found on YouTube — it may be private or deleted',
    YtErrorKind.network => "Couldn't reach YouTube — check your connection",
    YtErrorKind.extractor =>
      'YouTube changed something — try Settings → Update yt-dlp',
    YtErrorKind.missingBinary =>
      "yt-dlp isn't installed — install it in Settings",
    YtErrorKind.throttled => 'YouTube is limiting downloads — retrying soon',
    YtErrorKind.diskFull => 'Storage is full — free up space and retry',
    YtErrorKind.unknown => 'Something went wrong with yt-dlp',
  };
}
