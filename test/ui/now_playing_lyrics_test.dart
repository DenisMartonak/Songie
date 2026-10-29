import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/lyrics/lyrics_strip.dart';
import 'package:songies/ui/lyrics/lyrics_view.dart';
import 'package:songies/ui/now_playing/now_playing_header.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';
import 'package:songies/ui/now_playing/now_playing_queue.dart';

import '../helpers/fake_lyrics_service.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late FakeLyricsService service;

  setUp(() async {
    h = await UiHarness.create();
    service = FakeLyricsService()
      ..answers['t1'] = const LyricsShown(
        TrackLyrics(
          kind: LyricsKind.plain,
          source: LyricsSource.lrclib,
          text: 'First invented line\nSecond invented line',
        ),
      );
  });
  tearDown(() => h.dispose());

  /// Opens Now Playing over a stub page with the three seeded songs queued
  /// (the first one playing).
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await real(tester, () async {
      await h.addTrack('t1', title: 'Song one', artist: 'Artist one');
      await h.addTrack('t2', title: 'Song two');
      await h.addTrack('t3', title: 'Song three');
    });
    await tester.pumpWidget(
      h.app(
        disableAnimations: disableAnimations,
        initialLocation: '/',
        extraOverrides: [lyricsServiceProvider.overrideWithValue(service)],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Shell stub')),
          ),
          GoRoute(path: '/now-playing', pageBuilder: nowPlayingPage),
        ],
      ),
    );
    GoRouter.of(tester.element(find.text('Shell stub'))).push('/now-playing');
    await settle(tester);
    final tracks = await real(
      tester,
      () => (h.db.select(
        h.db.tracks,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
    );
    await real(tester, () => h.player.playQueue(tracks));
    await settle(tester);
  }

  Future<void> tapTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(Key('nowPlaying.tab.$tab')));
    await settle(tester);
  }

  group('phone (400x800)', () {
    uiTest('shows three tabs: Now playing, Lyrics and Queue', (tester) async {
      await pumpApp(tester);
      for (final (key, label) in [
        ('player', 'Now playing'),
        ('lyrics', 'Lyrics'),
        ('queue', 'Queue'),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key('nowPlaying.tab.$key')),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      final tabs = tester.widget<NowPlayingTabs>(find.byType(NowPlayingTabs));
      expect(tabs.selected, NowPlayingTab.player);
      expect(find.byType(LyricsView), findsNothing);
      expect(service.lookups, isEmpty, reason: 'no lookup until opened');
    });

    uiTest('Lyrics shows the large view under the strip', (tester) async {
      await pumpApp(tester);
      await tapTab(tester, 'lyrics');

      final view = tester.widget<LyricsView>(find.byType(LyricsView));
      expect(view.density, LyricsDensity.large);
      expect(find.textContaining('First invented line'), findsOneWidget);
      expect(find.byType(LyricsStrip), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(LyricsStrip)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(LyricsView)).dy),
      );
      expect(tester.getSize(find.byType(LyricsStrip)).height, closeTo(56, 8));
      expect(service.lookups.map((l) => l.id), ['t1']);
    });

    uiTest('the strip shows the song and toggles play/pause', (tester) async {
      await pumpApp(tester);
      await tapTab(tester, 'lyrics');

      expect(
        tester.widget<Text>(find.byKey(const Key('lyricsStrip.title'))).data,
        'Song one',
      );
      expect(
        find.descendant(
          of: find.byType(LyricsStrip),
          matching: find.text('Artist one'),
        ),
        findsOneWidget,
      );
      expect(h.player.state.playing, isTrue);
      final button = find.byKey(const Key('lyricsStrip.playPause'));
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.pause_rounded)),
        findsOneWidget,
      );

      await tester.tap(button);
      await settle(tester);
      expect(h.player.state.playing, isFalse);
      expect(
        find.descendant(
          of: button,
          matching: find.byIcon(Icons.play_arrow_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(button);
      await settle(tester);
      expect(h.player.state.playing, isTrue);
    });

    uiTest('Queue still works, and Now playing comes back', (tester) async {
      // Keeps the playing row's equalizer bars still, so the queue settles.
      await pumpApp(tester, disableAnimations: true);
      await tapTab(tester, 'lyrics');
      await tapTab(tester, 'queue');
      expect(find.byType(NowPlayingQueue), findsOneWidget);
      expect(find.byType(LyricsView), findsNothing);
      expect(find.byType(LyricsStrip), findsNothing);

      await tapTab(tester, 'player');
      expect(find.byType(NowPlayingQueue), findsNothing);
      expect(find.byKey(const Key('nowPlaying.art')), findsOneWidget);
    });
  });

  group('desktop dialog (1280x800)', () {
    uiTest('the Lyrics tab shows the lyrics view', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      expect(find.byKey(const Key('nowPlaying.panel')), findsOneWidget);
      await tapTab(tester, 'lyrics');

      expect(
        find.descendant(
          of: find.byKey(const Key('nowPlaying.panel')),
          matching: find.byType(LyricsView),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('First invented line'), findsOneWidget);
      // The player bar already shows the song on desktop.
      expect(find.byType(LyricsStrip), findsNothing);
    });
  });
}
