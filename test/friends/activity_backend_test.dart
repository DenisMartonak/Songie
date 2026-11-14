import 'package:flutter_test/flutter_test.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/friends/stats_summary.dart';
import 'package:songies/stats/stats_models.dart';

import '../helpers/fake_activity_backend.dart';

void main() {
  const halo = NowPlaying(title: 'Halo', artist: 'Beyonce', videoId: 'v1');
  final top = StatsSummary(
    at: DateTime(2026, 11, 14),
    periods: {
      StatsPeriod.month: const PeriodStats(
        period: StatsPeriod.month,
        total: Duration(minutes: 5),
        previousTotal: null,
        buckets: [],
        topArtists: [
          ArtistStat(name: 'Beyonce', plays: 1, heard: Duration(minutes: 5)),
        ],
        topSongs: [],
      ),
    },
  );

  test('models round-trip and reject bad shapes', () {
    expect(NowPlaying.fromJson(halo.toJson()), halo);
    expect(NowPlaying.fromJson(const {'title': 'x'}), isNull);
    expect(NowPlaying.fromJson('x'), isNull);
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
    await b.setSharing(listening: false);
    expect(calls.last.$1, 'set_sharing');
    // Only the switch that changed: null leaves the other as it is.
    expect(calls.last.$2, {'p_listening': false, 'p_top': null});
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
        'share_top': false,
      },
      {'user_id': 'u3', 'top': top.toJson()},
    ];
    final got = await b.friendActivity();
    expect(got['u2']!.nowPlaying, halo);
    expect(got['u2']!.roomCode, 'ABCD2345');
    expect(got['u2']!.nowUpdatedAt, DateTime.utc(2026, 11, 13, 12));
    expect(got['u2']!.stats, isNull);
    expect(got['u2']!.sharesStats, isFalse);
    // Missing share_top: shared.
    expect(got['u3']!.sharesStats, isTrue);
    expect(
      got['u3']!.stats!.periods[StatsPeriod.month]!.topArtists.single.name,
      'Beyonce',
    );
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
    await f.setSharing(listening: false);
    await f.publishNowPlaying(halo);
    f.me = 'a';
    final b = (await f.friendActivity())['b']!;
    expect(b.nowPlaying, isNull);
    expect(b.roomCode, isNull);
    expect(b.sharesStats, isTrue);
    expect(
      b.stats!.periods[StatsPeriod.month]!.topArtists.single.name,
      'Beyonce',
    );
    f.me = 'b';
    await f.setSharing(top: false);
    f.me = 'a';
    final hidden = (await f.friendActivity())['b']!;
    expect(hidden.stats, isNull);
    expect(hidden.sharesStats, isFalse);
  });
}
