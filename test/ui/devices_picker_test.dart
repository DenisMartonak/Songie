import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/remote/remote_protocol.dart';
import 'package:songies/ui/remote/devices_button.dart';
import 'package:songies/ui/remote/remote_islands.dart';
import 'package:songies/ui/remote/remote_strip.dart';

import '../helpers/fake_remote_hub.dart';
import '../helpers/ui_harness.dart';

RemotePresence _device(
  String id, {
  String? title,
  bool playing = false,
  int v = kRemoteProtocol,
}) => RemotePresence(
  deviceId: id,
  name: 'Device $id',
  platform: 'linux',
  appVersion: '1.0.0',
  playing: playing,
  title: title,
  v: v,
);

SignedIn _signedIn(String id) =>
    SignedIn(Profile(id: id, username: 'user$id', email: '$id@example.com'));

void main() {
  late UiHarness h;
  late FakeRemoteHub hub;
  late StreamController<AccountState> account;
  late AccountState current;
  // Whether 'o' answers a hello, which makes the link connected.
  late bool answers;

  setUp(() async {
    h = await UiHarness.create();
    hub = FakeRemoteHub();
    account = StreamController<AccountState>.broadcast();
    current = _signedIn('u1');
    answers = true;
  });
  tearDown(() async {
    await account.close();
    await h.dispose();
  });

  Future<void> join(RemotePresence p) async {
    final channel = hub.channelFor(p.deviceId);
    await channel.join(p);
    channel.messages.listen((m) {
      if (m is RemoteHello && m.to == p.deviceId && answers) {
        channel.send(
          RemoteState(
            from: p.deviceId,
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
          ),
        );
      }
    });
  }

  Future<void> pump(WidgetTester tester, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<Override> overrides = [
      accountStateProvider.overrideWith(
        (ref) => Stream<AccountState>.multi((c) {
          c.addSync(current);
          final sub = account.stream.listen(c.addSync);
          c.onCancel = sub.cancel;
        }),
      ),
      remoteChannelProvider.overrideWithValue(
        (userId) => hub.channelFor(h.stamp.deviceId),
      ),
      remoteDeviceNameProvider.overrideWith((ref) async => 'This PC'),
    ];
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: overrides,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: RemoteEndedIslands(
                child: Column(children: [DevicesButton(), RemoteStrip()]),
              ),
            ),
          ),
        ],
      ),
    );
    await flush(tester);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('devices.button')));
    await settle(tester);
  }

  Future<void> pick(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('devices.device.$id')));
    await tester.pump();
    await flush(tester);
  }

  testWidgets('no button when signed out', (tester) async {
    current = const SignedOut();
    await join(_device('o'));
    await pump(tester);
    expect(find.byKey(const Key('devices.button')), findsNothing);
  });

  testWidgets('lists online devices and This device', (tester) async {
    await join(_device('o', title: 'Some song', playing: true));
    await join(_device('p'));
    await pump(tester);
    await open(tester);
    expect(find.text('This device'), findsOneWidget);
    expect(find.byKey(const Key('devices.thisDevice.check')), findsOneWidget);
    expect(find.text('Device o'), findsOneWidget);
    expect(find.text('Some song'), findsOneWidget);
    expect(find.text('Device p'), findsOneWidget);
  });

  testWidgets('none online says No other devices online', (tester) async {
    await pump(tester);
    await open(tester);
    expect(find.text('No other devices online'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
  });

  testWidgets('an old version is greyed with Update Songies to control this '
      'device', (tester) async {
    await join(_device('o', v: kRemoteProtocol + 1));
    await pump(tester);
    await open(tester);
    expect(find.text('Update Songies to control this device'), findsOneWidget);
    await tester.tap(find.byKey(const Key('devices.device.o')));
    await settle(tester);
    // Disabled: nothing was selected and the menu is still open.
    expect(find.text('Connecting to Device o…'), findsNothing);
    expect(find.text('Update Songies to control this device'), findsOneWidget);
  });

  testWidgets('picking a device shows Connecting then Playing on <device>', (
    tester,
  ) async {
    answers = false;
    await join(_device('o'));
    await pump(tester);
    await open(tester);
    await pick(tester, 'o');
    await settle(tester);
    expect(find.text('Connecting to Device o…'), findsOneWidget);
    answers = true;
    // The device answers a new hello only; drive its state by hand.
    await hub
        .channelFor('o')
        .send(
          RemoteState(
            from: 'o',
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
          ),
        );
    await flush(tester);
    await settle(tester);
    expect(find.text('Playing on Device o'), findsOneWidget);
    expect(find.text('Connecting to Device o…'), findsNothing);
  });

  testWidgets('This device returns', (tester) async {
    await join(_device('o'));
    await pump(tester, width: 400);
    await open(tester);
    await pick(tester, 'o');
    await settle(tester);
    expect(find.text('Playing on Device o'), findsOneWidget);

    await open(tester);
    // On a phone the picker is a bottom sheet.
    expect(find.byKey(const Key('devices.sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('devices.thisDevice')));
    await settle(tester);
    expect(find.text('Playing on Device o'), findsNothing);
    expect(find.byKey(const Key('remote.strip')), findsNothing);
  });

  testWidgets('tapping the strip opens the picker', (tester) async {
    await join(_device('o'));
    await pump(tester);
    await open(tester);
    await pick(tester, 'o');
    await settle(tester);
    await tester.tap(find.byKey(const Key('remote.strip')));
    await settle(tester);
    expect(find.byKey(const Key('devices.thisDevice')), findsOneWidget);
  });

  testWidgets('no answer shows the island', (tester) async {
    answers = false;
    await join(_device('o'));
    await pump(tester);
    await open(tester);
    await pick(tester, 'o');
    await tester.pump(const Duration(seconds: 6));
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Device o didn't answer"), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('lost shows the strip text and then the island', (tester) async {
    await join(_device('o'));
    await pump(tester);
    await open(tester);
    await pick(tester, 'o');
    await settle(tester);
    hub.drop('o');
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Lost connection to Device o'), findsOneWidget);
    expect(find.byKey(const Key('remote.strip')), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 500));
    // The link has ended: the island tells it; the strip is gone.
    expect(find.byKey(const Key('remote.strip')), findsNothing);
    expect(find.text('Lost connection to Device o'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('the island still shows after sign-out and sign-in', (
    tester,
  ) async {
    answers = false;
    await join(_device('o'));
    await pump(tester);
    await open(tester);
    await pick(tester, 'o');
    await tester.pump(const Duration(seconds: 6));
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Device o didn't answer"), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await settle(tester);
    expect(find.text("Device o didn't answer"), findsNothing);

    account.add(const SignedOut());
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
    account.add(_signedIn('u1'));
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));

    await open(tester);
    await pick(tester, 'o');
    await tester.pump(const Duration(seconds: 6));
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Device o didn't answer"), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('picking after the link ended under the open picker works', (
    tester,
  ) async {
    await join(_device('o'));
    await join(_device('p'));
    await pump(tester);
    await open(tester);
    await pick(tester, 'o');
    await settle(tester);
    hub.drop('o');
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('remote.strip')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('devices.thisDevice')), findsOneWidget);
    // The link ends and the strip (which opened the picker) goes.
    await tester.pump(const Duration(seconds: 16));
    expect(find.byKey(const Key('remote.strip')), findsNothing);
    expect(find.byKey(const Key('devices.thisDevice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('devices.device.p')));
    await tester.pump();
    await flush(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Playing on Device p'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('picking after the account changed does nothing', (tester) async {
    await join(_device('o'));
    await pump(tester);
    await open(tester);
    account.add(const SignedOut());
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('devices.device.o')), findsOneWidget);
    await tester.tap(find.byKey(const Key('devices.device.o')));
    await tester.pump();
    await flush(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('remote.strip')), findsNothing);
  });
}
