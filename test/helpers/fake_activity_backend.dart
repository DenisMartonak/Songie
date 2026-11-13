import 'package:songies/friends/activity_backend.dart';

/// Activity rows in memory, following the server's rules
/// (`supabase/migrations/20261115120000_friend_activity.sql`). [me] is who
/// acts; [friendsOf] says who may see whom.
class FakeActivityBackend implements ActivityBackend {
  FakeActivityBackend({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;
  final _rows = <String, _Row>{};
  final calls = <String>[];
  Object? error;
  String me = '';

  /// Who [id] is friends with.
  Set<String> Function(String id) friendsOf = (_) => const {};

  _Row _row(String id) => _rows.putIfAbsent(id, _Row.new);

  void _check() {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<Sharing> mySharing() async {
    calls.add('mySharing');
    _check();
    final r = _rows[me];
    return Sharing(listening: r?.listening ?? true, top: r?.top ?? true);
  }

  @override
  Future<void> setSharing(Sharing s) async {
    calls.add('setSharing');
    _check();
    final r = _row(me)
      ..listening = s.listening
      ..top = s.top;
    if (!s.listening) {
      r
        ..now = null
        ..nowAt = null
        ..roomCode = null;
    }
    if (!s.top) r.summary = null;
  }

  @override
  Future<void> publishNowPlaying(NowPlaying? now, {String? roomCode}) async {
    calls.add('publishNowPlaying');
    _check();
    final r = _row(me);
    if (!r.listening) return;
    r
      ..now = now
      ..nowAt = this.now()
      ..roomCode = roomCode;
  }

  @override
  Future<void> publishTop(TopSummary top) async {
    calls.add('publishTop');
    _check();
    final r = _row(me);
    if (!r.top) return;
    r.summary = top;
  }

  @override
  Future<Map<String, FriendActivity>> friendActivity() async {
    calls.add('friendActivity');
    _check();
    return {
      for (final id in friendsOf(me))
        if (_rows[id] case final r?)
          id: FriendActivity(
            nowPlaying: r.listening ? r.now : null,
            nowUpdatedAt: r.listening ? r.nowAt : null,
            roomCode: r.listening ? r.roomCode : null,
            top: r.top ? r.summary : null,
          ),
    };
  }

  /// [id]'s row as stored (for tests).
  ({NowPlaying? now, String? roomCode, TopSummary? top})? rowOf(String id) {
    final r = _rows[id];
    if (r == null) return null;
    return (now: r.now, roomCode: r.roomCode, top: r.summary);
  }
}

class _Row {
  bool listening = true;
  bool top = true;
  NowPlaying? now;
  DateTime? nowAt;
  String? roomCode;
  TopSummary? summary;
}
