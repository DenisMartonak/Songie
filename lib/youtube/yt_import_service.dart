import 'package:drift/drift.dart';

import '../core/fractional_index.dart';
import '../core/log.dart';
import '../core/result.dart';
import '../core/text_normalize.dart';
import '../data/database.dart';
import '../data/db_guard.dart';
import '../data/sync_stamp.dart';
import '../library/library_repository.dart';
import 'thumbnail_fetcher.dart';
import 'yt_json.dart';
import 'yt_links.dart';
import 'yt_models.dart';
import 'ytdlp_client.dart';

class ImportResult {
  const ImportResult({
    required this.playlistId,
    required this.alreadyExisted,
    required this.added,
  });

  final String playlistId;
  final bool alreadyExisted;

  /// Number of entries created.
  final int added;
}

class SyncResult {
  const SyncResult({
    required this.added,
    required this.flaggedRemoved,
    required this.restored,
    required this.addedTrackIds,
  });

  final int added;
  final int flaggedRemoved;
  final int restored;

  /// Track ids of the newly appended entries, in append order.
  final List<String> addedTrackIds;
}

const _chunk = 500;

/// (track id, video id, flat-playlist thumbnail url) of a cover to fetch.
typedef _ArtJob = (String, String, String?);

/// Imports a YouTube playlist into the library and syncs it later (spec
/// 6.1-6.2). All database writes of one import/sync run in a single
/// transaction using bulk batches; each row still gets its own stamp.
class YtImportService {
  YtImportService(this._db, this._stamp, this._client, this._thumbs)
    : _repo = LibraryRepository(_db, _stamp);

  final AppDatabase _db;
  final SyncStamp _stamp;
  final YtDlpClient _client;
  final ThumbnailFetcher _thumbs;
  final LibraryRepository _repo;

