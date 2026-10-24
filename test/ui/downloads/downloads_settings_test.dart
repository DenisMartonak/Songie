import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/ui/settings/downloads_settings.dart';
import 'package:songies/ui/settings/storage_usage.dart';

import '../../helpers/test_db.dart';
import '../../helpers/ui_harness.dart';

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
              body: ListView(children: const [DownloadsSettingsSection()]),
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

  /// A YouTube playlist "Mix" of two downloaded songs (1 MB and 2 MB).
  Future<void> downloadedMix(WidgetTester tester) => real(tester, () async {
    for (final (id, mb) in [('y1', 1), ('y2', 2)]) {
      await h.db
          .into(h.db.tracks)
          .insert(trackRow(id: id, source: 'yt', ytVideoId: 'v$id'));
      await h.db
          .into(h.db.localFiles)
          .insert(
            LocalFilesCompanion.insert(
              trackId: id,
              path: '/yt/v$id.webm',
              state: 'done',
              bytes: mb * 1024 * 1024,
              mtimeMs: 0,
            ),
          );
    }
    final pid = await h.addPlaylist('Mix', ['y1', 'y2']);
    await (h.db.update(h.db.playlists)..where((p) => p.id.equals(pid))).write(
      const PlaylistsCompanion(source: Value('yt')),
    );
  });

  uiTest('shows the total and per-playlist sizes with formatBytes', (
    tester,
  ) async {
    await downloadedMix(tester);
    await pumpSection(tester);
    expect(find.text('Downloads'), findsOneWidget);
    expect(
      find.text('Downloaded songs · ${formatBytes(3 * 1024 * 1024)}'),
      findsOneWidget,
    );
    expect(find.text('Downloaded songs · 3.0 MB'), findsOneWidget);
    expect(find.text('Mix · 3.0 MB'), findsOneWidget);
  });

  uiTest('with nothing downloaded the total is 0 B', (tester) async {
    await pumpSection(tester);
    expect(find.text('Downloaded songs · 0 B'), findsOneWidget);
  });

  uiTest('the Wi-Fi only toggle writes wifi_only', (tester) async {
    await pumpSection(tester);
    final tile = find.widgetWithText(SwitchListTile, 'Wi-Fi only');
    expect(tile, findsOneWidget);
    // Desktop default is off.
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.tap(tile);
    await settle(tester);
    expect(await stored(tester, kWifiOnly), isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  uiTest('Wi-Fi only defaults to on for Android', (tester) async {
    h.isAndroid = true;
    await pumpSection(tester);
    final tile = find.widgetWithText(SwitchListTile, 'Wi-Fi only');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  uiTest('Pause and Resume downloads drive the queue', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.text('Pause downloads'));
    await settle(tester);
    expect(h.downloads.calls, ['pauseByUser']);

    await tester.tap(find.text('Resume downloads'));
    await settle(tester);
    expect(h.downloads.calls, ['pauseByUser', 'resumeByUser', 'resume']);
    expect(find.text('Pause downloads'), findsOneWidget);
  });
}
