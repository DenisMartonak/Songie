import 'package:flutter_test/flutter_test.dart';
import 'package:songies/friends/friends_backend.dart';
import 'package:songies/playlists/sharing_backend.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_sharing_backend.dart';

void main() {
  const halo = RoomSong(videoId: 'v1', title: 'Halo', artist: 'Beyonce');

  test('calls map to their functions and parameters', () async {
    final calls = <(String, Map<String, Object?>)>[];
    Object? answer;
    final b = SupabaseSharingBackend.withRpc((fn, params) async {
      calls.add((fn, params));
      return answer;
    });
    answer = 'ABCDEFGH2345';
    expect(await b.share('Gym', const [halo]), 'ABCDEFGH2345');
    expect(calls.last.$1, 'share_playlist');
    expect(calls.last.$2, {
      'p_name': 'Gym',
      'p_songs': [halo.toJson()],
    });
    answer = null;
    await b.update('ABCDEFGH2345', 'Gym 2', const []);
    expect(calls.last.$1, 'update_shared_playlist');
    expect(calls.last.$2, {
      'p_code': 'ABCDEFGH2345',
      'p_name': 'Gym 2',
      'p_songs': <Object?>[],
    });
    await b.stop('ABCDEFGH2345');
    expect(calls.last.$1, 'stop_sharing_playlist');
    expect(calls.last.$2, {'p_code': 'ABCDEFGH2345'});
  });

  test('get parses the songs, and an empty result is gone', () async {
    Object? answer = [
      {
        'name': 'Gym',
        'owner_name': 'den',
        'songs': [halo.toJson(), 'junk'],
        'updated_at': '2026-11-13T12:00:00Z',
        'is_mine': false,
      },
    ];
    final b = SupabaseSharingBackend.withRpc((fn, params) async => answer);
    final got = (await b.get('ABCDEFGH2345'))!;
    expect(got.name, 'Gym');
    expect(got.ownerName, 'den');
    expect(got.songs.single.videoId, 'v1');
    expect(got.updatedAt, DateTime.utc(2026, 11, 13, 12));
    expect(got.isMine, isFalse);
    answer = <Object?>[];
    expect(await b.get('ABCDEFGH2345'), isNull);
  });

  test('server errors map', () async {
    final b = SupabaseSharingBackend.withRpc(
      (fn, params) async =>
          throw const PostgrestException(message: 'not_owner'),
    );
    await expectLater(
      b.stop('ABCDEFGH2345'),
      throwsA(
        isA<FriendsException>().having(
          (e) => e.error,
          'error',
          FriendsError.notOwner,
        ),
      ),
    );
    final big = SupabaseSharingBackend.withRpc(
      (fn, params) async =>
          throw const PostgrestException(message: 'too_large'),
    );
    await expectLater(
      big.share('x', const []),
      throwsA(
        isA<FriendsException>().having(
          (e) => e.error,
          'error',
          FriendsError.tooLarge,
        ),
      ),
    );
  });

  test('the fake keeps shares to their owner', () async {
    final f = FakeSharingBackend()..me = 'a';
    final code = await f.share('Gym', const [halo]);
    f.me = 'b';
    expect((await f.get(code))!.isMine, isFalse);
    await expectLater(f.stop(code), throwsA(isA<FriendsException>()));
    f.me = 'a';
    await f.stop(code);
    expect(await f.get(code), isNull);
  });
}
