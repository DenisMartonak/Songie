import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'friends_backend.dart' show FriendsRpc, guardFriendsCall;
import 'stats_summary.dart';

/// A song as friends see it: title, artist and, for a YouTube song, its
/// video id (its cover comes from it).
@immutable
class NowPlaying {
  const NowPlaying({required this.title, required this.artist, this.videoId});

  final String title;
  final String artist;
  final String? videoId;

  /// The cover for a YouTube song; null for any other.
  String? get coverUrl =>
      videoId == null ? null : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  Map<String, Object?> toJson() => {
    'title': title,
    'artist': artist,
    'videoId': ?videoId,
  };

  static NowPlaying? fromJson(Object? j) {
    if (j is! Map) return null;
    final title = j['title'];
    final artist = j['artist'];
    final videoId = j['videoId'];
    if (title is! String || artist is! String) return null;
    return NowPlaying(
      title: title,
      artist: artist,
      videoId: videoId is String ? videoId : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NowPlaying &&
      other.title == title &&
      other.artist == artist &&
      other.videoId == videoId;

  @override
  int get hashCode => Object.hash(title, artist, videoId);
}

/// What a friend shares: what they play now (and since when), the room they
/// host, and their stats. Each part is null when not shared.
@immutable
class FriendActivity {
  const FriendActivity({
    this.nowPlaying,
    this.nowUpdatedAt,
    this.roomCode,
    this.stats,
    this.sharesStats = true,
  });

  /// Older than this, a "now playing" is not believed (the app may have
  /// closed without clearing it).
  static const Duration fresh = Duration(minutes: 15);

  final NowPlaying? nowPlaying;
  final DateTime? nowUpdatedAt;
  final String? roomCode;
  final StatsSummary? stats;

  /// Whether they share their stats (false: their stats are private, not
  /// just not published yet).
  final bool sharesStats;

  bool listeningAt(DateTime now) {
    final at = nowUpdatedAt;
    return nowPlaying != null && at != null && now.difference(at) <= fresh;
  }
}

/// The account's two sharing switches.
@immutable
class Sharing {
  const Sharing({required this.listening, required this.top});

  static const on = Sharing(listening: true, top: true);

  final bool listening;
  final bool top;

  @override
  bool operator ==(Object other) =>
      other is Sharing && other.listening == listening && other.top == top;

  @override
  int get hashCode => Object.hash(listening, top);
}

/// The activity rows on the server
/// (`supabase/migrations/20261115120000_friend_activity.sql`).
abstract interface class ActivityBackend {
  Future<Sharing> mySharing();

  /// Sets the switches given; one left null stays as the server has it (so
  /// a stale view can't turn back on what another device turned off).
  Future<void> setSharing({bool? listening, bool? top});

  /// What this account plays now (null: nothing) and the room it hosts.
  Future<void> publishNowPlaying(NowPlaying? now, {String? roomCode});
  Future<void> publishTop(StatsSummary summary);

  /// Each friend's shared activity, by user id.
  Future<Map<String, FriendActivity>> friendActivity();
}

class SupabaseActivityBackend implements ActivityBackend {
  /// [client] is read only when a call is made.
  SupabaseActivityBackend(SupabaseClient Function() client)
    : _rpc = ((fn, params) => client().rpc<dynamic>(fn, params: params));

  @visibleForTesting
  SupabaseActivityBackend.withRpc(this._rpc);

  final FriendsRpc _rpc;

  @override
  Future<Sharing> mySharing() => guardFriendsCall(() async {
    final rows = await _rpc('my_sharing', {}) as List<dynamic>;
    if (rows.isEmpty) return Sharing.on;
    final r = rows.first as Map;
    return Sharing(
      listening: r['share_listening'] != false,
      top: r['share_top'] != false,
    );
  });

  @override
  Future<void> setSharing({bool? listening, bool? top}) => guardFriendsCall(
    () => _rpc('set_sharing', {'p_listening': listening, 'p_top': top}),
  );

  @override
  Future<void> publishNowPlaying(NowPlaying? now, {String? roomCode}) =>
      guardFriendsCall(
        () => _rpc('publish_now_playing', {
          'p_now': now?.toJson(),
          'p_room_code': roomCode,
        }),
      );

  @override
  Future<void> publishTop(StatsSummary summary) =>
      guardFriendsCall(() => _rpc('publish_top', {'p_top': summary.toJson()}));

  @override
  Future<Map<String, FriendActivity>> friendActivity() =>
      guardFriendsCall(() async {
        final rows = await _rpc('friend_activity', {}) as List<dynamic>;
        return {
          for (final row in rows.cast<Map<dynamic, dynamic>>())
            if (row['user_id'] is String)
              row['user_id'] as String: FriendActivity(
                nowPlaying: NowPlaying.fromJson(row['now_playing']),
                nowUpdatedAt: DateTime.tryParse(
                  row['now_updated_at'] as String? ?? '',
                ),
                roomCode: row['room_code'] as String?,
                stats: StatsSummary.fromJson(row['top']),
                sharesStats: row['share_top'] != false,
              ),
        };
      });
}
