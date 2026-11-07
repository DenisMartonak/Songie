import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/remote/remote_protocol.dart';

import 'fake_remote_hub.dart';
import 'ui_harness.dart';

/// A signed-in account on a fake remote hub, for the menus' Play on entries.
class RemoteMenuRig {
  RemoteMenuRig(this.h, {this.signedIn = true});

  final UiHarness h;
  final bool signedIn;
  final hub = FakeRemoteHub();

  /// Pass to `h.app(extraOverrides: ...)`.
  List<Override> get overrides => [
    accountStateProvider.overrideWith(
      (ref) => Stream<AccountState>.value(
        signedIn
            ? const SignedIn(
                Profile(id: 'u1', username: 'user', email: 'u@example.com'),
              )
            : const SignedOut(),
      ),
    ),
    remoteChannelProvider.overrideWithValue(
      (userId) => hub.channelFor(h.stamp.deviceId),
    ),
    remoteDeviceNameProvider.overrideWith((ref) async => 'This PC'),
  ];

  Future<void> join(String id, String name, {int v = kRemoteProtocol}) => hub
      .channelFor(id)
      .join(
        RemotePresence(
          deviceId: id,
          name: name,
          platform: 'linux',
          appVersion: '1.0.0',
          playing: false,
          v: v,
        ),
      );

  /// Keeps the online devices loaded, as the devices button does in the app.
  /// Call after the app is pumped.
  Future<void> watchDevices(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    final sub = container.listen(remoteDevicesProvider, (_, _) {});
    addTearDown(sub.close);
    await flush(tester);
  }

  List<RemoteCommand> get commands =>
      hub.sent.whereType<RemoteCommand>().toList();
}
