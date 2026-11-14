// The profile view: the header (avatar, name, friend count, actions,
// listening) over the stats, on the phone and the wide layout, for your
// own profile and a friend's.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/friends/stats_summary.dart';
import 'package:songies/providers.dart';
import 'package:songies/room/room_service.dart';
import 'package:songies/stats/artist_photos.dart';
import 'package:songies/stats/stats_models.dart';
import 'package:songies/stats/stats_repository.dart';
import 'package:songies/ui/account/avatar.dart';
import 'package:songies/ui/profile/profile_stats.dart';
import 'package:songies/ui/profile/profile_view.dart';

import '../../helpers/room_rig.dart';
import '../../helpers/ui_harness.dart';

/// The same scripted stats for every period.
class _FakeStats implements StatsRepository {
  _FakeStats(this.stats);

  final PeriodStats stats;

  @override
  Stream<PeriodStats> watch(StatsPeriod p) => Stream.value(stats);

  /// Each period's own artists, as the photo fill reads them.
  @override
  Future<PeriodStats> period(StatsPeriod p) async =>
      _period(p, prefix: 'All ${p.name}');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No photos; counts loads and fills.
class _Photos extends ArtistPhotos {
  _Photos(SettingsRepository settings)
    : super(
        settings: settings,
        saved: () async => const {},
        browseIdForTrack: (_) async => null,
        artist: (_) async => null,
      );

  int loads = 0;
  final filled = <List<String>>[];

  @override
  Future<void> load() async => loads++;

