import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../account/supabase_config.dart' show kAvatarBucket;
import '../core/log.dart';

/// A Songies user as friends see them.
@immutable
class FriendUser {
  const FriendUser({required this.id, required this.username, this.avatarUrl});

  final String id;
  final String username;

  /// The picture's public URL; null without one.
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      other is FriendUser &&
      other.id == id &&
      other.username == username &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, username, avatarUrl);
}

/// How someone stands with the signed-in user: friends, or a request they
/// sent (incoming) or the user sent (outgoing).
enum FriendLink { friend, incoming, outgoing }

class FriendRow {
  const FriendRow({required this.user, required this.link});
  final FriendUser user;
  final FriendLink link;
}

/// Why a friends call failed (the server's error, or no connection).
enum FriendsError {
  offline,
  selfRequest,
  unknownUser,
  notRequested,
  notOwner,
  tooLarge,
  other,
}

class FriendsException implements Exception {
  const FriendsException(this.error);
  final FriendsError error;

  @override
  String toString() => 'FriendsException(${error.name})';
}

/// The friendships and profiles on the server
/// (`supabase/migrations/20261114120000_friends.sql`).
abstract interface class FriendsBackend {
  /// Everyone [me] is friends with or has a request with.
  Future<List<FriendRow>> load(String me);

  /// Up to 20 users whose username starts with [query] (any case), never
  /// [me].
  Future<List<FriendUser>> search(String me, String query);

  /// Asks [other] to be friends: [FriendLink.outgoing] for a new request,
  /// [FriendLink.friend] when they had already asked (it is accepted).
  Future<FriendLink?> send(String other);

  /// Accepts [other]'s request.
  Future<void> accept(String other);

  /// Ends whatever there is with [other]: declines, cancels or unfriends.
  Future<void> remove(String other);
}

/// [q] for a `like` pattern: `\`, `%` and `_` match themselves.
String escapeLike(String q) =>
    q.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');

/// The `ilike` pattern for usernames starting with [query], or null when
/// fewer than 2 username characters remain. Only what a username may hold
/// (a-z, 0-9, `_` and `.`) is kept: the server reads `*` as a wildcard too.
String? usernameSearchPattern(String query) {
  final kept = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.]'), '');
  if (kept.length < 2) return null;
  return '${escapeLike(kept)}%';
}

/// Runs [call], turning server and network failures into
/// [FriendsException]s.
Future<T> guardFriendsCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PostgrestException catch (e) {
    throw FriendsException(switch (e.message) {
      final m when m.contains('self_request') => FriendsError.selfRequest,
      final m when m.contains('unknown_user') => FriendsError.unknownUser,
      final m when m.contains('not_requested') => FriendsError.notRequested,
      final m when m.contains('not_owner') => FriendsError.notOwner,
      final m when m.contains('too_large') => FriendsError.tooLarge,
      _ => FriendsError.other,
    });
  } on SocketException {
    throw const FriendsException(FriendsError.offline);
  } on TimeoutException {
    throw const FriendsException(FriendsError.offline);
  } on http.ClientException {
    throw const FriendsException(FriendsError.offline);
  } on AuthRetryableFetchException {
    throw const FriendsException(FriendsError.offline);
  } on TlsException {
    // A Wi-Fi login page or a broken connection.
    throw const FriendsException(FriendsError.offline);
  } on FriendsException {
    rethrow;
  } catch (e) {
    // Anything else (a garbled reply): a failure the UI can show.
    AppLog.w('friends: call failed (${e.runtimeType})');
    throw const FriendsException(FriendsError.other);
  }
}

typedef FriendsRpc = Future<Object?> Function(
  String fn,
  Map<String, Object?> params,
);

class SupabaseFriendsBackend implements FriendsBackend {
  /// [client] is read only when a call is made, so a signed-out app never
  /// touches Supabase.
  SupabaseFriendsBackend(SupabaseClient Function() client)
    : _client = client,
      _rpc = ((fn, params) => client().rpc<dynamic>(fn, params: params));

  @visibleForTesting
  SupabaseFriendsBackend.withRpc(this._rpc) : _client = null;

  final SupabaseClient Function()? _client;
  final FriendsRpc _rpc;

  SupabaseClient get _c => _client!();

  FriendUser _user(Map<String, dynamic> row) {
    final path = row['avatar_path'] as String?;
    return FriendUser(
      id: row['id'] as String,
      username: row['username'] as String,
      avatarUrl: path == null
          ? null
          : _c.storage.from(kAvatarBucket).getPublicUrl(path),
    );
  }

  @override
  Future<List<FriendRow>> load(String me) => guardFriendsCall(() async {
    final rows = await _c
        .from('friendships')
        .select('requester, addressee, status');
    final links = <String, FriendLink>{};
    for (final r in rows) {
      final requester = r['requester'] as String;
      final other = requester == me ? r['addressee'] as String : requester;
      links[other] = r['status'] == 'accepted'
          ? FriendLink.friend
          : requester == me
          ? FriendLink.outgoing
          : FriendLink.incoming;
    }
    if (links.isEmpty) return const [];
    final profiles = await _c
        .from('profiles')
        .select('id, username, avatar_path')
        .inFilter('id', links.keys.toList());
    return [
      for (final p in profiles)
        FriendRow(user: _user(p), link: links[p['id']]!),
    ];
  });

  @override
  Future<List<FriendUser>> search(String me, String query) =>
      guardFriendsCall(() async {
        final pattern = usernameSearchPattern(query);
        if (pattern == null) return const [];
        final rows = await _c
            .from('profiles')
            .select('id, username, avatar_path')
            .ilike('username', pattern)
            .neq('id', me)
            .order('username')
            .limit(20);
        return [for (final r in rows) _user(r)];
      });

  @override
  Future<FriendLink?> send(String other) => guardFriendsCall(() async {
    final status = await _rpc('send_friend_request', {'p_other': other});
    return switch (status) {
      'pending' => FriendLink.outgoing,
      'accepted' => FriendLink.friend,
      _ => null,
    };
  });

  @override
  Future<void> accept(String other) =>
      guardFriendsCall(() => _rpc('accept_friend_request', {'p_other': other}));

  @override
  Future<void> remove(String other) =>
      guardFriendsCall(() => _rpc('remove_friend', {'p_other': other}));
}
