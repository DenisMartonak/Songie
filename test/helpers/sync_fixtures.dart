import 'package:drift/drift.dart';
import 'package:songies/data/database.dart';
import 'package:songies/sync/change_feed.dart';

/// Every synced row in [db] as `'<wire>/<id>'` to content hash, for
/// comparing two databases.
Future<Map<String, String>> snapshot(AppDatabase db) async {
  final page = await ChangeFeed(db).since(0, limit: 1 << 30);
  return {for (final r in page.rows) '${r.table.wire}/${r.id}': r.contentHash};
}

/// Inserts one row into each synced table, with local seqs
/// [firstSeq]..[firstSeq]+7 in the order of `SyncTable.values`.
Future<void> seedOneOfEach(AppDatabase db, {int firstSeq = 1}) async {
  var s = firstSeq;
  String clock() => '0000000000001-00000-dev';
  final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  await db
      .into(db.tracks)
      .insert(
        TracksCompanion.insert(
          id: 't$s',
          clock: clock(),
          originDevice: 'dev',
          localSeq: s++,
          source: 'local',
          title: 'T',
          artist: 'A',
          searchText: 't a',
        ),
      );
  await db
      .into(db.playlists)
      .insert(
        PlaylistsCompanion.insert(
          id: 'p$s',
          clock: clock(),
          originDevice: 'dev',
          localSeq: s++,
          name: 'P',
          source: 'local',
          lastYtSyncAt: Value(at),
        ),
      );
  await db
      .into(db.playlistEntries)
      .insert(
        PlaylistEntriesCompanion.insert(
          id: 'e$s',
          clock: clock(),
          originDevice: 'dev',
          localSeq: s++,
          playlistId: 'p',
          trackId: 't',
          position: 'a0',
          addedAt: at,
        ),
      );
  await db
      .into(db.ytSeen)
      .insert(
        YtSeenCompanion.insert(
          id: 'y$s',
          clock: clock(),
          originDevice: 'dev',
          localSeq: s++,
          playlistId: 'p',
          videoId: 'v',
        ),
      );
  await db
      .into(db.themes)
      .insert(
        ThemesCompanion.insert(
          id: 'th$s',
          clock: clock(),
          originDevice: 'dev',
          localSeq: s++,
          name: 'N',
          specJson: '{}',
        ),
      );
  await db
      .into(db.fonts)
      .insert(
        FontsCompanion.insert(
          id: 'f$s',
          clock: clock(),
          originDevice: 'dev',
          localSeq: s++,
          family: 'F',
          fileHash: 'h',
          ext: 'ttf',
        ),
      );
  await db
      .into(db.lyrics)
      .insert(
        LyricsCompanion.insert(
          id: 'l$s',
          clock: clock(),
          originDevice: 'dev',
          localSeq: s++,
          kind: 'plain',
          body: 'b',
          fetchedAt: at,
        ),
      );
  await db
      .into(db.listens)
      .insert(
        ListensCompanion.insert(
          id: 'li$s',
          clock: clock(),
          originDevice: 'dev',
          localSeq: s++,
          trackId: 't',
          startedAt: at,
          heardMs: 1,
          counted: true,
          mainArtist: 'A',
          titleSnapshot: 'T',
          artistSnapshot: 'A',
        ),
      );
}