  @override
  Future<void> fill(List<ArtistStat> artists, {bool force = false}) async =>
      filled.add([for (final a in artists) a.name]);
}

PeriodStats _period(StatsPeriod p, {String prefix = 'Artist'}) => PeriodStats(
  period: p,
  total: const Duration(minutes: 600),
  previousTotal: null,
  buckets: [
    for (var i = 0; i < 7; i++)
      StatsBucket(
        start: DateTime(2026, 11, 1 + i),
        end: DateTime(2026, 11, 2 + i),
        heard: const Duration(minutes: 30),
      ),
  ],
  topArtists: [
    for (var i = 1; i <= 3; i++)
      ArtistStat(
        name: '$prefix $i',
        plays: 10 - i,
        heard: Duration(minutes: 100 - i),
        sampleTrackId: 's$i',
      ),
  ],
  topSongs: const [],
);

void main() {
  late UiHarness h;
  late RoomRig rig;
  const halo = NowPlaying(title: 'Halo', artist: 'Beyonce', videoId: 'v1');

  setUp(() async {
    h = await UiHarness.create();
    h.stats = _FakeStats(_period(StatsPeriod.month, prefix: 'Mine'));
    rig = RoomRig(h);
    // The rig signs the app in as u1 ("me"); f1 (fay) is a friend.
    final f = h.friendsBackend
      ..addUser('u1', 'me')
      ..addUser('f1', 'fay')
      ..addUser('r1', 'ray')
      ..me = 'u1';
    await f.send('f1');
    f.me = 'f1';
    await f.accept('u1');
    f.me = 'u1';
    h.activityBackend
      ..friendsOf = ((id) => id == 'u1' ? {'f1'} : {'u1'})
      ..me = 'u1';
  });
  tearDown(() => h.dispose());

  Future<void> asFay(Future<void> Function(ActivityBackend a) f) async {
    h.activityBackend.me = 'f1';
    await f(h.activityBackend);
    h.activityBackend.me = 'u1';
  }

  late _Photos photos;

  Future<void> pump(
    WidgetTester tester,
    ProfileSource source, {
    Size size = const Size(400, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    photos = _Photos(SettingsRepository(h.db));
    await tester.pumpWidget(
      h.app(
        initialLocation: '/p',
        extraOverrides: [
          ...rig.overrides,
          artistPhotosProvider.overrideWithValue(photos),
        ],
        routes: [
          GoRoute(
            path: '/p',
            builder: (_, _) => Scaffold(
              body: ProfileView(
                source: source,
                actions: [
                  FilledButton(
                    key: const Key('t.edit'),
                    onPressed: () {},
                    child: const Text('Edit profile'),
                  ),
                  IconButton(
                    key: const Key('t.menu'),
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/profile/friends',
            builder: (_, _) => const Scaffold(body: Text('Friends list')),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Finder key(String k) => find.byKey(Key(k));
  String plain(WidgetTester tester, String k) =>
      tester.widget<Text>(key(k)).textSpan?.toPlainText() ??
      tester.widget<Text>(key(k)).data!;

  StatsSummary summary(DateTime at) => StatsSummary(
    at: at,
    periods: {
      for (final p in StatsPeriod.values)
        p: _period(p, prefix: 'Fay ${p.name}'),
    },
  );
  uiTest('phone: avatar, name, friends, actions, listening, then stats', (
    tester,
  ) async {
    await asFay((a) async {
      await a.publishNowPlaying(halo);
      await a.publishTop(summary(DateTime.now()));
    });
    await pump(tester, const FriendProfile('f1'));
    final top = [
      find.byType(PersonAvatar),
      key('profile.name'),
      key('profile.friendCount'),
      key('t.menu'),
      key('profile.listening'),
      find.byType(ProfileStats),
    ].map((f) => tester.getTopLeft(f.first).dy).toList();
    for (var i = 1; i < top.length; i++) {
      expect(top[i], greaterThan(top[i - 1]), reason: 'item $i');
    }
    expect(plain(tester, 'profile.name'), 'fay');
    expect(plain(tester, 'profile.friendCount'), '1 friend');
    expect(plain(tester, 'profile.listening'), contains('Halo'));
    await rig.dispose(tester);
  });

  uiTest('wide: listening sits under the avatar; actions at the far right', (
    tester,
  ) async {
    await asFay((a) => a.publishNowPlaying(halo));
    await pump(tester, const FriendProfile('f1'), size: const Size(1400, 900));
    final avatar = tester.getRect(find.byType(PersonAvatar).first);
    final listening = tester.getRect(key('profile.listening'));
    final name = tester.getRect(key('profile.name'));
    expect(listening.top, greaterThan(avatar.bottom));
    expect(listening.right, lessThan(name.left));
    // Content 1200 wide, centered in 1400, with 24 inside.
    expect(tester.getRect(key('t.menu')).right, closeTo(1276, 1));
    expect(name.top, lessThan(avatar.center.dy));
    await rig.dispose(tester);
  });

  uiTest('wide: a long name at twice the text size fits', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final long = 'Maximilian' * 4;
    final f = h.friendsBackend..addUser('l1', long);
    await f.send('l1');
    f.me = 'l1';
    await f.accept('u1');
    f.me = 'u1';
    await pump(tester, const FriendProfile('l1'), size: const Size(1000, 900));
    expect(tester.takeException(), isNull);
    expect(key('profile.name'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('scroll view spans the window', (tester) async {
    await pump(tester, const FriendProfile('f1'), size: const Size(1400, 900));
    expect(tester.getSize(find.byType(Scrollable).first).width, 1400);
    await rig.dispose(tester);
  });

  uiTest('friend sharing off says so and shows no picker', (tester) async {
    await asFay((a) => a.setSharing(top: false));
    await pump(tester, const FriendProfile('f1'));
    expect(plain(tester, 'profile.noShare'), "fay doesn't share their stats");
    expect(key('profile.period.week'), findsNothing);
    expect(key('profile.noStats'), findsNothing);
    await rig.dispose(tester);
  });

  uiTest('friend sharing on with no summary says No stats yet', (tester) async {
    await asFay((a) => a.publishNowPlaying(halo));
    await pump(tester, const FriendProfile('f1'));
    expect(plain(tester, 'profile.noStats'), 'No stats from fay yet');
    expect(key('profile.noShare'), findsNothing);
    await rig.dispose(tester);
  });

  uiTest('a two-week-old summary says Updated 2 weeks ago', (tester) async {
    h.now = () => DateTime(2026, 11, 28, 12);
    await asFay((a) => a.publishTop(summary(DateTime(2026, 11, 14))));
    await pump(tester, const FriendProfile('f1'));
    expect(plain(tester, 'profile.updated'), 'Updated 2 weeks ago');
    await rig.dispose(tester);
  });

  uiTest('a summary from today says nothing about its age', (tester) async {
    h.now = () => DateTime(2026, 11, 28, 13);
    await asFay((a) => a.publishTop(summary(DateTime(2026, 11, 28))));
    await pump(tester, const FriendProfile('f1'));
    expect(key('profile.updated'), findsNothing);
    expect(find.text('Fay month 1'), findsOneWidget);
    await rig.dispose(tester);
  });

  test('relative ages', () {
    final now = DateTime(2026, 11, 28, 9);
    String? at(DateTime d) => profileUpdatedText(d, now);
    expect(at(DateTime(2026, 11, 28)), isNull);
    expect(at(DateTime(2026, 11, 27)), 'Updated yesterday');
    expect(at(DateTime(2026, 11, 25)), 'Updated 3 days ago');
    expect(at(DateTime(2026, 11, 21)), 'Updated 1 week ago');
    expect(at(DateTime(2026, 11, 7)), 'Updated 3 weeks ago');
    expect(at(DateTime(2026, 10, 28)), 'Updated 1 month ago');
    expect(at(DateTime(2026, 6, 1)), 'Updated 6 months ago');
  });

  uiTest("the friend's period picker doesn't change mine", (tester) async {
    await asFay((a) => a.publishTop(summary(DateTime.now())));
    await pump(tester, const FriendProfile('f1'));
    expect(find.text('Fay month 1'), findsOneWidget);
    await tester.tap(key('profile.period.week'));
    await settle(tester);
    expect(find.text('Fay week 1'), findsOneWidget);
    expect(containerOf(tester).read(statsPeriodProvider), StatsPeriod.month);
    await rig.dispose(tester);
  });

  uiTest('an old app\'s summary lists names without numbers', (tester) async {
    h.activityBackend.storeTop(
      'f1',
      StatsSummary.fromJson({
        'artists': [
          {'name': 'Old Artist'},
        ],
        'songs': [
          {'title': 'Old Song', 'artist': 'Old Artist', 'videoId': 'v1'},
        ],
      })!,
    );
    await pump(tester, const FriendProfile('f1'));
    expect(find.text('Old Artist'), findsWidgets);
    expect(find.text('Old Song'), findsOneWidget);
    expect(find.textContaining(' min'), findsNothing);
    expect(find.textContaining('plays'), findsNothing);
    expect(key('profile.period.week'), findsNothing);
    await rig.dispose(tester);
  });

  uiTest('Join shows while they host a room and joins it', (tester) async {
    await pump(tester, const FriendProfile('f1'));
    expect(key('profile.join'), findsNothing);
    await rig.hostRoom(tester);
    await asFay((a) => a.publishNowPlaying(halo, roomCode: 'ABCD2345'));
    // The view asks again every minute while open.
    await tester.pump(const Duration(minutes: 1));
    await settle(tester);
    expect(key('profile.join'), findsOneWidget);
    await tester.tap(key('profile.join'));
    await rig.run(tester, Future.value());
    expect(rig.service!.status, isA<RoomGuesting>());
    await rig.dispose(tester);
  });

  uiTest('own profile: your stats, photos looked up once on open for every '
      'period', (tester) async {
    await pump(tester, const MyProfile());
    expect(plain(tester, 'profile.name'), 'me');
    expect(find.text('Mine 1'), findsOneWidget);
    expect(photos.loads, 1);
    expect(photos.filled, [
      [
        for (final p in StatsPeriod.values)
          for (var i = 1; i <= 3; i++) 'All ${p.name} $i',
      ],
    ]);
    await rig.dispose(tester);
  });

  uiTest('own friend count opens your friends and keeps the request dot', (
    tester,
  ) async {
    h.friendsBackend.me = 'r1';
    await h.friendsBackend.send('u1');
    h.friendsBackend.me = 'u1';
    await pump(tester, const MyProfile());
    expect(plain(tester, 'profile.friendCount'), '1 friend');
    expect(key('friends.dot'), findsOneWidget);
    await tester.tap(key('profile.friendCount'));
    await settle(tester);
    expect(find.text('Friends list'), findsOneWidget);
    await rig.dispose(tester);
  });
}
