import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/ui/shell/player_bar.dart';
import 'package:songies/ui/widgets/song_menu.dart';

import '../helpers/room_rig.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late RoomRig rig;

  setUp(() async {
    h = await UiHarness.create();
    rig = RoomRig(h);
  });
  tearDown(() => h.dispose());

  /// The player bar, and a button opening a local song's menu.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: rig.overrides,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () => showSongMenu(
                      context,
                      ref,
                      MenuSong.track(roomTrack('x', source: 'local')),
                      anchor: const Rect.fromLTWH(400, 300, 1, 1),
                    ),
                    child: const Text('Local song'),
                  ),
                ),
              ),
              bottomNavigationBar: const PlayerBar(),
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
            ),
          )
          .onPressed !=
      null;

  Future<void> openPlayingSongMenu(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PlayerBar),
        matching: find.text('Song a'),
      ),
      buttons: 2,
    );
    await tester.pump();
    await flush(tester);
    await tester.pumpAndSettle();
  }

  PopupMenuItem<Object?>? addToQueue(WidgetTester tester) {
    final f = find.byKey(const Key('songMenu.addToQueue'));
    if (f.evaluate().isEmpty) return null;
    return tester.widget<PopupMenuItem<Object?>>(f);
  }

  uiTest('no room: the controls work as always', (tester) async {
    await pump(tester);
    await tester.runAsync(() => h.player.playQueue([roomTrack('a')]));
    await flush(tester);
    for (final k in ['shuffle', 'previous', 'next', 'repeat']) {
      expect(enabled(tester, 'playerBar.$k'), isTrue, reason: k);
    }
    expect(find.byKey(const Key('room.button')), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('a listener\'s controls are dimmed and inert', (tester) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.listener);
    expect(h.player.state.current?.title, 'Song a');
    for (final k in ['shuffle', 'previous', 'next', 'repeat']) {
      expect(enabled(tester, 'playerBar.$k'), isFalse, reason: k);
    }
    final play = tester.widget<GestureDetector>(
      find.byKey(const Key('playerBar.playPause')),
    );
    expect(play.onTap, isNull);
    expect(
      tester.widget<Slider>(find.byKey(const Key('playerBar.scrubber'))).onChanged,
      isNull,
    );
    // Volume stays each person's own.
    expect(
      tester.widget<Slider>(find.byKey(const Key('playerBar.volume'))).onChanged,
      isNotNull,
    );
    await rig.dispose(tester);
  });

  uiTest('full control: the controls work, through the host', (
    tester,
  ) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.full);
    expect(enabled(tester, 'playerBar.next'), isTrue);
    expect(rig.hostPlayer.state.playing, isTrue);
    await tester.tap(find.byKey(const Key('playerBar.playPause')));
    await rig.run(tester, Future.value());
    expect(rig.hostPlayer.state.playing, isFalse);
    await rig.dispose(tester);
  });

  uiTest('a listener\'s song menu has no Add to queue', (tester) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.listener);
    await openPlayingSongMenu(tester);
    expect(find.text('Add to playlist'), findsOneWidget);
    expect(addToQueue(tester), isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await rig.dispose(tester);
  });

  uiTest('Queue: Add to queue adds to the room\'s queue', (tester) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.queue);
    await openPlayingSongMenu(tester);
    expect(addToQueue(tester)!.enabled, isTrue);
    await tester.tap(find.byKey(const Key('songMenu.addToQueue')));
    await rig.run(tester, Future.value());
    expect(rig.hostPlayer.state.queue.map((t) => t.title), [
      'Song a',
      'Song a',
    ]);
    // The guest's own queue follows the host's, not the menu.
    expect(h.player.state.queue.length, 2);
    await rig.dispose(tester);
  });

  uiTest('Queue: Add to queue is greyed for a local song', (tester) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.queue);
    await tester.tap(find.text('Local song'));
    await tester.pump();
    await flush(tester);
    await tester.pumpAndSettle();
    expect(addToQueue(tester)!.enabled, isFalse);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await rig.dispose(tester);
  });
}
