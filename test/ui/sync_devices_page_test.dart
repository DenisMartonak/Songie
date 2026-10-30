import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/providers.dart';
import 'package:songies/sync/discovery.dart';
import 'package:songies/sync/merger.dart';
import 'package:songies/sync/pairing_code.dart';
import 'package:songies/sync/pairing_service.dart';
import 'package:songies/sync/sync_host.dart';
import 'package:songies/sync/sync_progress.dart';
import 'package:songies/sync/sync_responder.dart';
import 'package:songies/sync/sync_runner.dart';
import 'package:songies/ui/settings/sync/sync_devices_page.dart';

import '../helpers/ui_harness.dart';

/// Always draws [value] (the pairing code's digits).
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final int value;

  @override
  int nextInt(int max) => value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

/// A sync run the test drives.
class _Run {
  _Run(this.peerId, this.choose, this.cancel);
  final String peerId;
  final ChooseClashes choose;
  final SyncCancel? cancel;
  final events = StreamController<SyncProgress>();
}

/// A [SyncHost] with no network: the test sets what it answers.
class _FakeHost implements SyncHost {
  final _devices = StreamController<List<SyncDeviceView>>.broadcast();
  final _responder = StreamController<ResponderState>.broadcast();
  final _runs = StreamController<HostRun>.broadcast(sync: true);
  final _codeLost = StreamController<void>.broadcast();
  List<SyncDeviceView> current = const [];

  int starts = 0;
  int stops = 0;
  bool serving = false;
  bool codeShowing = false;
  final unpaired = <String>[];
  final syncs = <_Run>[];
  FindOutcome findOutcome = FindOutcome.paired;
  final codesTried = <String>[];

  /// The run announced after pairing by code succeeds.
  final pairedRun = StreamController<SyncProgress>();
  final pairedCancel = SyncCancel();

  @override
  ChooseClashes? choose;

  @override
  int? get port => serving ? 47823 : null;

  void setDevices(List<SyncDeviceView> devices) {
    current = devices;
    _devices.add(devices);
  }

  @override
  Stream<List<SyncDeviceView>> get devices => Stream.multi((m) {
    m.add(current);
    final sub = _devices.stream.listen(m.add);
    m.onCancel = sub.cancel;
  });

  @override
  Stream<ResponderState> get responder => _responder.stream;

  @override
  Stream<HostRun> get runs => _runs.stream;

  @override
  Stream<void> get codeLost => _codeLost.stream;

  int codesShown = 0;

  @override
  Future<void> start() async {
    starts++;
    serving = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    serving = false;
  }

  @override
  Future<void> dispose() async {}

  @override
  PairingCode showCode() {
    codeShowing = true;
    codesShown++;
    return PairingCode(random: _FixedRandom(42));
  }

  @override
  void hideCode() => codeShowing = false;

  @override
  Future<FindOutcome> pairByCode(String code) async {
    codesTried.add(code);
    if (findOutcome == FindOutcome.paired) {
      // The host saves the peer, then starts the first sync.
      setDevices([...current, SyncDeviceView(_peer('laptop', 'Laptop'), null)]);
      _runs.add(HostRun('laptop', pairedRun.stream, pairedCancel));
    }
    return findOutcome;
  }

  @override
  Future<PairOutcome> pairByAddress(String host, int port, String code) async =>
      PairOutcome.unreachable;

  @override
  Stream<SyncProgress> sync(
    String peerId, {
    required ChooseClashes choose,
    SyncCancel? cancel,
  }) {
    final run = _Run(peerId, choose, cancel);
    syncs.add(run);
    return run.events.stream;
  }

  @override
  Future<void> unpair(String peerId) async => unpaired.add(peerId);

