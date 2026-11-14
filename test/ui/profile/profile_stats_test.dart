// The profile's stats section: period picker, minutes and chart, top 10
// artists and songs with pictures, on the phone and the wide layout, for
// your own profile and a friend's.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/providers.dart';
import 'package:songies/stats/artist_photos.dart';
import 'package:songies/stats/stats_models.dart';
import 'package:songies/ui/profile/profile_stats.dart';
import 'package:songies/ui/widgets/favorite_star.dart';

import '../../helpers/ui_harness.dart';

/// Photos the test knows, without lookups.
class _Photos extends ArtistPhotos {
  _Photos(SettingsRepository settings, this.known)
    : super(
        settings: settings,
        saved: () async => const {},
        browseIdForTrack: (_) async => null,
        artist: (_) async => null,
      );

  final Map<String, ArtistPhoto> known;

  @override
  ArtistPhoto? of(String name) => known[name];
}

List<StatsBucket> _days(int count) => [
  for (var i = 0; i < count; i++)
    StatsBucket(
      start: DateTime(2026, 10, 16 + i),
      end: DateTime(2026, 10, 17 + i),
      heard: Duration(minutes: 10 + i),
    ),
];

List<ArtistStat> _artists({String prefix = 'Artist', bool numbers = true}) => [
  for (var i = 1; i <= 10; i++)
    ArtistStat(
      name: '$prefix $i',
      plays: numbers ? 30 - i : 0,
      heard: numbers ? Duration(minutes: 413 - i) : Duration.zero,
      sampleTrackId: 's$i',
    ),
];

List<SongStat> _songs({
  String prefix = 'Song',
  bool numbers = true,
  bool friend = false,
}) => [
  for (var i = 1; i <= 10; i++)
    SongStat(
      trackId: friend ? (i == 2 ? 'friend:month:1' : 'yt:v$i') : 's$i',
      title: '$prefix $i',
      artist: 'Artist $i',
      mainArtist: 'Artist $i',
      plays: numbers ? 42 - i : 0,
      heard: numbers ? Duration(minutes: 100 - i) : Duration.zero,
      videoId: friend && i != 2 ? 'v$i' : null,
    ),
];

