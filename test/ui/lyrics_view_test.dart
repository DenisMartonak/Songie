import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/data/database.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_service.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/contrast.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/lyrics/lyrics_view.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';

import '../helpers/fake_lyrics_service.dart';
import '../helpers/ui_harness.dart';

/// Invented lines, one every 5 s from 5 s: line i is at (5 + 5i) s.
List<LyricLine> invented(int n, {String Function(int i)? text}) => [
  for (var i = 0; i < n; i++)
    LyricLine(
      Duration(seconds: 5 + 5 * i),
      text?.call(i) ?? 'Paper lantern number $i',
    ),
];

TrackLyrics syncedOf(
  List<LyricLine> lines, {
  LyricsSource source = LyricsSource.lrclib,
  String? credit,
}) => TrackLyrics(
  kind: LyricsKind.synced,
  source: source,
  lines: lines,
  credit: credit,
);

void main() {
  late UiHarness h;
  late FakeLyricsService service;
  late StreamController<PlayerState> states;
  late List<Track> tracks;

  setUp(() async {
    h = await UiHarness.create();
    service = FakeLyricsService();
    states = StreamController<PlayerState>.broadcast();
  });
  tearDown(() async {
    await states.close();
    await h.dispose();
  });

  Future<void> pumpView(
    WidgetTester tester, {
    LyricsDensity density = LyricsDensity.large,
    Size size = const Size(400, 800),
    double? panelWidth,
    bool disableAnimations = false,
    bool loadPlayer = false,
    ThemeSpec theme = ThemeSpec.builtInDefault,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await real(tester, () async {
      await h.addTrack('t1', title: 'Song one');
      await h.addTrack('t2', title: 'Song two');
      await h.addTrack('t3', title: 'Song three');
      tracks = await (h.db.select(
        h.db.tracks,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      // A loaded player, so seeks reach the fake backend.
      if (loadPlayer) await h.player.playQueue(tracks);
    });
    final view = LyricsView(density: density);
    await tester.pumpWidget(
      h.app(
        theme: theme,
        disableAnimations: disableAnimations,
        initialLocation: '/',
        extraOverrides: [
          lyricsServiceProvider.overrideWithValue(service),
          playerStateProvider.overrideWith((ref) => states.stream),
        ],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: panelWidth == null
                  ? view
                  : Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(width: panelWidth, child: view),
                    ),
            ),
          ),
        ],
      ),
    );
    await flush(tester);
  }

  PlayerState at(
    Duration position, {
    int index = 0,
    bool playing = true,
    List<Track>? queue,
  }) => PlayerState(
    queue: queue ?? tracks,
    index: index,
    position: position,
    playing: playing,
  );

  Future<void> push(WidgetTester tester, PlayerState s) async {
    states.add(s);
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  SongiesColors colorsOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(LyricsView)))
          .extension<SongiesColors>()!;

  Color lineColor(WidgetTester tester, int i) => tester
      .widget<RichText>(
        find.descendant(
          of: find.byKey(ValueKey('lyrics.line.$i')),
          matching: find.byType(RichText),
        ),
      )
      .text
      .style!
      .color!;

  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('lyrics.synced')),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  Rect viewport(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('lyrics.synced')));

  Rect lineRect(WidgetTester tester, int i) =>
      tester.getRect(find.byKey(ValueKey('lyrics.line.$i')));

  group('synced', () {
    uiTest('highlights line 1 at 12 s and none at 0 s', (tester) async {
      service.answers['t1'] = LyricsShown(syncedOf(invented(5)));
      await pumpView(tester);
      await push(tester, at(Duration.zero));
      final text = colorsOf(tester).text;
      for (var i = 0; i < 5; i++) {
        expect(lineColor(tester, i), isNot(text), reason: 'line $i at 0 s');
      }
      await push(tester, at(const Duration(seconds: 12)));
      expect(lineColor(tester, 1), text);
      expect(lineColor(tester, 0), isNot(text));
      expect(lineColor(tester, 2), isNot(text));
    });

    uiTest('a seek back to 6 s highlights line 0', (tester) async {
      service.answers['t1'] = LyricsShown(syncedOf(invented(5)));
      await pumpView(tester);
      await push(tester, at(const Duration(seconds: 12)));
      await push(tester, at(const Duration(seconds: 6)));
      expect(lineColor(tester, 0), colorsOf(tester).text);
      expect(lineColor(tester, 1), isNot(colorsOf(tester).text));
    });

    uiTest('the dimmed lines keep AA contrast for large text', (tester) async {
      service.answers['t1'] = LyricsShown(syncedOf(invented(5)));
      await pumpView(tester);
      await push(tester, at(const Duration(seconds: 12)));
      final c = colorsOf(tester);
      final dim = lineColor(tester, 0);
      final onBg = Color.alphaBlend(dim, c.background);
      expect(dim.a, lessThan(1));
      expect(
        (onBg.computeLuminance() + 0.05) /
            (c.background.computeLuminance() + 0.05),
        greaterThanOrEqualTo(3),
      );
    });

    for (final (name, theme) in [
      ('default', ThemeSpec.builtInDefault),
      ('album glow', ThemeSpec.albumGlow),
      ('terminal', ThemeSpec.terminal),
    ]) {
      for (final (density, minRatio) in [
        (LyricsDensity.large, 3.0),
        (LyricsDensity.compact, 4.5),
      ]) {
        uiTest('$name, ${density.name}: the dimmed lines reach '
            '$minRatio:1 on the background and over the worst blurred '
            'cover, top and bottom', (tester) async {
          service.answers['t1'] = LyricsShown(syncedOf(invented(5)));
          await pumpView(tester, density: density, theme: theme);
          await push(tester, at(const Duration(seconds: 12)));
          final c = colorsOf(tester);
          final dim = lineColor(tester, 0);
          expect(dim, isNot(c.text));
          expect(c.blurNowPlaying, isTrue);
          for (final bg in [
            c.background,
            blurWorstCaseTop(c),
            blurWorstCaseBottom(c),
          ]) {
            expect(
              contrastRatio(Color.alphaBlend(dim, bg), bg),
              greaterThanOrEqualTo(minRatio),
              reason: 'over $bg',
            );
          }
        });
      }
    }

    uiTest('tapping line 2 seeks to its time', (tester) async {
      service.answers['t1'] = LyricsShown(syncedOf(invented(5)));
      await pumpView(tester, loadPlayer: true);
      await push(tester, at(const Duration(seconds: 12)));
      await tester.tap(find.text('Paper lantern number 2'));
      await flush(tester);
      expect(h.backend.calls, contains('seek:15000'));
    });

    uiTest('a drag stops following; it resumes after 5 s', (tester) async {
      service.answers['t1'] = LyricsShown(syncedOf(invented(60)));
      await pumpView(tester);
      await push(tester, at(const Duration(seconds: 102))); // line 19
      final before = offset(tester);
      expect(before, greaterThan(0));

      await tester.drag(
        find.byKey(const Key('lyrics.synced')),
        const Offset(0, 300),
      );
      await tester.pump(const Duration(seconds: 1));
      final dragged = offset(tester);
      expect(dragged, lessThan(before));

      await push(tester, at(const Duration(seconds: 117))); // line 22
      expect(offset(tester), dragged, reason: 'not following');

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(offset(tester), greaterThan(before));
      final vp = viewport(tester);
      final top = lineRect(tester, 22).top - vp.top;
      expect(top / vp.height, closeTo(0.35, 0.08));
    });

    uiTest('a keyboard scroll stops following; the view\'s own follow '
        'scrolls do not', (tester) async {
      service.answers['t1'] = LyricsShown(syncedOf(invented(60)));
      await pumpView(tester);
      await push(tester, at(const Duration(seconds: 102))); // line 19
      // Several follow scrolls in a row: each one still follows.
      await push(tester, at(const Duration(seconds: 117))); // line 22
      final at22 = offset(tester);
      await push(tester, at(const Duration(seconds: 157))); // line 30
      final at30 = offset(tester);
      expect(at30, greaterThan(at22), reason: 'still following');

      // A Page Up, as the keyboard sends it: no drag details.
      Actions.invoke(
        tester.element(find.text('Paper lantern number 30')),
        const ScrollIntent(
          direction: AxisDirection.up,
          type: ScrollIncrementType.page,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final scrolled = offset(tester);
      expect(scrolled, lessThan(at30));

      await push(tester, at(const Duration(seconds: 202))); // line 39
      expect(offset(tester), scrolled, reason: 'not following');

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(offset(tester), greaterThan(at30), reason: 'resumed');
    });

    uiTest('while paused, a position change does not scroll', (tester) async {
      service.answers['t1'] = LyricsShown(syncedOf(invented(60)));
      await pumpView(tester);
      await push(tester, at(const Duration(seconds: 102), playing: false));
      final before = offset(tester);
      expect(before, greaterThan(0), reason: 'placed on mount');
      await push(tester, at(const Duration(seconds: 202), playing: false));
      expect(offset(tester), before);
    });

    uiTest('with reduced motion nothing animates after a line change', (
      tester,
    ) async {
      service.answers['t1'] = LyricsShown(syncedOf(invented(60)));
      await pumpView(tester, disableAnimations: true);
      await push(tester, at(const Duration(seconds: 102)));
      states.add(at(const Duration(seconds: 117)));
      await flush(tester);
      expect(tester.hasRunningAnimations, isFalse);
      expect(lineColor(tester, 22), colorsOf(tester).text);
      final vp = viewport(tester);
      expect(
        (lineRect(tester, 22).top - vp.top) / vp.height,
        closeTo(0.35, 0.08),
      );
    });

    for (final (name, density, size, panel) in [
      ('large at 400x800', LyricsDensity.large, const Size(400, 800), null),
      (
        'compact in a 320 px panel',
        LyricsDensity.compact,
        const Size(1280, 800),
        320.0,
      ),
    ]) {
      uiTest('60 long lines, $name: no overflow, current line in view', (
        tester,
      ) async {
        service.answers['t1'] = LyricsShown(
          syncedOf(
            invented(
              60,
              text: (i) =>
                  'Line $i where the paper lanterns drift along the slow '
                  'river under a borrowed moon and nobody counts the hours',
            ),
          ),
        );
        await pumpView(tester, density: density, size: size, panelWidth: panel);
        await push(tester, at(const Duration(seconds: 207))); // line 40
        expect(tester.takeException(), isNull);
        final vp = viewport(tester);
        final line = lineRect(tester, 40);
        expect(line.top, greaterThanOrEqualTo(vp.top));
        expect(line.bottom, lessThanOrEqualTo(vp.bottom));
        if (panel != null) expect(vp.width, panel);
      });
    }
  });

  group('plain', () {
    uiTest('shows the text; tapping does nothing', (tester) async {
      service.answers['t1'] = const LyricsShown(
        TrackLyrics(
          kind: LyricsKind.plain,
          source: LyricsSource.lrclib,
          text: 'Kettle sings at dawn\nThe cat ignores it',
        ),
      );
      await pumpView(tester, loadPlayer: true);
      await push(tester, at(const Duration(seconds: 12)));
      expect(find.textContaining('Kettle sings at dawn'), findsOneWidget);
      await tester.tap(find.textContaining('Kettle sings at dawn'));
      await flush(tester);
      expect(h.backend.calls.where((c) => c.startsWith('seek:')), isEmpty);
    });
  });

  group('states', () {
    uiTest('no track shows nothing', (tester) async {
      await pumpView(tester);
      await push(tester, const PlayerState());
      expect(
        find.descendant(
          of: find.byType(LyricsView),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(service.lookups, isEmpty);
    });

    uiTest('loading shows Shimmer bars', (tester) async {
      service.gates['t1'] = Completer();
      await pumpView(tester);
      await push(tester, at(Duration.zero));
      expect(find.byKey(const Key('lyrics.loading')), findsOneWidget);
      service.gates['t1']!.complete(const LyricsNone());
      await flush(tester);
    });

    uiTest('LyricsNone offers Search again, which forces a lookup', (
      tester,
    ) async {
      await pumpView(tester);
      await push(tester, at(Duration.zero));
      expect(find.text('No lyrics found for this song'), findsOneWidget);
      expect(service.lookups.last, (id: 't1', force: false));
      await tester.tap(find.widgetWithText(TextButton, 'Search again'));
      await flush(tester);
      expect(service.lookups.last, (id: 't1', force: true));
    });

    uiTest('LyricsOffline asks for a connection and retries online', (
      tester,
    ) async {
      service.answers['t1'] = const LyricsOffline();
      await pumpView(tester);
      await push(tester, at(Duration.zero));
      expect(find.text('Lyrics need a connection'), findsOneWidget);
      final before = service.lookups.length;

      service.answers['t1'] = LyricsShown(syncedOf(invented(3)));
      h.network.set(NetworkKind.wifi);
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(service.lookups.length, before + 1);
      expect(find.text('Paper lantern number 0'), findsOneWidget);
    });
  });

  group('credits', () {
    for (final (source, label) in [
      (LyricsSource.lrclib, 'Lyrics from LRCLIB'),
      (LyricsSource.youtube, 'Lyrics from YouTube Music'),
      (LyricsSource.file, 'Lyrics from the file'),
    ]) {
      uiTest('credit for ${source.name}', (tester) async {
        service.answers['t1'] = LyricsShown(
          syncedOf(
            invented(3),
            source: source,
            credit: source == LyricsSource.youtube ? 'Source: Inkwell' : null,
          ),
        );
        await pumpView(tester);
        await push(tester, at(Duration.zero));
        expect(find.text(label), findsOneWidget);
        expect(
          find.text('Source: Inkwell'),
          source == LyricsSource.youtube ? findsOneWidget : findsNothing,
        );
      });
    }

    uiTest('plain lyrics carry the credit too', (tester) async {
      service.answers['t1'] = const LyricsShown(
        TrackLyrics(
          kind: LyricsKind.plain,
          source: LyricsSource.youtube,
          text: 'Kettle sings at dawn',
          credit: 'Source: Inkwell',
        ),
      );
      await pumpView(tester);
      await push(tester, at(Duration.zero));
      expect(find.text('Lyrics from YouTube Music'), findsOneWidget);
      expect(find.text('Source: Inkwell'), findsOneWidget);
    });
  });

  group('track switches', () {
    uiTest('a slow lookup for A finishing after a switch to B shows B', (
      tester,
    ) async {
      final a = service.gates['t1'] = Completer();
      service.answers['t2'] = LyricsShown(
        syncedOf([const LyricLine(Duration(seconds: 1), 'Words of B')]),
      );
      await pumpView(tester);
      await push(tester, at(Duration.zero));
      expect(find.byKey(const Key('lyrics.loading')), findsOneWidget);

      await push(tester, at(Duration.zero, index: 1));
      a.complete(
        LyricsShown(
          syncedOf([const LyricLine(Duration(seconds: 1), 'Words of A')]),
        ),
      );
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Words of B'), findsOneWidget);
      expect(find.text('Words of A'), findsNothing);
    });
  });

  group('prefetch', () {
    uiTest('prefetches up next, again when it changes', (tester) async {
      await pumpView(tester);
      await push(tester, at(Duration.zero));
      expect(service.prefetched, ['t2']);
      await push(tester, at(const Duration(seconds: 3)));
      expect(service.prefetched, ['t2'], reason: 'a tick is not a change');
      await push(tester, at(Duration.zero, index: 1));
      expect(service.prefetched, ['t2', 't3']);
    });
  });
}
