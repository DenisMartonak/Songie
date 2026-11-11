import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/app.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/motion/motion.dart';
import 'package:songies/update/release.dart';
import 'package:songies/update/update_checker.dart';
import 'package:songies/update/update_controller.dart';
import 'package:songies/update/update_downloader.dart';
import 'package:songies/update/update_installer.dart' as inst;

import '../helpers/fake_network_status.dart';
import '../helpers/fake_updater.dart';
import '../helpers/test_db.dart';

void main() {
  late FakeUpdateChecker checker;
  late FakeUpdateDownloader downloader;
  late FakeUpdateInstaller installer;
  late FakeNetworkStatus network;
  late List<Uri> opened;
  late FakeUpdateNotifications notifications;

  setUp(() {
    notifications = FakeUpdateNotifications();
    checker = FakeUpdateChecker();
    downloader = FakeUpdateDownloader();
    installer = FakeUpdateInstaller();
    network = FakeNetworkStatus();
    opened = [];
  });

  List<Override> updateOverrides({
    bool isAndroid = false,
    Duration? timeout,
    bool supported = true,
  }) => [
    updateCheckerProvider.overrideWithValue(supported ? checker : null),
    updateDownloaderProvider.overrideWithValue(downloader),
    inst.updateInstallerProvider.overrideWithValue(installer),
    networkStatusProvider.overrideWithValue(network),
    isAndroidProvider.overrideWithValue(isAndroid),
    openDownloadPageProvider.overrideWithValue((u) async => opened.add(u)),
    if (timeout != null) updateCheckTimeoutProvider.overrideWithValue(timeout),
    updateNotificationsProvider.overrideWithValue(notifications),
  ];

  group('controller', () {
    late AppDatabase db;
    late SettingsRepository settings;

    setUp(() {
      db = testDb();
      settings = SettingsRepository(db);
    });
    tearDown(() => db.close());

    ProviderContainer make({bool isAndroid = false, Duration? timeout}) {
      final c = ProviderContainer(
        overrides: [
          ...updateOverrides(isAndroid: isAndroid, timeout: timeout),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    UpdateController ctl(ProviderContainer c) =>
        c.read(updateControllerProvider.notifier);

    test('starts idle', () {
      expect(make().read(updateControllerProvider), isA<Idle>());
    });

    test(
      'startup goes to Available only when an update is available',
      () async {
        final c = make();
        checker.onStartup = () async => availableFor(testRelease);
        await ctl(c).startup();
        final s = c.read(updateControllerProvider);
        expect(s, isA<Available>());
        expect((s as Available).release.version, testRelease.version);
        expect(s.asset.name, 'songies-1.1.0-x86_64.AppImage');
      },
    );

    for (final (name, answer) in [
      ('up to date', const UpToDate() as UpdateCheck?),
      ('throttled or skipped', null),
      ('failed', CheckFailed(const SocketException('offline'))),
    ]) {
      test('startup stays idle when $name', () async {
        final c = make();
        checker.onStartup = () async => answer;
        await ctl(c).startup();
        expect(c.read(updateControllerProvider), isA<Idle>());
      });
    }

    test('startup swallows a checker that throws', () async {
      final c = make();
      checker.onStartup = () async => throw StateError('boom');
      await ctl(c).startup();
      expect(c.read(updateControllerProvider), isA<Idle>());
    });

    test('startup offline or slow shows nothing and does not block', () async {
      final c = make(timeout: const Duration(milliseconds: 50));
      final never = Completer<UpdateCheck?>();
      checker.onStartup = () => never.future;
      final sw = Stopwatch()..start();
      await ctl(c).startup();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(c.read(updateControllerProvider), isA<Idle>());
    });

    test('the check gives up after about 15 s by default', () {
      expect(
        make().read(updateCheckTimeoutProvider),
        const Duration(seconds: 15),
      );
    });

    test('startup does nothing on an unsupported platform', () async {
      final c = ProviderContainer(
        overrides: [
          ...updateOverrides(supported: false),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(c.dispose);
      await c.read(updateControllerProvider.notifier).startup();
      expect(c.read(updateControllerProvider), isA<Idle>());
    });

    test('a late startup answer does not override a manual check', () async {
      final c = make();
      final late = Completer<UpdateCheck?>();
      checker.onStartup = () => late.future;
      checker.onNow = () async => const UpToDate();
      final startup = ctl(c).startup();
      await ctl(c).checkNow();
      late.complete(availableFor(testRelease));
      await startup;
      expect(c.read(updateControllerProvider), isA<NoUpdate>());
    });

    test(
      'checkNow: Checking, then NoUpdate / CheckError / Available',
      () async {
        final c = make();
        final seen = <UpdateState>[];
        c.listen(updateControllerProvider, (_, s) => seen.add(s));

        await ctl(c).checkNow();
        expect(seen.first, isA<Checking>());
        expect(c.read(updateControllerProvider), isA<NoUpdate>());

        checker.onNow = () async => CheckFailed(const SocketException('x'));
        await ctl(c).checkNow();
        expect(c.read(updateControllerProvider), isA<CheckError>());

        checker.onNow = () async => availableFor(testRelease);
        await ctl(c).checkNow();
        expect(c.read(updateControllerProvider), isA<Available>());
      },
    );

    test('checkNow times out as a connection error', () async {
      final c = make(timeout: const Duration(milliseconds: 50));
      checker.onNow = () => Completer<UpdateCheck>().future;
      await ctl(c).checkNow();
      expect(c.read(updateControllerProvider), isA<CheckError>());
    });

    test('not now skips the version', () async {
      final c = make();
      checker.onStartup = () async => availableFor(testRelease);
      await ctl(c).startup();
      ctl(c).notNow();
      await pumpEventQueue();
      expect(checker.skipped, [testRelease.version]);
      // The background check (Android notification) stays quiet about it too.
      expect(notifications.skipped, [testRelease.version]);
      expect(c.read(updateControllerProvider), isA<Idle>());
    });

    test('manual only offers the download page', () async {
      final c = make();
      installer.selfUpdate = false;
      checker.onNow = () async => availableFor(testRelease);
      await ctl(c).checkNow();
      final s = c.read(updateControllerProvider);
      expect(s, isA<ManualOnly>());
      expect((s as ManualOnly).htmlUrl, testRelease.htmlUrl);

      await ctl(c).openDownloadPage();
      expect(opened, [testRelease.htmlUrl]);
      expect(downloader.calls, 0);
    });

    test('a release without an https page link opens nothing', () async {
      final c = make();
      installer.selfUpdate = false;
      final r = Release(
        version: testRelease.version,
        notes: '',
        htmlUrl: Uri(),
        assets: testRelease.assets,
      );
      checker.onNow = () async => availableFor(r);
      await ctl(c).checkNow();
      expect(c.read(updateControllerProvider), isA<ManualOnly>());
      await ctl(c).openDownloadPage();
      expect(opened, isEmpty);
    });

    test('accept downloads then installs', () async {
      final c = make();
      checker.onNow = () async => availableFor(testRelease);
      await ctl(c).checkNow();
      final seen = <UpdateState>[];
      c.listen(updateControllerProvider, (_, s) => seen.add(s));

      await ctl(c).accept();
      expect(
        [for (final d in seen.whereType<Downloading>()) (d.received, d.total)],
        [(0, 10), (5, 10)],
      );
      final ready = c.read(updateControllerProvider);
      expect(ready, isA<ReadyToInstall>());
      expect(installer.installs, isEmpty, reason: 'asks before installing');

      await ctl(c).installNow();
      expect(installer.installs, [downloader.file]);
      expect(c.read(updateControllerProvider), isA<Installing>());
    });

    test(
      'a desktop install that never returns is already Installing',
      () async {
        final c = make();
        installer.onInstall = () => Completer<inst.InstallOutcome>().future;
        checker.onNow = () async => availableFor(testRelease);
        await ctl(c).checkNow();
        await ctl(c).accept();
        unawaited(ctl(c).installNow());
        await pumpEventQueue();
        expect(installer.installs, hasLength(1));
        expect(c.read(updateControllerProvider), isA<Installing>());
      },
    );

    test('checksum failure shows Failed and installs nothing', () async {
      final c = make();
      downloader.onDownload = (_) => Stream.fromIterable([
        const DownloadProgress(5, 10),
        const DownloadFailed(DownloadError.checksumMismatch, 10, 10),
      ]);
      checker.onNow = () async => availableFor(testRelease);
      await ctl(c).checkNow();
      await ctl(c).accept();
      final s = c.read(updateControllerProvider);
      expect(s, isA<Failed>());
      expect((s as Failed).message, isNot(contains('/')));
      await ctl(c).installNow();
      expect(installer.installs, isEmpty);
    });

    test('a cut download shows a connection message', () async {
      final c = make();
      downloader.onDownload = (_) =>
          Stream.value(const DownloadFailed(DownloadError.network));
      checker.onNow = () async => availableFor(testRelease);
      await ctl(c).checkNow();
      await ctl(c).accept();
      expect(
        (c.read(updateControllerProvider) as Failed).message,
        "Couldn't download the update. Check your connection.",
      );
    });

    test('cancel stops the download and goes back to Available', () async {
      final c = make();
      final ctrl = StreamController<DownloadProgress>();
      downloader.onDownload = (_) => ctrl.stream;
      checker.onNow = () async => availableFor(testRelease);
      await ctl(c).checkNow();
      final accepted = ctl(c).accept();
      ctrl.add(const DownloadProgress(1, 10));
      await pumpEventQueue();
      expect(c.read(updateControllerProvider), isA<Downloading>());
      ctl(c).cancel();
      expect(downloader.lastCancel!.isCancelled, isTrue);
      expect(c.read(updateControllerProvider), isA<Available>());
      // The real downloader then reports the cancel and ends.
      ctrl
        ..add(const DownloadFailed(DownloadError.cancelled))
        ..close();
      await accepted;
      expect(c.read(updateControllerProvider), isA<Available>());
      expect(installer.installs, isEmpty);
    });

    group('install outcomes', () {
      Future<ProviderContainer> ready(inst.InstallOutcome outcome) async {
        final c = make();
        installer.onInstall = () async => outcome;
        checker.onNow = () async => availableFor(testRelease);
        await ctl(c).checkNow();
        await ctl(c).accept();
        await ctl(c).installNow();
        return c;
      }

      test('NeedsPermission opens the permission screen on request', () async {
        final c = await ready(const inst.NeedsPermission());
        expect(c.read(updateControllerProvider), isA<NeedsPermission>());
        await ctl(c).openPermissionSettings();
        expect(installer.permissionOpens, 1);
        // Trying again installs the same file.
        installer.onInstall = () async => const inst.Installing();
        await ctl(c).installNow();
        expect(installer.installs, [downloader.file, downloader.file]);
      });

      test('Rejected and InstallFailed show a plain message', () async {
        for (final o in [
          const inst.Rejected('the update is not signed'),
          inst.InstallFailed(
            const FileSystemException('denied', '/home/u/x.AppImage'),
          ),
        ]) {
          final c = await ready(o);
          final s = c.read(updateControllerProvider);
          expect(s, isA<Failed>());
          expect((s as Failed).message, isNot(contains('/home')));
          expect(s.message, isNot(contains('signed')));
        }
      });

      test('Android: backing out of the system installer can retry', () async {
        final c = make(isAndroid: true);
        checker.onNow = () async => availableFor(testRelease);
        await ctl(c).checkNow();
        await ctl(c).accept();
        await ctl(c).installNow();
        expect(c.read(updateControllerProvider), isA<Installing>());
        // The user backed out; the verified file is still there.
        await ctl(c).installNow();
        expect(installer.installs, [downloader.file, downloader.file]);
      });

      test('desktop: Installing does not start a second install', () async {
        final c = await ready(const inst.Installing());
        expect(c.read(updateControllerProvider), isA<Installing>());
        await ctl(c).installNow();
        expect(installer.installs, [downloader.file]);
      });

      test('CannotReplace offers the download page', () async {
        final c = await ready(const inst.CannotReplace());
        final s = c.read(updateControllerProvider);
        expect((s as ManualOnly).htmlUrl, testRelease.htmlUrl);
      });
    });

    group('wifi only on mobile data waits and offers download anyway', () {
      test('on Android with the default setting', () async {
        final c = make(isAndroid: true);
        network.kind = NetworkKind.mobile;
        checker.onNow = () async => availableFor(testRelease);
        await ctl(c).checkNow();
        await ctl(c).accept();
        expect(c.read(updateControllerProvider), isA<WaitingForWifi>());
        expect(downloader.calls, 0);

        await ctl(c).downloadAnyway();
        expect(downloader.calls, 1);
        expect(c.read(updateControllerProvider), isA<ReadyToInstall>());
      });

      test('when the network cannot be read, as if on mobile data', () async {
        final c = make(isAndroid: true);
        network.currentError = StateError('no connectivity channel');
        checker.onNow = () async => availableFor(testRelease);
        await ctl(c).checkNow();
        await ctl(c).accept();
        expect(c.read(updateControllerProvider), isA<WaitingForWifi>());
        expect(downloader.calls, 0);
      });

      test('not when Wi-Fi only is off', () async {
        final c = make(isAndroid: true);
        await settings.setBool(kWifiOnly, false);
        network.kind = NetworkKind.mobile;
        checker.onNow = () async => availableFor(testRelease);
        await ctl(c).checkNow();
        await ctl(c).accept();
        expect(downloader.calls, 1);
      });

      test('not on desktop', () async {
        final c = make();
        await settings.setBool(kWifiOnly, true);
        network.kind = NetworkKind.mobile;
        checker.onNow = () async => availableFor(testRelease);
        await ctl(c).checkNow();
        await ctl(c).accept();
        expect(downloader.calls, 1);
      });
    });
  });

  group('app startup', () {
    Future<void> pumpApp(WidgetTester tester) async {
      final states = StreamController<PlayerState>.broadcast();
      addTearDown(states.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...updateOverrides(),
            themeSpecProvider.overrideWithValue(ThemeSpec.builtInDefault),
            resolvedFontFamilyProvider.overrideWithValue(
              ThemeSpec.builtInDefault.fontFamily,
            ),
            playerStateProvider.overrideWith((ref) => states.stream),
            coverPaletteProvider.overrideWith((ref) => Stream.value(null)),
            reduceMotionProvider.overrideWithValue(false),
          ],
          child: SongiesApp(
            checkForUpdates: true,
            router: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => Scaffold(
                    body: TextButton(
                      onPressed: () {},
                      child: const Text('probe'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('startup shows the dialog only when an update is available', (
      tester,
    ) async {
      checker.onStartup = () async => availableFor(testRelease);
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(checker.startupCalls, 0, reason: 'waits 3 s after first frame');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(checker.startupCalls, 1);
      expect(find.text('Songies 1.1.0 is available'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Songies 1.1.0 is available'), findsNothing);
      expect(checker.skipped, [testRelease.version]);
    });

    testWidgets('opened from the update notification: checks right away, '
        'past the 12 h limit', (tester) async {
      notifications.openRequest = true;
      checker.onNow = () async => availableFor(testRelease);
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(checker.nowCalls, 1);
      expect(checker.startupCalls, 0);
      expect(find.text('Songies 1.1.0 is available'), findsOneWidget);
    });

    testWidgets(
      'tapping the notification while Songies runs shows the prompt',
      (tester) async {
        checker.onStartup = () async => const UpToDate();
        checker.onNow = () async => availableFor(testRelease);
        await pumpApp(tester);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.text('Songies 1.1.0 is available'), findsNothing);
        notifications.tap();
        await tester.pumpAndSettle();
        expect(find.text('Songies 1.1.0 is available'), findsOneWidget);
      },
    );

    testWidgets('startup asks for the notification permission', (tester) async {
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(notifications.permissionAsks, 1);
    });

    testWidgets('startup with no update shows nothing and runs once', (
      tester,
    ) async {
      checker.onStartup = () async => const UpToDate();
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(checker.startupCalls, 1);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const Key('island')), findsNothing);
    });

    testWidgets('startup offline or slow shows nothing and does not block', (
      tester,
    ) async {
      checker.onStartup = () => Completer<UpdateCheck?>().future;
      await pumpApp(tester);
      // The app is usable before and during the check.
      expect(find.text('probe'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('probe'));
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(checker.startupCalls, 1);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('probe'), findsOneWidget);
    });

    testWidgets('a hidden download asks to install once it is ready', (
      tester,
    ) async {
      final ctrl = StreamController<DownloadProgress>();
      downloader.onDownload = (_) => ctrl.stream;
      checker.onStartup = () async => availableFor(testRelease);
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update now'));
      ctrl.add(const DownloadProgress(5, 10));
      await tester.pump();
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      ctrl
        ..add(DownloadDone(downloader.file, 10))
        ..close();
      await tester.pumpAndSettle();
      expect(find.text('Install now'), findsOneWidget);
      expect(installer.installs, isEmpty);
    });

    testWidgets('no startup check unless asked for', (tester) async {
      checker.onStartup = () async => availableFor(testRelease);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...updateOverrides(),
            themeSpecProvider.overrideWithValue(ThemeSpec.builtInDefault),
            resolvedFontFamilyProvider.overrideWithValue(
              ThemeSpec.builtInDefault.fontFamily,
            ),
            coverPaletteProvider.overrideWith((ref) => Stream.value(null)),
            reduceMotionProvider.overrideWithValue(false),
          ],
          child: SongiesApp(
            router: GoRouter(
              routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(checker.startupCalls, 0);
    });
  });
}