PeriodStats _stats({
  StatsPeriod period = StatsPeriod.month,
  List<ArtistStat>? artists,
  List<SongStat>? songs,
}) => PeriodStats(
  period: period,
  total: const Duration(minutes: 2418),
  previousTotal: const Duration(minutes: 2000),
  buckets: _days(30),
  topArtists: artists ?? _artists(),
  topSongs: songs ?? _songs(),
);

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    WidgetTester tester, {
    PeriodStats? stats,
    StatsPeriod period = StatsPeriod.month,
    ValueChanged<StatsPeriod>? onPeriod,
    bool picker = true,
    bool wide = false,
    bool mine = true,
    String? note,
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        extraOverrides: overrides,
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(
                child: ProfileStats(
                  stats: stats ?? _stats(),
                  period: period,
                  onPeriod: picker ? (onPeriod ?? (_) {}) : null,
                  wide: wide,
                  mine: mine,
                  note: note,
                ),
              ),
            ),
            routes: [
              GoRoute(
                path: 'ytm/artist/:id',
                builder: (_, s) => Text('artist ${s.pathParameters['id']}'),
              ),
            ],
          ),
          GoRoute(
            path: '/search',
            builder: (_, _) => Consumer(
              builder: (_, ref, _) =>
                  Text('search: ${ref.watch(searchQueryProvider)}'),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Finder key(String k) => find.byKey(Key(k));

  Future<void> tapVisible(WidgetTester tester, String k) async {
    await tester.scrollUntilVisible(key(k), 200);
    await tester.tap(key(k));
    await settle(tester);
  }

  for (final wide in [false, true]) {
    final label = wide ? 'wide' : 'phone';
    uiTest('shows 5 then 10 after Show more ($label)', (tester) async {
      size(tester, wide ? const Size(1280, 900) : const Size(400, 800));
      await pump(tester, wide: wide);
      expect(find.text('Top 10 artists'), findsOneWidget);
      expect(find.text('Top 10 songs'), findsOneWidget);
      expect(key('profile.artist.4'), findsOneWidget);
      expect(key('profile.artist.5'), findsNothing);
      expect(key('profile.song.4'), findsOneWidget);
      expect(key('profile.song.5'), findsNothing);

      await tapVisible(tester, 'profile.artists.more');
      expect(key('profile.artists.more'), findsNothing);
      await tester.scrollUntilVisible(key('profile.artist.9'), 200);
      expect(find.text('Artist 10'), findsOneWidget);

      await tapVisible(tester, 'profile.songs.more');
      expect(key('profile.songs.more'), findsNothing);
      await tester.scrollUntilVisible(key('profile.song.9'), 200);
      expect(find.text('Song 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  uiTest('artist row shows minutes, song row shows plays', (tester) async {
    size(tester, const Size(400, 800));
    await pump(tester);
    expect(
      find.descendant(
        of: key('profile.artist.0'),
        matching: find.text('412 min'),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(key('profile.song.0'), 200);
    expect(
      find.descendant(
        of: key('profile.song.0'),
        matching: find.text('41 plays'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('profile.song.0'),
        matching: find.text('Artist 1'),
      ),
      findsOneWidget,
    );
  });

  uiTest('phone total is a card with minutes and the chart', (tester) async {
    size(tester, const Size(400, 800));
    await pump(tester);
    expect(find.text('Minutes listened'), findsOneWidget);
    expect(tester.widget<Text>(key('profile.total')).data, '2,418');
    expect(key('profile.chart'), findsOneWidget);
    expect(find.text('+21% vs the previous month'), findsOneWidget);
  });

  uiTest('wide total reads "minutes listened in the last 30 days"', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    await pump(tester, wide: true);
    expect(tester.widget<Text>(key('profile.total')).data, '2,418');
    expect(find.text('minutes listened in the last 30 days'), findsOneWidget);
    expect(key('profile.chart'), findsOneWidget);

    await pump(
      tester,
      wide: true,
      period: StatsPeriod.halfYear,
      stats: _stats(period: StatsPeriod.halfYear),
    );
    expect(find.text('minutes listened in the last 6 months'), findsOneWidget);
  });

  uiTest('the picker reports the chosen period', (tester) async {
    size(tester, const Size(400, 800));
    final chosen = <StatsPeriod>[];
    await pump(tester, onPeriod: chosen.add);
    for (final p in StatsPeriod.values) {
      expect(key('profile.period.${p.name}'), findsOneWidget);
    }
    await tester.tap(key('profile.period.week'));
    await settle(tester);
    await tester.tap(key('profile.period.year'));
    await settle(tester);
    expect(chosen, [StatsPeriod.week, StatsPeriod.year]);
  });

  uiTest('the note shows under the picker', (tester) async {
    size(tester, const Size(400, 800));
    await pump(tester, mine: false, note: 'Updated 3 weeks ago');
    expect(find.text('Updated 3 weeks ago'), findsOneWidget);
  });

  uiTest('an empty period says so', (tester) async {
    size(tester, const Size(400, 800));
    await pump(
      tester,
      stats: const PeriodStats(
        period: StatsPeriod.year,
        total: Duration.zero,
        previousTotal: null,
        buckets: [],
        topArtists: [],
        topSongs: [],
      ),
      period: StatsPeriod.year,
    );
    expect(find.text('Nothing played in this period yet'), findsOneWidget);
    expect(key('profile.total'), findsNothing);
    expect(key('profile.chart'), findsNothing);
  });

  uiTest('legacy stats: no picker, no total, no chart, names listed', (
    tester,
  ) async {
    size(tester, const Size(400, 800));
    await pump(
      tester,
      picker: false,
      mine: false,
      stats: PeriodStats(
        period: StatsPeriod.month,
        total: Duration.zero,
        previousTotal: null,
        buckets: const [],
        topArtists: _artists(numbers: false),
        topSongs: _songs(numbers: false, friend: true),
      ),
    );
    for (final p in StatsPeriod.values) {
      expect(key('profile.period.${p.name}'), findsNothing);
    }
    expect(key('profile.total'), findsNothing);
    expect(key('profile.chart'), findsNothing);
    expect(find.text('Nothing played in this period yet'), findsNothing);
    expect(find.text('Artist 1'), findsWidgets);
    await tester.scrollUntilVisible(key('profile.song.0'), 200);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('0 min'), findsNothing);
    expect(find.text('0 plays'), findsNothing);
  });

  bool isNetwork(ImageProvider p, String url) => switch (p) {
    NetworkImage(url: final u) => u == url,
    ResizeImage(:final imageProvider) => isNetwork(imageProvider, url),
    _ => false,
  };

  uiTest('own artist row uses the cached photo when known', (tester) async {
    size(tester, const Size(400, 800));
    await pump(
      tester,
      overrides: [
        artistPhotosProvider.overrideWith(
          (ref) => _Photos(ref.watch(settingsRepositoryProvider), {
            'Artist 1': (browseId: 'UC1', photoUrl: 'https://img/a1.jpg'),
          }),
        ),
      ],
    );
    final images = tester.widgetList<Image>(
      find.descendant(
        of: key('profile.artist.0'),
        matching: find.byType(Image),
      ),
    );
    expect(images.any((i) => isNetwork(i.image, 'https://img/a1.jpg')), isTrue);

    // Its page is known too, so a tap opens it.
    await tester.tap(key('profile.artist.0'));
    await settle(tester);
    expect(find.text('artist UC1'), findsOneWidget);
  });

  uiTest('a friend artist with a browse id opens their page', (tester) async {
    size(tester, const Size(400, 800));
    final artists = _artists();
    artists[0] = ArtistStat(
      name: 'Artist 1',
      plays: 3,
      heard: const Duration(minutes: 412),
      photoUrl: 'https://img/f1.jpg',
      browseId: 'UCf1',
    );
    await pump(tester, mine: false, stats: _stats(artists: artists));
    final images = tester.widgetList<Image>(
      find.descendant(
        of: key('profile.artist.0'),
        matching: find.byType(Image),
      ),
    );
    expect(images.any((i) => isNetwork(i.image, 'https://img/f1.jpg')), isTrue);
    await tester.tap(key('profile.artist.0'));
    await settle(tester);
    expect(find.text('artist UCf1'), findsOneWidget);
  });

  uiTest('a friend artist without one opens Search', (tester) async {
    size(tester, const Size(400, 800));
    await pump(tester, mine: false);
    await tester.tap(key('profile.artist.1'));
    await settle(tester);
    expect(find.text('search: Artist 2'), findsOneWidget);
  });

  uiTest("friend song with a video id plays it; without one isn't tappable", (
    tester,
  ) async {
    size(tester, const Size(400, 800));
    await pump(tester, mine: false, stats: _stats(songs: _songs(friend: true)));
    final cover = tester.widgetList<Image>(
      find.descendant(of: key('profile.song.0'), matching: find.byType(Image)),
    );
    expect(
      cover.any(
        (i) => isNetwork(i.image, 'https://i.ytimg.com/vi/v1/hqdefault.jpg'),
      ),
      isTrue,
    );
    expect(key('profile.song.menu.0'), findsNothing);
    expect(
      find.descendant(
        of: key('profile.song.0'),
        matching: find.byType(FavoriteStar),
      ),
      findsNothing,
    );

    await tapVisible(tester, 'profile.song.1');
    expect(h.ytStore.upserted, isEmpty);
    expect(h.player.state.queue, isEmpty);

    await tapVisible(tester, 'profile.song.0');
    expect(h.ytStore.upserted, ['v1']);
    expect(h.player.state.queue.map((t) => t.ytVideoId), ['v1']);
    expect(h.player.state.queue.single.title, 'Song 1');
  });

  uiTest('own song row keeps menu and star', (tester) async {
    size(tester, const Size(400, 800));
    await real(tester, () => h.addTrack('s1', title: 'Live title'));
    await pump(tester);
    await tester.scrollUntilVisible(key('profile.song.1'), 200);
    expect(
      find.descendant(
        of: key('profile.song.0'),
        matching: find.byType(FavoriteStar),
      ),
      findsOneWidget,
    );
    expect(key('profile.song.menu.0'), findsOneWidget);
    expect(key('profile.song.menu.1'), findsNothing);

    await tester.tap(key('profile.song.1'));
    await settle(tester);
    expect(h.player.state.queue, isEmpty);

    await tester.tap(key('profile.song.0'));
    await settle(tester);
    expect(h.player.state.queue.map((t) => t.id), ['s1']);
  });

  for (final width in [360.0, 840.0]) {
    uiTest('200-char names fit at ${width.round()}', (tester) async {
      size(tester, Size(width, 900));
      final long = 'N' * 200;
      await pump(
        tester,
        wide: width >= 840,
        stats: _stats(
          artists: _artists(prefix: long),
          songs: _songs(prefix: long),
        ),
      );
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'profile.artists.more');
      await tapVisible(tester, 'profile.songs.more');
      await tester.scrollUntilVisible(key('profile.song.9'), 200);
      expect(tester.takeException(), isNull);
    });
  }
}
