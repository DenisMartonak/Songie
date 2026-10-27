import 'package:drift/drift.dart';

import '../core/text_normalize.dart';
import '../data/database.dart';
import 'library_repository.dart';

const _escape = r'\';

/// Reactive local-library search (songs + playlists) and the "add songs"
/// picker list.
///
/// Spec deviation (intentional): a LIKE over the normalized `search_text`
/// column instead of FTS5; fast enough for a personal library and needs no
/// triggers.
class SearchRepository {
  SearchRepository(this._db);

  final AppDatabase _db;

  /// Live tracks whose `search_text` contains every token of [query], ordered
  /// by title. An empty query yields `[]`.
  Stream<List<Track>> searchTracks(String query, {int limit = 50}) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return Stream.value(const []);
    return (_db.select(_db.tracks)
          ..where((t) {
            var match = t.deleted.equals(false) & _inLibrary(t);
            for (final token in tokens) {
              match =
                  match &
                  t.searchText.like(
                    '%${_escapeLike(token)}%',
                    escapeChar: _escape,
                  );
            }
            return match;
          })
          ..orderBy(_titleOrder)
          ..limit(limit))
        .watch();
  }

  /// Live playlists whose normalized name contains every token of [query],
  /// ordered by name. An empty query yields `[]`.
  Stream<List<PlaylistSummary>> searchPlaylists(String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return Stream.value(const []);
    return watchPlaylistSummaries(_db).map((all) {
      return [
        for (final p in all)
          if (_containsAll(normalizeForSearch(p.name), tokens)) p,
      ];
    });
  }

  /// Every live track in the library, ordered by title: local tracks and YouTube
  /// tracks reachable from a playlist (see [_inLibrary]).
  Stream<List<Track>> allTracks() {
    return (_db.select(_db.tracks)
          ..where((t) => t.deleted.equals(false) & _inLibrary(t))
          ..orderBy(_titleOrder))
        .watch();
  }

  /// Local tracks always count. A YouTube track (an imported one, or one played
  /// from search and never added anywhere) counts only while an active entry
  /// of a non-deleted playlist points at it.
  Expression<bool> _inLibrary($TracksTable t) {
    final e = _db.playlistEntries;
    final p = _db.playlists;
    final reachable =
        _db.selectOnly(e).join([innerJoin(p, p.id.equalsExp(e.playlistId))])
          ..addColumns([e.id])
          ..where(
            e.trackId.equalsExp(t.id) &
                e.deleted.equals(false) &
                e.status.equals('active') &
                p.deleted.equals(false),
          );
    return t.source.equals('yt').not() | existsQuery(reachable);
  }

  static final List<OrderingTerm Function($TracksTable)> _titleOrder = [
    (t) => OrderingTerm.asc(t.title.lower()),
    (t) => OrderingTerm.asc(t.id),
  ];

  static List<String> _tokens(String query) {
    final normalized = normalizeForSearch(query);
    return normalized.isEmpty ? const [] : normalized.split(' ');
  }

  static bool _containsAll(String haystack, List<String> tokens) =>
      tokens.every(haystack.contains);

  /// Escapes `%`, `_` and the escape character for `LIKE ... ESCAPE '\'`.
  static String _escapeLike(String token) =>
      token.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '$_escape${m[0]}');
}