  @override
  Future<List<String>> localAddresses() async => ['192.168.1.20'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PeerRow _peer(String id, String name, {DateTime? lastSyncAt}) => PeerRow(
  deviceId: id,
  name: name,
  certFingerprint: 'fp',
  pairKey: 'key',
  lastSentSeq: 0,
  lastReceivedSeq: 0,
  lastSyncAt: lastSyncAt,
);

FoundDevice _found(String id, String name) => FoundDevice(
  id: id,
  name: name,
  host: '192.168.1.30',
  port: 47823,
  pairing: false,
);

PlaylistClash _clash(
  String id,
  String? name, {
  bool mineDeleted = false,
  bool theirsDeleted = false,
}) => PlaylistClash(
  playlistId: id,
  name: name,
  mineDeleted: mineDeleted,
  theirsDeleted: theirsDeleted,
  mine: const [],
  theirs: const [],
);

void main() {
  late UiHarness h;
  late _FakeHost host;

  /// Whether the page is on screen (a background tab turns it off).
  late ValueNotifier<bool> visible;

  setUp(() async {
    h = await UiHarness.create();
    host = _FakeHost();
    visible = ValueNotifier(true);
  });
  tearDown(() => h.dispose());

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(800, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings/sync',
        extraOverrides: [syncHostProvider.overrideWith((ref) => host)],
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: Text('Settings')),
            routes: [
              GoRoute(
                path: 'sync',
                builder: (_, _) => Scaffold(
                  body: ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, on, child) =>
                        TickerMode(enabled: on, child: child!),
                    child: const SyncDevicesPage(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
  }

  void pairedDevices() => host.setDevices([
    SyncDeviceView(
      _peer('laptop', 'Laptop', lastSyncAt: DateTime(2026, 10, 21, 9, 5)),
      _found('laptop', 'Laptop'),
    ),
    SyncDeviceView(_peer('phone', 'Phone'), null),
  ]);

  uiTest('shows paired devices with online state', (tester) async {
    pairedDevices();
    await pumpPage(tester);

    expect(host.starts, 1);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Last synced 2026-10-21 09:05'), findsOneWidget);
    expect(find.byKey(const Key('sync.device.laptop.online')), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Never synced'), findsOneWidget);
    expect(find.byKey(const Key('sync.device.phone.offline')), findsOneWidget);
    expect(
      find.text('The other device needs Sync devices open too.'),
      findsOneWidget,
    );
  });

  uiTest('works at phone width', (tester) async {
    pairedDevices();
    await pumpPage(tester, size: const Size(360, 1600));
    expect(tester.takeException(), isNull);
    expect(find.text('Show a code'), findsOneWidget);
    expect(find.text('Enter a code'), findsOneWidget);
  });

  uiTest('tapping a device syncs and Cancel cancels', (tester) async {
    pairedDevices();
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('sync.device.laptop')));
    await settle(tester);
    expect(host.syncs.single.peerId, 'laptop');

    host.syncs.single.events.add(
      const SyncStep(SyncStage.files, done: 3, total: 12),
    );
    await settle(tester);
    expect(find.text('Copying files 3 of 12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync.cancel')));
    await settle(tester);
    expect(host.syncs.single.cancel!.isCancelled, isTrue);
  });

  uiTest('not found offers Try again', (tester) async {
    pairedDevices();
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('sync.device.phone')));
    await settle(tester);
    host.syncs.single.events.add(const SyncFailed(SyncFailure.notFound));
    await settle(tester);
    expect(find.text('Not found. Open Sync devices on Phone.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync.retry')));
    await settle(tester);
    expect(host.syncs, hasLength(2));
    expect(host.syncs.last.peerId, 'phone');
  });

  uiTest('the responder shows who it is waiting for', (tester) async {
    pairedDevices();
    await pumpPage(tester);

    host._responder.add(const WaitingFor('Laptop'));
    await settle(tester);
    expect(find.text('Waiting for Laptop…'), findsOneWidget);

    host._responder.add(const Receiving(SyncStage.applying, 0, 0));
    await settle(tester);
    expect(find.text('Saving'), findsOneWidget);
  });

  uiTest('show a code shows it with its addresses', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Show a code'));
    await settle(tester);
    expect(host.codeShowing, isTrue);
    expect(find.text('000042'), findsOneWidget);
    expect(find.text('192.168.1.20:47823'), findsOneWidget);
    expect(find.textContaining('5:00'), findsOneWidget);

    // Pairing here closes the sheet.
    host.setDevices([SyncDeviceView(_peer('laptop', 'Laptop'), null)]);
    await settle(tester);
    expect(find.text('000042'), findsNothing);
    expect(host.codeShowing, isFalse);
  });

  uiTest('a code lost when the host stopped shows as expired', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Show a code'));
    await settle(tester);
    expect(find.textContaining('5:00'), findsOneWidget);

    host._codeLost.add(null);
    await settle(tester);
    expect(find.textContaining('Expires in'), findsNothing);
    final shown = tester.widget<Text>(find.byKey(const Key('sync.code.shown')));
    expect(shown.style?.decoration, TextDecoration.lineThrough);

    await tester.tap(find.byKey(const Key('sync.code.again')));
    await settle(tester);
    expect(host.codesShown, 2);
    expect(find.textContaining('5:00'), findsOneWidget);
    expect(find.byKey(const Key('sync.code.again')), findsNothing);
  });

  uiTest('enter code success starts a sync and shows the summary', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Enter a code'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('sync.code.field')), '123456');
    await settle(tester);
    await tester.tap(find.byKey(const Key('sync.code.pair')));
    await settle(tester);

    expect(host.codesTried, ['123456']);
    expect(find.byKey(const Key('sync.code.field')), findsNothing);
    expect(host.choose, isNotNull);

    // The first sync asks about clashes on this page, naming the new peer.
    final answer = host.choose!([_clash('p1', 'Road trip')]);
    await settle(tester);
    expect(find.text("Keep Laptop's"), findsOneWidget);
    await tester.tap(find.text("Keep this device's"));
    await settle(tester);
    expect(await answer, {'p1': Resolution.keepMine});

    host.pairedRun.add(const SyncStep(SyncStage.pulling));
    await settle(tester);
    expect(find.text('Fetching changes'), findsOneWidget);

    host.pairedRun.add(
      const SyncDone(
        SyncSummary(
          peerName: 'Laptop',
          playlistsChanged: 3,
          songsAdded: 41,
          filesCopied: 12,
        ),
      ),
    );
    await settle(tester);
    expect(
      find.text(
        'Synced with Laptop: 3 playlists changed, 41 songs added, '
        '12 files copied.',
      ),
      findsOneWidget,
    );
  });

  uiTest('none found offers connect by address', (tester) async {
    host.findOutcome = FindOutcome.noneFound;
    await pumpPage(tester);

    await tester.tap(find.text('Enter a code'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('sync.code.field')), '123456');
    await settle(tester);
    await tester.tap(find.byKey(const Key('sync.code.pair')));
    await settle(tester);

    expect(
      find.text(
        'No device showing that code was found. Check the code, and that '
        'both devices are on the same Wi-Fi.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Connect by address'));
    await settle(tester);
    expect(find.byKey(const Key('sync.address.host')), findsOneWidget);
    expect(find.byKey(const Key('sync.address.port')), findsOneWidget);
  });

  uiTest('clash dialog hides keep both when theirs is deleted', (tester) async {
    pairedDevices();
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('sync.device.laptop')));
    await settle(tester);

    final answer = host.syncs.single.choose([
      _clash('p1', 'Road trip', theirsDeleted: true),
      _clash('p2', null),
    ]);
    await settle(tester);
    expect(find.text('Road trip'), findsOneWidget);
    expect(
      find.text('Deleted on Laptop, changed on this device'),
      findsOneWidget,
    );
    expect(find.text("Keep this device's"), findsOneWidget);
    expect(find.text("Keep Laptop's"), findsOneWidget);
    expect(find.text('Keep both'), findsNothing);

    await tester.tap(find.text("Keep Laptop's"));
    await settle(tester);
    // The next clash, in turn; its name is unknown.
    expect(find.text('Changed on both devices'), findsOneWidget);
    expect(find.text('Keep both'), findsOneWidget);
    await tester.tap(find.text('Keep both'));
    await settle(tester);

    expect(await answer, {
      'p1': Resolution.keepTheirs,
      'p2': Resolution.keepBoth,
    });
  });

  uiTest('dismissing the clash dialog leaves the sync', (tester) async {
    pairedDevices();
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('sync.device.laptop')));
    await settle(tester);

    final answer = host.syncs.single.choose([
      _clash('p1', 'Road trip', mineDeleted: true),
    ]);
    await settle(tester);
    expect(
      find.text('Deleted on this device, changed on Laptop'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(await answer, isNull);
  });

  uiTest('leaving during choices cancels', (tester) async {
    pairedDevices();
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('sync.device.laptop')));
    await settle(tester);

    final run = host.syncs.single;
    final answer = run.choose([_clash('p1', 'Road trip')]);
    await settle(tester);
    expect(find.text('Changed on both devices'), findsOneWidget);

    GoRouter.of(tester.element(find.byType(SyncDevicesPage))).go('/settings');
    await settle(tester);

    expect(find.byType(SyncDevicesPage), findsNothing);
    expect(find.text('Changed on both devices'), findsNothing);
    expect(await answer, isNull);
    expect(run.cancel!.isCancelled, isTrue);
    expect(host.choose, isNull);
  });

  uiTest('linux shows firewall commands', (tester) async {
    h.isLinux = true;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPage(tester);

    const commands =
        'sudo firewall-cmd --permanent --add-port=47823/tcp\n'
        'sudo firewall-cmd --permanent --add-service=mdns\n'
        'sudo firewall-cmd --reload';
    expect(find.text(commands), findsOneWidget);
    await tester.tap(find.byKey(const Key('sync.firewall.copy')));
    await settle(tester);
    expect(copied, commands);
    expect(find.textContaining('Windows may ask'), findsNothing);
  });

  uiTest('windows shows the firewall note', (tester) async {
    h.isWindows = true;
    await pumpPage(tester);
    expect(
      find.text(
        'Windows may ask to allow Songies on private networks. Allow it.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('firewall-cmd'), findsNothing);
  });

  uiTest('unpair asks first', (tester) async {
    pairedDevices();
    await pumpPage(tester);

    Future<void> openUnpair() async {
      await tester.tap(find.byKey(const Key('sync.device.laptop.menu')));
      await settle(tester);
      await tester.tap(find.text('Unpair'));
      await settle(tester);
    }

    await openUnpair();
    expect(find.text('Unpair Laptop?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(host.unpaired, isEmpty);

    await openUnpair();
    await tester.tap(find.byKey(const Key('sync.unpair.confirm')));
    await settle(tester);
    expect(host.unpaired, ['laptop']);
  });

  uiTest('the device name can be changed', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('sync.deviceName.edit')));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Den laptop');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Den laptop'), findsOneWidget);
  });

  group('serving only while visible', () {
    Future<void> hide(WidgetTester tester, bool hidden) async {
      visible.value = !hidden;
      await settle(tester);
    }

    uiTest('hidden stops and visible starts again', (tester) async {
      await pumpPage(tester);
      expect(host.starts, 1);
      expect(host.stops, 0);

      await hide(tester, true);
      expect(host.stops, 1);
      expect(host.serving, isFalse);

      await hide(tester, false);
      expect(host.starts, 2);
      expect(host.serving, isTrue);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('sync.showCode')))
            .enabled,
        isTrue,
      );
    });

    uiTest('hidden during a run stops after the run', (tester) async {
      pairedDevices();
      await pumpPage(tester);
      await tester.tap(find.byKey(const Key('sync.device.laptop')));
      await settle(tester);

      await hide(tester, true);
      expect(host.stops, 0);

      host.syncs.single.events.add(
        const SyncDone(
          SyncSummary(
            peerName: 'Laptop',
            playlistsChanged: 0,
            songsAdded: 0,
            filesCopied: 0,
          ),
        ),
      );
      await settle(tester);
      expect(host.stops, 1);
    });

    uiTest('hidden while a peer syncs here stops when it is done', (
      tester,
    ) async {
      await pumpPage(tester);
      host._responder.add(const WaitingFor('Laptop'));
      await settle(tester);

      await hide(tester, true);
      expect(host.stops, 0);

      host._responder.add(
        const ResponderDone(
          SyncSummary(
            peerName: 'Laptop',
            playlistsChanged: 0,
            songsAdded: 0,
            filesCopied: 0,
          ),
        ),
      );
      await settle(tester);
      expect(host.stops, 1);
    });

    uiTest('an open pairing sheet keeps serving until it closes', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.text('Show a code'));
      await settle(tester);

      await hide(tester, true);
      expect(host.stops, 0);

      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(host.stops, 1);
    });
  });

  uiTest('pairing is off while a sync runs here', (tester) async {
    pairedDevices();
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('sync.device.laptop')));
    await settle(tester);

    bool enabled(String key) =>
        tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;
    expect(enabled('sync.showCode'), isFalse);
    expect(enabled('sync.enterCode'), isFalse);

    host.syncs.single.events.add(const SyncFailed(SyncFailure.network));
    await settle(tester);
    expect(enabled('sync.showCode'), isTrue);
  });

  uiTest('leaving closes the rename dialog', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('sync.deviceName.edit')));
    await settle(tester);
    expect(find.text('Device name'), findsOneWidget);

    GoRouter.of(tester.element(find.byType(SyncDevicesPage))).go('/settings');
    await settle(tester);
    expect(find.text('Device name'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
