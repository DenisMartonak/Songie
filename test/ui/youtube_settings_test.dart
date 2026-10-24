import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/ui/settings/youtube_settings.dart';

import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => Scaffold(
              body: ListView(children: const [YouTubeSettingsSection()]),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<bool?> stored(WidgetTester tester, String key) =>
      real(tester, () async {
        final v = await SettingsRepository(h.db).getString(key);
        return v == null ? null : v == '1';
      });

  uiTest('Settings has a YouTube section', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        extraOverrides: [
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
        ],
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: SettingsPage()),
          ),
        ],
      ),
    );
    await settle(tester);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('yt-dlp version: 2026.10.21'), findsOneWidget);
  });

  uiTest('shows the installed version and offers Update', (tester) async {
    await pumpSection(tester);
    expect(find.text('yt-dlp version: 2026.10.21'), findsOneWidget);
    expect(find.text('Update yt-dlp'), findsOneWidget);
    expect(find.text('Install yt-dlp'), findsNothing);
  });

  uiTest('desktop without yt-dlp offers Install', (tester) async {
    h.ytRunner.versionResult = null;
    await pumpSection(tester);
    expect(find.text('yt-dlp version: not installed'), findsOneWidget);
    expect(find.text('Install yt-dlp'), findsOneWidget);
  });

  uiTest('Android only ever offers Update', (tester) async {
    h.isAndroid = true;
    h.ytRunner.versionResult = null;
    await pumpSection(tester);
    expect(find.text('Update yt-dlp'), findsOneWidget);
    expect(find.text('Install yt-dlp'), findsNothing);
  });

  uiTest('Update reports the new version', (tester) async {
    await pumpSection(tester);
    h.ytRunner.versionResult = '2026.11.01';
    await tester.tap(find.text('Update yt-dlp'));
    await settle(tester);

    expect(h.ytRunner.updateCalls, 1);
    expect(find.text('yt-dlp updated to 2026.11.01'), findsOneWidget);
    expect(find.text('yt-dlp version: 2026.11.01'), findsOneWidget);
  });

  uiTest('a failed update shows the error', (tester) async {
    h.ytRunner.updateResult = const Err(
      Failure(FailureKind.network, 'Could not download yt-dlp'),
    );
    await pumpSection(tester);
    await tester.tap(find.text('Update yt-dlp'));
    await settle(tester);

    expect(find.text('Could not download yt-dlp'), findsOneWidget);
  });

  uiTest('Wi-Fi only moved to the Downloads section', (tester) async {
    await pumpSection(tester);
    expect(find.textContaining('Wi-Fi only'), findsNothing);
  });

  uiTest('the system yt-dlp toggle is hidden off Linux', (tester) async {
    await pumpSection(tester);
    expect(find.text('Use system yt-dlp'), findsNothing);
  });

  uiTest('on Linux the system yt-dlp toggle writes its setting', (
    tester,
  ) async {
    h.isLinux = true;
    await pumpSection(tester);
    final tile = find.widgetWithText(SwitchListTile, 'Use system yt-dlp');
    expect(tile, findsOneWidget);
    expect(find.text('Takes effect after restart'), findsOneWidget);

    await tester.tap(tile);
    await settle(tester);
    expect(await stored(tester, kYtdlpUseSystem), isTrue);
  });
}
