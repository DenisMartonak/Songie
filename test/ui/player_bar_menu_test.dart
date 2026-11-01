import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/providers.dart';
import 'package:songies/router.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/shell/player_bar.dart';

import '../helpers/fake_lyrics_service.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  /// The whole app on a 1280x800 desktop window, playing 'Song one'.
  Future<void> pumpPlaying(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await real(tester, () async {
      await h.addTrack('t1', title: 'Song one', artist: 'Artist one');
      await h.addTrack('t2', title: 'Song two');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          lyricsServiceProvider.overrideWithValue(FakeLyricsService()),
          hasCustomTitleBarProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          routerConfig: buildRouter(),
        ),
      ),
    );
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

  final bar = find.byType(PlayerBar);

  uiTest('right-clicking the playing song opens its menu', (tester) async {
    await pumpPlaying(tester);
    await tester.tap(
      find.descendant(of: bar, matching: find.text('Song one')),
      buttons: kSecondaryButton,
    );
    await settle(tester);
    expect(find.text('Add to playlist'), findsOneWidget);
  });

  uiTest('right-clicking the bar controls opens no menu', (tester) async {
    await pumpPlaying(tester);
    await tester.tap(
      find.byKey(const Key('playerBar.scrubber')),
      buttons: kSecondaryButton,
    );
    await settle(tester);
    expect(find.text('Add to playlist'), findsNothing);
  });
}
