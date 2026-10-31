import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/app_theme.dart';
import 'package:songies/theme/theme_spec.dart';
import 'package:songies/ui/update/update_dialog.dart';
import 'package:songies/update/update_controller.dart';
import 'package:songies/update/update_downloader.dart';
import 'package:songies/update/update_installer.dart' as inst;

import '../helpers/fake_network_status.dart';
import '../helpers/fake_updater.dart';

/// Settings at their defaults; never touches a database.
class _DefaultSettings implements SettingsRepository {
  @override
  Future<bool> getBool(String key, {required bool fallback}) async => fallback;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeUpdateChecker checker;
  late FakeUpdateDownloader downloader;
  late FakeUpdateInstaller installer;
  late FakeNetworkStatus network;
  late List<Uri> opened;
  late ProviderContainer container;

  setUp(() {
    checker = FakeUpdateChecker()
      ..onNow = () async => availableFor(testRelease);
    downloader = FakeUpdateDownloader();
    installer = FakeUpdateInstaller();
    network = FakeNetworkStatus();
    opened = [];
  });

  /// Checks (so the controller holds [testRelease] or what [checker] says)
  /// and opens the dialog.
  Future<void> pumpDialog(WidgetTester tester, {bool isAndroid = false}) async {
    container = ProviderContainer(
      overrides: [
        updateCheckerProvider.overrideWithValue(checker),
        updateDownloaderProvider.overrideWithValue(downloader),
        inst.updateInstallerProvider.overrideWithValue(installer),
        networkStatusProvider.overrideWithValue(network),
        isAndroidProvider.overrideWithValue(isAndroid),
        settingsRepositoryProvider.overrideWithValue(_DefaultSettings()),
        openDownloadPageProvider.overrideWithValue((u) async => opened.add(u)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildThemeData(ThemeSpec.builtInDefault),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showUpdateDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await container.read(updateControllerProvider.notifier).checkNow();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  UpdateState state() => container.read(updateControllerProvider);

  testWidgets('dialog copy is exact', (tester) async {
    await pumpDialog(tester);
    expect(find.text('Songies 1.1.0 is available'), findsOneWidget);
    expect(find.text('Faster search and a new theme.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update now'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Not now'), findsOneWidget);
    expect(find.text('Open download page'), findsNothing);
  });

  testWidgets('long release notes are cut to about 600 characters', (
    tester,
  ) async {
    final long = List.filled(300, 'word').join(' ');
    checker.onNow = () async => availableFor(releaseWithNotes(long));
    await pumpDialog(tester);
    final shown = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .firstWhere((s) => s.startsWith('word'));
    expect(shown.length, inInclusiveRange(550, 601));
    expect(shown, endsWith('…'));
  });

  testWidgets('not now skips the version and closes', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Songies 1.1.0 is available'), findsNothing);
    expect(checker.skipped, [testRelease.version]);
  });

  testWidgets('manual only offers the download page', (tester) async {
    installer.selfUpdate = false;
    await pumpDialog(tester);
    expect(find.text('Update now'), findsNothing);
    await tester.tap(find.text('Open download page'));
    await tester.pumpAndSettle();
    expect(opened, [testRelease.htmlUrl]);
  });

  testWidgets('wifi only on mobile data waits and offers download anyway', (
    tester,
  ) async {
    network.kind = NetworkKind.mobile;
    await pumpDialog(tester, isAndroid: true);
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(state(), isA<WaitingForWifi>());
    expect(find.textContaining('mobile data'), findsOneWidget);
    expect(downloader.calls, 0);
    await tester.tap(find.text('Download anyway'));
    await tester.pumpAndSettle();
    expect(downloader.calls, 1);
    expect(find.text('Install now'), findsOneWidget);
  });

  testWidgets('downloading shows progress and Cancel; it can be hidden', (
    tester,
  ) async {
    final ctrl = StreamController<DownloadProgress>();
    downloader.onDownload = (_) => ctrl.stream;
    await pumpDialog(tester);
    await tester.tap(find.text('Update now'));
    ctrl.add(const DownloadProgress(5, 10));
    await tester.pump();
    await tester.pump();
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
    expect(find.text('Cancel'), findsOneWidget);

    // Hidden: the download carries on.
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    ctrl
      ..add(DownloadDone(downloader.file, 10))
      ..close();
    await tester.pumpAndSettle();
    expect(state(), isA<ReadyToInstall>());

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();
    expect(installer.installs, [downloader.file]);
  });

  testWidgets('Cancel stops the download', (tester) async {
    final ctrl = StreamController<DownloadProgress>();
    downloader.onDownload = (_) => ctrl.stream;
    await pumpDialog(tester);
    await tester.tap(find.text('Update now'));
    ctrl.add(const DownloadProgress(1, 10));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(downloader.lastCancel!.isCancelled, isTrue);
    expect(find.text('Update now'), findsOneWidget);
    await ctrl.close();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed check of the download shows a plain message', (
    tester,
  ) async {
    downloader.onDownload = (_) => Stream.value(
      const DownloadFailed(DownloadError.checksumMismatch, 10, 10),
    );
    await pumpDialog(tester);
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(state(), isA<Failed>());
    expect(find.text((state() as Failed).message), findsOneWidget);
    expect(find.text('Install now'), findsNothing);
    expect(installer.installs, isEmpty);
  });

  testWidgets('needs permission offers the settings screen', (tester) async {
    installer.onInstall = () async => const inst.NeedsPermission();
    await pumpDialog(tester, isAndroid: true);
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();
    expect(state(), isA<NeedsPermission>());
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(installer.permissionOpens, 1);
  });

  testWidgets('Android Installing offers Install now again after backing out', (
    tester,
  ) async {
    await pumpDialog(tester, isAndroid: true);
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();
    expect(state(), isA<Installing>());
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();
    expect(installer.installs, [downloader.file, downloader.file]);
  });

  testWidgets('desktop Installing shows only Close', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();
    expect(state(), isA<Installing>());
    expect(find.text('Install now'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
}
