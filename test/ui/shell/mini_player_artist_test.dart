// Tapping the artist in the mini player.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/remote/remote_protocol.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/shell/mini_player.dart';
import 'package:songies/ui/shell/phone_shell.dart';

import '../../helpers/remote_menu_rig.dart';
import '../../helpers/test_db.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late RemoteMenuRig rig;

  setUp(() async {
    h = await UiHarness.create();
    rig = RemoteMenuRig(h);
  });
  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        extraOverrides: rig.overrides,
        routes: [
          GoRoute(
            path: '/now-playing',
            builder: (_, _) => const Scaffold(body: Text('Now Playing stub')),
          ),
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => PhoneShell(shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (_, _) => const HomePage(),
                    routes: [
                      GoRoute(
                        path: 'ytm/artist/:id',
                        builder: (_, s) => Scaffold(
                          body: Text('artist ${s.pathParameters['id']}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
    await rig.watchDevices(tester);
    await settle(tester);
  }

  Finder inMini(String text) =>
      find.descendant(of: find.byType(MiniPlayer), matching: find.text(text));

  uiTest('tapping the artist opens the artist page; tapping the rest opens '
      'Now Playing', (tester) async {
    final yt = await real(tester, () async {
      await h.db
          .into(h.db.tracks)
          .insert(
            trackRow(
              id: 'y1',
              source: 'yt',
              ytVideoId: 'v1',
              title: 'Yt song',
              artist: 'Yt artist',
            ),
          );
      return h.db.select(h.db.tracks).getSingle();
    });
    h.ytm.radioAnswer = Ok(
      YtmRadio(
        const [],
        null,
        current: const YtmSong(
          videoId: 'v1',
          title: 'Yt song',
          artists: [YtmArtistRef(browseId: 'UCyt', name: 'Yt artist')],
          durationMs: 1000,
        ),
      ),
    );
    await pump(tester);
    await real(tester, () => h.player.playQueue([yt]));
    await settle(tester);

    await tester.tap(inMini('Yt artist'));
    await settle(tester);
    expect(find.text('artist UCyt'), findsOneWidget);
    expect(find.text('Now Playing stub'), findsNothing);

    GoRouter.of(tester.element(find.text('artist UCyt'))).pop();
    await settle(tester);
    await tester.tap(inMini('Yt song'));
    await settle(tester);
    expect(find.text('Now Playing stub'), findsOneWidget);
  });

  uiTest('while controlling another device the strip text is not tappable', (
    tester,
  ) async {
    await real(tester, () => h.addTrack('t1', title: 'Song one'));
    await rig.join('d1', 'Desk');
    final desk = rig.hub.channelFor('d1');
    desk.messages.listen((m) {
      if (m is RemoteHello && m.to == 'd1') {
        desk.send(
          RemoteState(
            from: 'd1',
            epoch: 1,
            offset: 0,
            index: 0,
            queue: const ['t1'],
            playing: true,
            buffering: false,
            shuffle: false,
            positionMs: 0,
            atMs: DateTime.now().millisecondsSinceEpoch,
            durationMs: 200000,
            volume: 1,
            repeat: RepeatMode.off,
          ),
        );
      }
    });
    await pump(tester);
    await tester.tap(find.byKey(const Key('devices.button')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('devices.device.d1')));
    await settle(tester);
    expect(inMini('Playing on Desk'), findsOneWidget);

    await tester.tap(inMini('Playing on Desk'));
    await settle(tester);
    // Falls through to the pill: Now Playing opens, no artist lookup runs.
    expect(find.text('Now Playing stub'), findsOneWidget);
    expect(h.ytm.radioCalls, isEmpty);
  });
}
