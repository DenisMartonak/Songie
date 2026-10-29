import 'dart:async';

import 'package:drift/drift.dart';

import '../core/connectivity.dart';
import '../core/log.dart';
import '../data/database.dart';
import 'file_lyrics.dart';
import 'lrc.dart';
import 'lrclib.dart';
import 'lyrics.dart';
import 'lyrics_sources.dart';
import 'lyrics_store.dart';
import 'ytm_lyrics.dart';

/// What the lyrics view shows for a track.
sealed class LyricsState {
  const LyricsState();
}

final class LyricsLoading extends LyricsState {
  const LyricsLoading();
}

/// Synced or plain lyrics.
final class LyricsShown extends LyricsState {
  const LyricsShown(this.lyrics);

  final TrackLyrics lyrics;
}

/// No lyrics found; the view offers Search again.
final class LyricsNone extends LyricsState {
  const LyricsNone();
}

/// "Lyrics need a connection".
final class LyricsOffline extends LyricsState {
  const LyricsOffline();
}

/// Finds a track's lyrics: its own file first, then the stored result, then
/// LRCLIB (exact, search) and YouTube Music, storing what the online sources
/// found. Only called while a lyrics view is open.
class LyricsService {
  LyricsService({
    required this._db,
    required this._store,
    required this._file,
    required this._lrclib,
    required this._ytm,
    required this._network,
    this._now = DateTime.now,
  });

  final AppDatabase _db;
  final LyricsStore _store;
  final FileLyricsSource _file;
  final LrclibSource _lrclib;
  final YtmLyricsSource _ytm;
  final NetworkStatus _network;
  final DateTime Function() _now;

  static const _noneRetryAfter = Duration(days: 30);

  final Map<String, Future<LyricsState>> _inFlight = {};

  /// The lyrics to show for [t]. A lookup already running for the track is
  /// joined (even with [force]); [force] ignores any stored result. Never
  /// throws.
  Future<LyricsState> lookup(Track t, {bool force = false}) {
    final running = _inFlight[t.id];
    if (running != null) return running;
    final f = _guarded(t, force);
    _inFlight[t.id] = f;
    f.whenComplete(() {
      if (identical(_inFlight[t.id], f)) _inFlight.remove(t.id);
    });
    return f;
  }

  /// Starts a lookup for the song that plays next, so skipping shows lyrics
  /// at once.
  void prefetch(Track? t) {
    if (t != null) unawaited(lookup(t));
  }

  Future<LyricsState> _guarded(Track t, bool force) async {
    try {
      return await _lookup(t, force);
    } catch (e, s) {
      AppLog.w('Lyrics lookup failed for ${t.id}', e, s);
      return const LyricsNone();
    }
  }

  Future<LyricsState> _lookup(Track t, bool force) async {
    // 1. The song's own file, every time; never stored.
    final fileAnswer = await _file.read(await _audioPath(t.id));
    TrackLyrics? filePlain;
    if (fileAnswer is Found) {
      if (fileAnswer.lyrics.kind == LyricsKind.synced) {
        return LyricsShown(fileAnswer.lyrics);
      }
      if (fileAnswer.lyrics.kind == LyricsKind.plain) {
        filePlain = fileAnswer.lyrics;
      }
    }
    LyricsState fileOr(LyricsState otherwise) =>
        filePlain != null ? LyricsShown(filePlain) : otherwise;

    // 2. The stored result.
    if (!force) {
      final stored = await _store.read(t.id);
      if (stored != null) {
        switch (stored.lyrics.kind) {
          case LyricsKind.synced:
            return LyricsShown(stored.lyrics);
          case LyricsKind.plain:
            return fileOr(LyricsShown(stored.lyrics));
          case LyricsKind.none:
            if (_now().difference(stored.fetchedAt) < _noneRetryAfter) {
              return fileOr(const LyricsNone());
            }
        }
      }
    }

    // 3. No artist: a title-only search too easily finds the wrong song.
    final q = _queryOf(t);
    if (q.artist.isEmpty) return fileOr(const LyricsNone());

    // 4. Offline.
    if (await _network.current() == NetworkKind.offline) {
      return fileOr(const LyricsOffline());
    }

    // 5. The online sources in order; the first synced answer stops the run.
    final sources = <Future<SourceAnswer> Function()>[
      () => _lrclib.exact(q),
      () => _lrclib.search(q),
      if (t.source == 'yt') () => _ytm.fetch(t.ytVideoId),
    ];
    TrackLyrics? onlineSynced;
    TrackLyrics? onlinePlain;
    var failures = 0;
    for (final ask in sources) {
      final a = await ask();
      if (a is Failed) {
        failures++;
      } else if (a is Found) {
        if (a.lyrics.kind == LyricsKind.synced) {
          onlineSynced = a.lyrics;
          break;
        }
        if (a.lyrics.kind == LyricsKind.plain) onlinePlain ??= a.lyrics;
      }
    }

    // 6–7. The best answer; the best online one is stored.
    final online = onlineSynced ?? onlinePlain;
    if (online != null) {
      await _store.write(t.id, online, _now());
      return onlineSynced != null
          ? LyricsShown(onlineSynced)
          : fileOr(LyricsShown(online));
    }
    if (failures == sources.length) {
      // Every source failed but the device is online (LRCLIB down, rate
      // limited): no lyrics, with Search again, and nothing stored. Only a
      // connection lost meanwhile is offline.
      return fileOr(
        await _network.current() == NetworkKind.offline
            ? const LyricsOffline()
            : const LyricsNone(),
      );
    }
    if (failures == 0) {
      await _store.write(
        t.id,
        const TrackLyrics(kind: LyricsKind.none, source: null),
        _now(),
      );
    }
    return fileOr(const LyricsNone());
  }

  /// The audio file on this device (a scanned local song or a downloaded
  /// YouTube one), or null.
  Future<String?> _audioPath(String trackId) async {
    final row =
        await (_db.select(
              _db.localFiles,
            )..where((f) => f.trackId.equals(trackId) & f.state.equals('done')))
            .getSingleOrNull();
    final path = row?.path;
    return path == null || path.isEmpty ? null : path;
  }

  static LyricsQuery _queryOf(Track t) {
    final album = t.album;
    return LyricsQuery(
      title: searchTitle(t.title),
      artist: searchArtist(t.artist),
      album: album == null || album.isEmpty ? null : album,
      durationSec: t.durationMs > 0 ? (t.durationMs / 1000).round() : null,
      videoId: t.ytVideoId,
    );
  }
}
