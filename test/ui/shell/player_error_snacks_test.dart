import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/shell/player_error_snacks.dart';

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

  group('snacks', () {
    late StreamController<PlayerState> states;

    setUp(() => states = StreamController<PlayerState>.broadcast());
    tearDown(() => states.close());

    Future<void> pumpSnacks(WidgetTester tester) => tester.pumpWidget(
      ProviderScope(
        overrides: [playerStateProvider.overrideWith((ref) => states.stream)],
        child: const MaterialApp(
          home: Scaffold(body: PlayerErrorSnacks(child: SizedBox.expand())),
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
      await pumpSnacks(tester);
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

    testWidgets('a local skip says the file is missing', (tester) async {
      await pumpSnacks(tester);
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
      await pumpSnacks(tester);
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
