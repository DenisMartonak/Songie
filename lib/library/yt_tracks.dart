import 'package:drift/drift.dart';

import '../core/log.dart';
import '../core/result.dart';
import '../core/text_normalize.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';
import '../innertube/ytm_models.dart';
import '../youtube/thumbnail_fetcher.dart';
import '../youtube/yt_json.dart';

/// Turns YouTube Music results into normal, stamped `tracks` rows
/// (`source 'yt'`) so they can be played, queued and added to playlists. A row
/// made here is in no playlist, so library lists do not show it until the user
/// adds it; recents and history do.
class YtTrackStore {
  YtTrackStore(this._db, this._stamp, this._thumbs);

  final AppDatabase _db;
  final SyncStamp _stamp;
  final ThumbnailFetcher _thumbs;

  Future<void> _coversPass = Future.value();

  /// Completes when the most recently queued cover fetch has finished.
  Future<void> get coversSettled => _coversPass;

  /// The row for [s]: created if its video is unknown (or revived if it was
  /// deleted), else the existing row after a fill-only upgrade. Never throws.
  Future<Result<Track>> upsert(YtmSong s) async {
    try {
      final r = await guardDb<Track>(_db, () async {
        final old = await (_db.select(
          _db.tracks,
        )..where((t) => t.ytVideoId.equals(s.videoId))).getSingleOrNull();
        if (old == null) {
          final st = await _stamp.next();
          final row = TracksCompanion.insert(
            id: st.id,
            clock: st.clock,
            originDevice: st.originDevice,
            localSeq: st.localSeq,
            source: 'yt',
            ytVideoId: Value(s.videoId),
            title: s.title,
            artist: s.artistLine,
            album: Value(_nonEmpty(s.album)),
            durationMs: Value(s.durationMs ?? 0),
            searchText: normalizeForSearch('${s.title} ${s.artistLine}'),
          );
          await _db.into(_db.tracks).insert(row);
          return Ok(await _byId(st.id));
        }
        if (old.deleted) {
          final st = await _stamp.next();
          await (_db.update(
            _db.tracks,
          )..where((t) => t.id.equals(old.id))).write(
            TracksCompanion(
              deleted: const Value(false),
              source: const Value('yt'),
              title: Value(s.title),
              artist: Value(s.artistLine),
              album: Value(_nonEmpty(s.album)),
              durationMs: Value(s.durationMs ?? 0),
              searchText: Value(
                normalizeForSearch('${s.title} ${s.artistLine}'),
              ),
              clock: Value(st.clock),
              originDevice: Value(st.originDevice),
              localSeq: Value(st.localSeq),
            ),
          );
          return Ok(await _byId(old.id));
        }
        await _fill(old, s);
        return Ok(await _byId(old.id));
      });
      if (r case Ok(:final value)) _queueCover(value, s);
      return r;
    } catch (e, st) {
      AppLog.w('YtTrackStore.upsert failed', e, st);
      return Err(Failure(FailureKind.unknown, '$e', cause: e));
    }
  }

  /// [upsert] for each song; songs that fail are left out.
  Future<List<Track>> upsertAll(List<YtmSong> s) async {
    final out = <Track>[];
    for (final song in s) {
      if (await upsert(song) case Ok(:final value)) out.add(value);
    }
    return out;
  }

  /// Fills what [t] lacks from the richer [rich], as one stamped write; nothing
  /// is written (and no stamp issued) when nothing would change. Never throws.
  Future<void> upgradeFrom(Track t, YtmSong rich) async {
    try {
      await guardDb<void>(_db, () async {
        final cur = await _byId(t.id);
        await _fill(cur, rich);
        return const Ok(null);
      });
      final cur = await _byIdOrNull(t.id);
      if (cur != null) _queueCover(cur, rich);
    } catch (e, st) {
      AppLog.w('YtTrackStore.upgradeFrom failed', e, st);
    }
  }

  /// Fill-only rule. The title and duration are filled when empty. The artist
  /// of an import is the uploader's channel name, which is not stored apart,
  /// so a row that was never enriched (no album: imports and streams never set
  /// one) counts as carrying the channel name and takes the song's artists;
  /// a row with an album keeps its artist unless it is empty. The album is
  /// filled when empty.
  Future<void> _fill(Track t, YtmSong s) async {
    final line = s.artistLine.trim();
    final album = _nonEmpty(s.album);
    final unenriched = _nonEmpty(t.album) == null;
    final newTitle = t.title.trim().isEmpty && s.title.isNotEmpty
        ? s.title
        : null;
    final newArtist =
        line.isNotEmpty &&
            line != t.artist &&
            (t.artist.trim().isEmpty || unenriched)
        ? line
        : null;
    final newAlbum = unenriched && album != null ? album : null;
    final dur = s.durationMs ?? 0;
    final newDuration = t.durationMs <= 0 && dur > 0 ? dur : null;
    if (newTitle == null &&
        newArtist == null &&
        newAlbum == null &&
        newDuration == null) {
      return;
    }
    final st = await _stamp.next();
    await (_db.update(_db.tracks)..where((r) => r.id.equals(t.id))).write(
      TracksCompanion(
        title: Value.absentIfNull(newTitle),
        artist: Value.absentIfNull(newArtist),
        album: Value.absentIfNull(newAlbum),
        durationMs: Value.absentIfNull(newDuration),
        searchText: newTitle != null || newArtist != null
            ? Value(
                normalizeForSearch(
                  '${newTitle ?? t.title} ${newArtist ?? t.artist}',
                ),
              )
            : const Value.absent(),
        clock: Value(st.clock),
        originDevice: Value(st.originDevice),
        localSeq: Value(st.localSeq),
      ),
    );
  }

  /// Fire-and-forget cover fetch through the shared thumbnail path; the sharp
  /// `yt2-` art is kept once there. Never throws.
  void _queueCover(Track t, YtmSong s) {
    final ref = t.artworkRef;
    if (t.unavailable || (ref != null && ref.startsWith('yt2-'))) return;
    final previous = _coversPass;
    _coversPass = () async {
      await previous;
      try {
        final art = await _thumbs.fetchBest(
          thumbnailCandidates(s.videoId, s.thumbnailUrl),
        );
        if (art == null) return;
        await guardDb<void>(_db, () async {
          final st = await _stamp.next();
          await (_db.update(_db.tracks)..where((r) => r.id.equals(t.id))).write(
            TracksCompanion(
              artworkRef: Value(art),
              clock: Value(st.clock),
              originDevice: Value(st.originDevice),
              localSeq: Value(st.localSeq),
            ),
          );
          return const Ok(null);
        });
      } catch (e, st) {
        AppLog.w('Cover for ${s.videoId} failed', e, st);
      }
    }();
  }

  Future<Track> _byId(String id) =>
      (_db.select(_db.tracks)..where((t) => t.id.equals(id))).getSingle();

  Future<Track?> _byIdOrNull(String id) =>
      (_db.select(_db.tracks)..where((t) => t.id.equals(id))).getSingleOrNull();

  static String? _nonEmpty(String? v) =>
      v == null || v.trim().isEmpty ? null : v;
}