  Future<Result<ImportResult>> importPlaylist(String input) async {
    final url = parsePlaylistLink(input);
    if (url == null) {
      return const Err(
        Failure(FailureKind.invalidInput, 'Not a YouTube playlist link'),
      );
    }
    final existing = await _repo.findPlaylistByYtUrl(url);
    if (existing != null) {
      return Ok(
        ImportResult(playlistId: existing.id, alreadyExisted: true, added: 0),
      );
    }
    final fetched = await _client.fetchPlaylist(url);
    if (fetched is Err<YtPlaylist>) return Err(fetched.failure);
    final list = (fetched as Ok<YtPlaylist>).value;
    final entries = _dedupe(list.entries);

    String? raced;
    final written = await guardDb<_Written>(_db, () async {
      // Re-check: the fetch above can take minutes and another import of the
      // same link may have finished meanwhile.
      final again = await _repo.findPlaylistByYtUrl(url);
      if (again != null) {
        raced = again.id;
        return Ok(_Written(again.id, const [], const []));
      }
      final ps = await _stamp.next();
      await _db
          .into(_db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: ps.id,
              clock: ps.clock,
              originDevice: ps.originDevice,
              localSeq: ps.localSeq,
              name: list.title.trim().isEmpty
                  ? 'YouTube playlist'
                  : list.title.trim(),
              source: 'yt',
              ytPlaylistUrl: Value(url),
              lastYtSyncAt: Value(DateTime.now()),
            ),
          );
      return Ok(await _append(ps.id, entries, null));
    });
    if (written is Err<_Written>) return Err(written.failure);
    final w = (written as Ok<_Written>).value;
    if (raced != null) {
      return Ok(
        ImportResult(playlistId: raced!, alreadyExisted: true, added: 0),
      );
    }
    _startThumbnails(w.needArt);
    return Ok(
      ImportResult(
        playlistId: w.playlistId,
        alreadyExisted: false,
        added: w.trackIds.length,
      ),
    );
  }

  Future<Result<SyncResult>> syncPlaylist(String playlistId) async {
    final playlist =
        await (_db.select(_db.playlists)
              ..where((p) => p.id.equals(playlistId) & p.deleted.equals(false)))
            .getSingleOrNull();
    if (playlist == null) {
      return Err(Failure(FailureKind.notFound, 'No such playlist $playlistId'));
    }
    final url = playlist.ytPlaylistUrl;
    if (playlist.source != 'yt' || url == null) {
      return const Err(
        Failure(FailureKind.invalidInput, 'Not a YouTube playlist'),
      );
    }
    final fetched = await _client.fetchPlaylist(url);
    if (fetched is Err<YtPlaylist>) return Err(fetched.failure);
    final entries = _dedupe((fetched as Ok<YtPlaylist>).value.entries);
    final fetchedById = {for (final e in entries) e.videoId: e};

    var flagged = 0;
    var restored = 0;
    final written = await guardDb<_Written>(_db, () async {
      final seenRows = await (_db.select(
        _db.ytSeen,
      )..where((s) => s.playlistId.equals(playlistId))).get();
      final seen = {for (final s in seenRows) s.videoId};

      final live =
          await (_db.select(_db.playlistEntries).join([
                innerJoin(
                  _db.tracks,
                  _db.tracks.id.equalsExp(_db.playlistEntries.trackId),
                ),
              ])..where(
                _db.playlistEntries.playlistId.equals(playlistId) &
                    _db.playlistEntries.deleted.equals(false),
              ))
              .get();
      String? last;
      final gone = <String>[];
      final back = <String>[];
      final upgrade = <_ArtJob>[];
      // Track id -> new `unavailable` value, for tracks whose flag changed.
      final flips = <String, bool>{};
      for (final r in live) {
        final e = r.readTable(_db.playlistEntries);
        final t = r.readTable(_db.tracks);
        if (last == null || e.position.compareTo(last) > 0) last = e.position;
        final vid = t.ytVideoId;
        if (vid == null) continue;
        final f = fetchedById[vid];
        if (f != null && f.unavailable != t.unavailable) {
          flips[t.id] = f.unavailable;
        }
        if (!_hasSharpArt(t.artworkRef) && !(f?.unavailable ?? t.unavailable)) {
          upgrade.add((t.id, vid, f?.thumbnailUrl));
        }
        // Only ids this playlist got from YouTube; tracks the user added from
        // elsewhere are left alone (spec 6.2).
        if (!seen.contains(vid)) continue;
        if (f != null) {
          if (e.status == 'removed_on_yt') back.add(e.id);
        } else if (e.status == 'active' && !e.kept) {
          gone.add(e.id);
        }
      }

      final fresh = [
        for (final e in entries)
          if (!seen.contains(e.videoId)) e,
      ];
      final w = await _append(playlistId, fresh, last);
      await _setStatus(gone, 'removed_on_yt');
      await _setStatus(back, 'active');
      await _setUnavailable(flips);
      flagged = gone.length;
      restored = back.length;
      w.needArt.addAll(upgrade);

      final ps = await _stamp.next(id: playlistId);
      await (_db.update(
        _db.playlists,
      )..where((p) => p.id.equals(playlistId))).write(
        PlaylistsCompanion(
          lastYtSyncAt: Value(DateTime.now()),
          clock: Value(ps.clock),
          originDevice: Value(ps.originDevice),
          localSeq: Value(ps.localSeq),
        ),
      );
      return Ok(w);
    });
    if (written is Err<_Written>) return Err(written.failure);
    final w = (written as Ok<_Written>).value;
    _startThumbnails(w.needArt);
    return Ok(
      SyncResult(
        added: w.trackIds.length,
        flaggedRemoved: flagged,
        restored: restored,
        addedTrackIds: w.trackIds,
      ),
    );
  }

  List<YtEntry> _dedupe(List<YtEntry> all) {
    final ids = <String>{};
    return [
      for (final e in all)
        if (ids.add(e.videoId)) e,
    ];
  }

  /// Upserts tracks (resurrecting tombstones), appends entries after
  /// [lastPosition] and records every id in `yt_seen`. Runs inside the
  /// caller's transaction.
  Future<_Written> _append(
    String playlistId,
    List<YtEntry> entries,
    String? lastPosition,
  ) async {
    final byVideo = <String, Track>{};
    final ids = [for (final e in entries) e.videoId];
    for (var i = 0; i < ids.length; i += _chunk) {
      final part = ids.sublist(
        i,
        i + _chunk > ids.length ? ids.length : i + _chunk,
      );
      final rows = await (_db.select(
        _db.tracks,
      )..where((t) => t.ytVideoId.isIn(part))).get();
      for (final t in rows) {
        byVideo[t.ytVideoId!] = t;
      }
    }

    // Only tracks that are written (new or revived) consume a stamp.
    final writes = [
      for (final e in entries)
        if (byVideo[e.videoId] == null || byVideo[e.videoId]!.deleted) e,
    ];
    final n = entries.length;
    final stamps = await _stamp.nextMany(
      writes.length + 2 * n,
      ids: [
        for (final e in writes) byVideo[e.videoId]?.id,
        for (var i = 0; i < 2 * n; i++) null,
      ],
    );
    final newTracks = <TracksCompanion>[];
    final revived = <(String, TracksCompanion)>[];
    final trackIds = <String>[];
    final needArt = <_ArtJob>[];
    var w = 0;
    for (final e in entries) {
      final old = byVideo[e.videoId];
      final isWrite = old == null || old.deleted;
      final s = isWrite ? stamps[w++] : null;
      final trackId = old?.id ?? s!.id;
      trackIds.add(trackId);
      // Unavailable entries only carry YouTube's no_thumbnail placeholder.
      if (!_hasSharpArt(old?.artworkRef) && !e.unavailable) {
        needArt.add((trackId, e.videoId, e.thumbnailUrl));
      }
      if (old == null) {
        newTracks.add(
          TracksCompanion.insert(
            id: s!.id,
            clock: s.clock,
            originDevice: s.originDevice,
            localSeq: s.localSeq,
            source: 'yt',
            ytVideoId: Value(e.videoId),
            title: e.title,
            artist: e.artist,
            durationMs: Value(e.durationMs),
            unavailable: Value(e.unavailable),
            searchText: normalizeForSearch('${e.title} ${e.artist}'),
          ),
        );
      } else if (old.deleted) {
        revived.add((
          old.id,
          TracksCompanion(
            deleted: const Value(false),
            source: const Value('yt'),
            title: Value(e.title),
            artist: Value(e.artist),
            durationMs: Value(e.durationMs),
            unavailable: Value(e.unavailable),
            searchText: Value(normalizeForSearch('${e.title} ${e.artist}')),
            clock: Value(s!.clock),
            originDevice: Value(s.originDevice),
            localSeq: Value(s.localSeq),
          ),
        ));
      }
    }

    final positions = nKeysBetween(lastPosition, null, n);
    final now = DateTime.now();
    final entryRows = <PlaylistEntriesCompanion>[];
    final seenRows = <YtSeenCompanion>[];
    for (var i = 0; i < n; i++) {
      final es = stamps[writes.length + i];
      entryRows.add(
        PlaylistEntriesCompanion.insert(
          id: es.id,
          clock: es.clock,
          originDevice: es.originDevice,
          localSeq: es.localSeq,
          playlistId: playlistId,
          trackId: trackIds[i],
          position: positions[i],
          addedAt: now,
        ),
      );
      final ss = stamps[writes.length + n + i];
      seenRows.add(
        YtSeenCompanion.insert(
          id: ss.id,
          clock: ss.clock,
          originDevice: ss.originDevice,
          localSeq: ss.localSeq,
          playlistId: playlistId,
          videoId: entries[i].videoId,
        ),
      );
    }

    await _db.batch((b) {
      b.insertAll(_db.tracks, newTracks);
      for (final (id, c) in revived) {
        b.update(_db.tracks, c, where: (t) => t.id.equals(id));
      }
      b.insertAll(_db.playlistEntries, entryRows);
      b.insertAll(_db.ytSeen, seenRows);
    });
    return _Written(playlistId, trackIds, needArt);
  }

  Future<void> _setStatus(List<String> entryIds, String status) async {
    if (entryIds.isEmpty) return;
    final stamps = await _stamp.nextMany(entryIds.length, ids: entryIds);
    await _db.batch((b) {
      for (var i = 0; i < entryIds.length; i++) {
        b.update(
          _db.playlistEntries,
          PlaylistEntriesCompanion(
            status: Value(status),
            clock: Value(stamps[i].clock),
            originDevice: Value(stamps[i].originDevice),
            localSeq: Value(stamps[i].localSeq),
          ),
          where: (e) => e.id.equals(entryIds[i]),
        );
      }
    });
  }

  Future<void> _setUnavailable(Map<String, bool> flips) async {
    if (flips.isEmpty) return;
    final ids = flips.keys.toList();
    final stamps = await _stamp.nextMany(ids.length, ids: ids);
    await _db.batch((b) {
      for (var i = 0; i < ids.length; i++) {
        b.update(
          _db.tracks,
          TracksCompanion(
            unavailable: Value(flips[ids[i]]!),
            clock: Value(stamps[i].clock),
            originDevice: Value(stamps[i].originDevice),
            localSeq: Value(stamps[i].localSeq),
          ),
          where: (t) => t.id.equals(ids[i]),
        );
      }
    });
  }

  Future<void> _thumbsPass = Future.value();

  /// Completes when the most recently started thumbnail pass has finished
  /// (immediately if none is running).
  Future<void> get thumbnailsSettled => _thumbsPass;

  static const _thumbConcurrency = 6;

  /// Queues the YouTube tracks among [tracks] whose art is not yet the sharp
  /// `yt2-` kind (and that are not unavailable) into the background thumbnail
  /// pass. Fire-and-forget; never throws.
  void refreshArtwork(Iterable<Track> tracks) {
    try {
      _startThumbnails([
        for (final t in tracks)
          if (t.ytVideoId != null &&
              !t.unavailable &&
              !_hasSharpArt(t.artworkRef))
            (t.id, t.ytVideoId!, null),
      ]);
    } catch (e, s) {
      AppLog.w('refreshArtwork failed', e, s);
    }
  }

  static bool _hasSharpArt(String? ref) =>
      ref != null && ref.startsWith('yt2-');

  void _startThumbnails(List<_ArtJob> jobs) {
    // One job per track; a later job's flat url replaces an earlier null.
    final byTrack = <String, _ArtJob>{};
    for (final j in jobs) {
      final old = byTrack[j.$1];
      if (old == null || old.$3 == null) byTrack[j.$1] = j;
    }
    final need = byTrack.values.toList();
    if (need.isEmpty) return;
    final previous = _thumbsPass;
    _thumbsPass = () async {
      await previous;
      await _fetchThumbnails(need);
    }();
  }

  /// Best effort, after the main transaction: failures are ignored.
  Future<void> _fetchThumbnails(List<_ArtJob> need) async {
    try {
      final refs = <String, String>{};
      var next = 0;
      Future<void> worker() async {
        while (next < need.length) {
          final (trackId, videoId, flatUrl) = need[next++];
          try {
            final ref = await _thumbs.fetchBest(
              thumbnailCandidates(videoId, flatUrl),
            );
            if (ref != null) refs[trackId] = ref;
          } catch (e, s) {
            // One bad image must not drop the rest of the pass.
            AppLog.w('Thumbnail for $trackId failed', e, s);
          }
        }
      }

      await Future.wait([
        for (var i = 0; i < _thumbConcurrency && i < need.length; i++) worker(),
      ]);
      if (refs.isEmpty) return;
      await guardDb<void>(_db, () async {
        final ids = refs.keys.toList();
        final stamps = await _stamp.nextMany(ids.length, ids: ids);
        await _db.batch((b) {
          for (var i = 0; i < ids.length; i++) {
            b.update(
              _db.tracks,
              TracksCompanion(
                artworkRef: Value(refs[ids[i]]),
                clock: Value(stamps[i].clock),
                originDevice: Value(stamps[i].originDevice),
                localSeq: Value(stamps[i].localSeq),
              ),
              where: (t) => t.id.equals(ids[i]),
            );
          }
        });
        return const Ok(null);
      });
    } catch (e, s) {
      AppLog.w('Saving YouTube thumbnails failed', e, s);
    }
  }
}

class _Written {
  _Written(this.playlistId, this.trackIds, this.needArt);

  final String playlistId;
  final List<String> trackIds;
  final List<_ArtJob> needArt;
}
