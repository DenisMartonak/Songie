// The phone's way to the device picker and its mini player while another
// device is controlled, with nothing playing here.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/remote/remote_protocol.dart';
import 'package:songies/ui/home/home_page.dart';
import 'package:songies/ui/shell/mini_player.dart';
import 'package:songies/ui/shell/phone_shell.dart';

import '../../helpers/remote_menu_rig.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late RemoteMenuRig rig;
  // Whether Desk answers a hello.
  late bool answers;

  setUp(() async {
    h = await UiHarness.create();
    rig = RemoteMenuRig(h);
    answers = true;
  });
  tearDown(() => h.dispose());

  RemoteState emptyState() => RemoteState(
    from: 'd1',
    epoch: 1,
    offset: 0,
    index: -1,
    queue: const [],
    playing: false,
    buffering: false,
    shuffle: false,
    positionMs: 0,
    atMs: DateTime.now().millisecondsSinceEpoch,
    durationMs: null,
    volume: 1,
    repeat: RepeatMode.off,
  );

  Future<void> deskOnline() async {
    await rig.join('d1', 'Desk');
    final desk = rig.hub.channelFor('d1');
    desk.messages.listen((m) {
      if (m is RemoteHello && m.to == 'd1' && answers) desk.send(emptyState());
    });
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        extraOverrides: rig.overrides,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => PhoneShell(shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(path: '/home', builder: (_, _) => const HomePage()),
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

  uiTest('fresh start, nothing playing: the devices button is on Home and '
      'opens the picker', (tester) async {
    await deskOnline();
    await pump(tester);
    expect(find.byType(MiniPlayer), findsNothing);
    expect(find.byKey(const Key('devices.button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('devices.button')));
    await settle(tester);
    expect(find.byKey(const Key('devices.sheet')), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Desk'), findsOneWidget);
  });

  uiTest('signed out there is no devices button', (tester) async {
    rig = RemoteMenuRig(h, signedIn: false);
    await pump(tester);
    expect(find.byKey(const Key('devices.button')), findsNothing);
  });

  uiTest('linked to a device with an empty queue the mini player shows '
      'Connecting to, then Playing on', (tester) async {
    answers = false;
    await deskOnline();
    await pump(tester);
    await tester.tap(find.byKey(const Key('devices.button')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('devices.device.d1')));
    await settle(tester);
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(inMini('Connecting to Desk…'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('miniPlayer.pill'))).height,
      MiniPlayer.height,
    );

    await rig.hub.channelFor('d1').send(emptyState());
    await settle(tester);
    expect(inMini('Playing on Desk'), findsOneWidget);
    expect(h.player.state.queue, isEmpty);
  });
}
