import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/island/island_host.dart';
import 'package:songies/ui/shell/player_error_islands.dart';

void main() {
  test('ytdlp-prefixed errors use the yt user copy', () {
    expect(
      playerErrorMessage('ytdlp:extractor:boom'),
      'YouTube changed something — try Settings → Update yt-dlp',
    );
  });

  test('network messages and others show as is', () {
    expect(playerErrorMessage("You're offline"), "You're offline");
  });

  group('islands', () {
    late StreamController<PlayerState> states;

    setUp(() => states = StreamController<PlayerState>.broadcast());
    tearDown(() => states.close());

    Future<void> pumpIslands(WidgetTester tester) => tester.pumpWidget(
      ProviderScope(
        overrides: [playerStateProvider.overrideWith((ref) => states.stream)],
        child: MaterialApp(
          builder: (_, c) => IslandHost(child: c!),
          home: Scaffold(body: PlayerErrorIslands(child: SizedBox.expand())),
        ),
      ),
    );

    Future<void> push(WidgetTester tester, PlayerState s) async {
      states.add(s);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a YouTube skip names the song and the yt reason', (
      tester,
    ) async {
      await pumpIslands(tester);
      await push(tester, const PlayerState());
      await push(
        tester,
        const PlayerState(
          notice: PlayerNotice(
            trackTitle: 'Song A',
            reason: 'ytdlp:notFound:gone',
          ),
        ),
      );
      expect(
        find.text(
          "Skipped 'Song A' — Not found on YouTube — it may be private or "
          'deleted',
        ),
        findsOneWidget,
      );
    });

    for (final kind in ['ageRestricted', 'ageRestrictedAccount']) {
      testWidgets('$kind offers Sign in, which opens Settings', (tester) async {
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  const Scaffold(body: PlayerErrorIslands(child: SizedBox())),
            ),
            GoRoute(
              path: '/settings',
              builder: (_, _) => const Scaffold(body: Text('settings page')),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerStateProvider.overrideWith((ref) => states.stream),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              builder: (_, c) => IslandHost(child: c!),
            ),
          ),
        );
        await push(tester, const PlayerState());
        await push(
          tester,
          PlayerState(
            notice: PlayerNotice(trackTitle: 'Song', reason: 'ytdlp:$kind:x'),
          ),
        );
        // Let the island finish rising before tapping its action.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        expect(find.text('settings page'), findsOneWidget);
      });
    }

    testWidgets('other skips have no action', (tester) async {
      await pumpIslands(tester);
      await push(tester, const PlayerState());
      await push(
        tester,
        const PlayerState(
          notice: PlayerNotice(trackTitle: 'Song', reason: 'ytdlp:notFound:x'),
        ),
      );
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('a local skip says the file is missing', (tester) async {
      await pumpIslands(tester);
      await push(tester, const PlayerState());
      await push(
        tester,
        const PlayerState(
          notice: PlayerNotice(
            trackTitle: 'Song B',
            reason: PlayerService.fileMissingReason,
          ),
        ),
      );
      expect(find.text("Skipped 'Song B' — file is missing"), findsOneWidget);
    });

    testWidgets('too many failures names the last reason', (tester) async {
      await pumpIslands(tester);
      await push(tester, const PlayerState());
      await push(
        tester,
        const PlayerState(
          error: PlayerService.tooManyFailuresError,
          notice: PlayerNotice(
            trackTitle: 'Song C',
            reason: 'ytdlp:notFound:gone',
          ),
        ),
      );
      expect(
        find.text(
          "Stopped — 3 songs in a row couldn't play. Not found on YouTube — "
          'it may be private or deleted',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Skipped'), findsNothing);
    });
  });
}
