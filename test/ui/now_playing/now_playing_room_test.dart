import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/ui/lyrics/lyrics_strip.dart';
import 'package:songies/ui/now_playing/now_playing_controls.dart';

import '../../helpers/room_rig.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late RoomRig rig;

  setUp(() async {
    h = await UiHarness.create();
    rig = RoomRig(h);
  });
  tearDown(() => h.dispose());

  /// The full-screen player's controls, scrubber and lyrics strip.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: rig.overrides,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: Column(
                children: [
                  NowPlayingScrubber(),
                  NowPlayingControls(),
                  LyricsStrip(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await flush(tester);
  }

  bool enabled(WidgetTester tester, String key) =>
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(IconButton),
              matchRoot: true,
            ),
          )
          .onPressed !=
      null;

  uiTest('a listener\'s full-screen controls are dimmed and inert', (
    tester,
  ) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.listener);
    for (final k in ['shuffle', 'previous', 'next', 'repeat']) {
      expect(enabled(tester, 'nowPlaying.$k'), isFalse, reason: k);
    }
    expect(enabled(tester, 'lyricsStrip.playPause'), isFalse);
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('nowPlaying.scrubber')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const Key('nowPlaying.playPause')));
    await rig.run(tester, Future.value());
    expect(rig.hostPlayer.state.playing, isTrue);
    expect(h.player.state.playing, isTrue);
    await rig.dispose(tester);
  });

  uiTest('Queue: still no playback control', (tester) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.queue);
    expect(enabled(tester, 'nowPlaying.next'), isFalse);
    expect(enabled(tester, 'lyricsStrip.playPause'), isFalse);
    await rig.dispose(tester);
  });

  uiTest('full control: the controls work, through the host', (tester) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.full);
    for (final k in ['shuffle', 'previous', 'next', 'repeat']) {
      expect(enabled(tester, 'nowPlaying.$k'), isTrue, reason: k);
    }
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('nowPlaying.scrubber')))
          .onChanged,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('lyricsStrip.playPause')));
    await rig.run(tester, Future.value());
    expect(rig.hostPlayer.state.playing, isFalse);
    await rig.dispose(tester);
  });
}
