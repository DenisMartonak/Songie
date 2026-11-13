import 'package:flutter_test/flutter_test.dart';
import 'package:songies/friends/activity_backend.dart';

import '../helpers/fake_activity_backend.dart';

void main() {
  const halo = NowPlaying(title: 'Halo', artist: 'Beyonce', videoId: 'v1');
  const top = TopSummary(
    artists: ['Beyonce', 'Daft Punk'],
    songs: [
      halo,
      NowPlaying(title: 'Local', artist: 'Me'),
    ],
  );

  test('models round-trip and reject bad shapes', () {
    expect(NowPlaying.fromJson(halo.toJson()), halo);
    expect(NowPlaying.fromJson(const {'title': 'x'}), isNull);
    expect(NowPlaying.fromJson('x'), isNull);
    expect(TopSummary.fromJson(top.toJson()), top);
    expect(
      TopSummary.fromJson(const {
        'artists': [
          {'name': 'A'},
          5,
        ],
        'songs': 'x',
      }),
      const TopSummary(artists: ['A'], songs: []),
    );
    expect(TopSummary.fromJson(null), isNull);
    // At most 10 of each.
    final many = TopSummary(
      artists: [for (var i = 0; i < 15; i++) 'a$i'],
      songs: const [],
    );
    expect(TopSummary.fromJson(many.toJson())!.artists, hasLength(10));
  });

  test('listeningAt ignores a status older than 15 minutes', () {
    final at = DateTime(2026, 11, 13, 12);
    final a = FriendActivity(nowPlaying: halo, nowUpdatedAt: at);
    expect(a.listeningAt(at.add(const Duration(minutes: 14))), isTrue);
    expect(a.listeningAt(at.add(const Duration(minutes: 16))), isFalse);
    expect(const FriendActivity().listeningAt(at), isFalse);
  });

  test('calls map to their functions and parameters', () async {
    final calls = <(String, Map<String, Object?>)>[];
    Object? answer;
    final b = SupabaseActivityBackend.withRpc((fn, params) async {
      calls.add((fn, params));
      return answer;
    });
    await b.publishNowPlaying(null);
    expect(calls.last.$1, 'publish_now_playing');
    expect(calls.last.$2, {'p_now': null, 'p_room_code': null});
    await b.publishNowPlaying(halo, roomCode: 'ABCD2345');
    expect(calls.last.$2, {'p_now': halo.toJson(), 'p_room_code': 'ABCD2345'});
    await b.setSharing(const Sharing(listening: false, top: true));
    expect(calls.last.$1, 'set_sharing');
    expect(calls.last.$2, {'p_listening': false, 'p_top': true});
    await b.publishTop(top);
    expect(calls.last.$2, {'p_top': top.toJson()});

    answer = [
      {'share_listening': false, 'share_top': true},
    ];
    expect(await b.mySharing(), const Sharing(listening: false, top: true));
    answer = [
      {
        'user_id': 'u2',
        'now_playing': halo.toJson(),
        'now_updated_at': '2026-11-13T12:00:00Z',
        'room_code': 'ABCD2345',
        'top': null,
      },
    ];
    final got = await b.friendActivity();
    expect(got['u2']!.nowPlaying, halo);
    expect(got['u2']!.roomCode, 'ABCD2345');
    expect(got['u2']!.nowUpdatedAt, DateTime.utc(2026, 11, 13, 12));
    expect(got['u2']!.top, isNull);
  });

  test('the fake hides what is not shared', () async {
    final f = FakeActivityBackend()
      ..friendsOf = (id) => id == 'a' ? {'b'} : {'a'};
    f.me = 'b';
    await f.publishNowPlaying(halo, roomCode: 'ABCD2345');
    await f.publishTop(top);
    f.me = 'a';
    expect((await f.friendActivity())['b']!.nowPlaying, halo);
    f.me = 'b';
    await f.setSharing(const Sharing(listening: false, top: true));
    await f.publishNowPlaying(halo);
    f.me = 'a';
    final b = (await f.friendActivity())['b']!;
    expect(b.nowPlaying, isNull);
    expect(b.roomCode, isNull);
    expect(b.top, top);
  });
}
