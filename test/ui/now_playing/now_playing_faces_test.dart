import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/ui/now_playing/now_playing_page.dart';
import 'package:songies/ui/now_playing/now_playing_queue.dart';
import 'package:songies/ui/room/room_button.dart';
import 'package:songies/ui/room/room_face.dart';

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

  /// The queue list, or with [page] the full-screen player.
  Future<void> pump(
    WidgetTester tester, {
    bool page = false,
    List<Object> extra = const [],
  }) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: page ? '/now-playing' : '/',
        extraOverrides: [...rig.overrides, ...extra.cast()],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: NowPlayingQueue()),
          ),
          GoRoute(path: '/now-playing', pageBuilder: nowPlayingPage),
        ],
      ),
    );
    await flush(tester);
  }

  /// Any room face.
  final anyFace = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('room.face.'),
  );

  Finder faceIn(String row, String user) => find.descendant(
    of: find.byKey(Key(row)),
    matching: find.byKey(Key('room.face.$user')),
  );

  uiTest('queue rows show who added each song', (tester) async {
    await pump(tester);
    await rig.joinAs(tester, RoomRole.queue);
    await rig.run(tester, rig.service!.guestView!.addToEnd([roomTrack('b')]));
    await tester.pump(const Duration(milliseconds: 600));
    expect(h.player.state.addedBy, ['u9', 'u1']);
    // The host's song is the host's; the one this device added is its own.
    expect(faceIn('queue.row.0', 'u9'), findsOneWidget);
    expect(faceIn('queue.row.1', 'u1'), findsOneWidget);
    expect(find.textContaining('Added by'), findsNothing);
    // No picture: the name's initial, and the name on hover.
    expect(
      find.descendant(
        of: find.byKey(const Key('room.face.u9')),
        matching: find.text('D'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('denis'), findsOneWidget);
    await rig.dispose(tester);
  });

  uiTest('the Now Playing title shows who added the song', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, page: true);
    await rig.joinAs(tester, RoomRole.listener);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('room.face.u9')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('denis')), findsWidgets);
    semantics.dispose();
    await rig.dispose(tester);
  });

  uiTest('outside a room no faces', (tester) async {
    await pump(tester);
    await tester.runAsync(() => h.player.playQueue([roomTrack('a')]));
    await flush(tester);
    expect(find.byKey(const Key('queue.row.0')), findsOneWidget);
    expect(anyFace, findsNothing);
    await rig.dispose(tester);
  });

  uiTest("an older host's songs show no face", (tester) async {
    await pump(
      tester,
      extra: [roomFacesProvider.overrideWithValue(const RoomFaces({}))],
    );
    await tester.runAsync(() => h.player.playQueue([roomTrack('a')]));
    await flush(tester);
    expect(find.byKey(const Key('queue.row.0')), findsOneWidget);
    expect(find.byType(RoomFaceDot), findsOneWidget);
    expect(anyFace, findsNothing);
    expect(tester.takeException(), isNull);
    await rig.dispose(tester);
  });
}
