import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/log.dart';
import 'package:songies/core/paths.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/providers.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/ui/library/pickers.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';

import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late Directory tmp;

  setUp(() async {
    h = await UiHarness.create();
    tmp = Directory.systemTemp.createTempSync('songies_settings_');
    h.paths = AppPaths.at(tmp);
    await h.paths!.ensureCreated();
    // The logger is global: point it at this test's directory.
    await AppLog.init(h.paths!.logs);
  });
  tearDown(() async {
    await h.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> seedFolders(WidgetTester tester, List<String> paths) =>
      real(tester, () async {
        for (final path in paths) {
          await h.db
              .into(h.db.libraryFolders)
              .insert(LibraryFoldersCompanion.insert(path: path));
        }
      });

  Future<void> pumpSettings(
    WidgetTester tester, {
    StorageUsage usage = const StorageUsage(artBytes: 0, databaseBytes: 0),
    LogSaver? logSaver,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        extraOverrides: [
          storageUsageProvider.overrideWith((ref) async => usage),
          if (logSaver != null) logSaverProvider.overrideWithValue(logSaver),
        ],
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: SettingsPage()),
            routes: [
              GoRoute(
                path: 'themes',
                builder: (_, _) => const Scaffold(body: Text('Themes page')),
              ),
            ],
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Finder rescan(String path) => find.byKey(Key('settings.rescan.$path'));
  Finder remove(String path) => find.byKey(Key('settings.remove.$path'));

  group('music folders', () {
    uiTest('lists each folder; Rescan scans that folder through the queue', (
      tester,
    ) async {
      await seedFolders(tester, ['/music/b', '/music/a']);
      await pumpSettings(tester);

      expect(find.byKey(const Key('settings.folder.row.0')), findsOneWidget);
      expect(find.byKey(const Key('settings.folder.row.1')), findsOneWidget);
      expect(find.byKey(const Key('settings.folder.row.2')), findsNothing);
      // Ordered by path.
      expect(
        tester.getTopLeft(find.text('/music/a')).dy,
        lessThan(tester.getTopLeft(find.text('/music/b')).dy),
      );

      await tester.tap(rescan('/music/a'));
      await settle(tester);
      expect(h.scanner.scannedFolders, ['/music/a']);
      expect(h.scanner.playlistNames, [null]);
    });

    uiTest('tapping Rescan twice queues the folder once while pending', (
      tester,
    ) async {
      final gate = Completer<void>();
      h.scanner.onScan = (folder, _) async* {
        await gate.future;
      };
      await seedFolders(tester, ['/music/a']);
      await pumpSettings(tester);

      await tester.tap(rescan('/music/a'));
      await flush(tester);
      await tester.tap(rescan('/music/a'));
      await flush(tester);
      gate.complete();
      await flush(tester);
      expect(h.scanner.scannedFolders, ['/music/a']);

      // Once finished, it can be queued again.
      await tester.tap(rescan('/music/a'));
      await flush(tester);
      expect(h.scanner.scannedFolders, ['/music/a', '/music/a']);
    });

    uiTest('Rescan all scans every folder, one after the other', (
      tester,
    ) async {
      final first = Completer<void>();
      h.scanner.onScan = (folder, _) async* {
        if (folder == '/music/a') await first.future;
      };
      await seedFolders(tester, ['/music/a', '/music/b']);
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings.rescanAll')));
      await flush(tester);
      expect(h.scanner.scannedFolders, ['/music/a']);

      first.complete();
      await flush(tester);
      expect(h.scanner.scannedFolders, ['/music/a', '/music/b']);
    });

    uiTest('a failed scan says which folder', (tester) async {
      h.scanner.onScan = (folder, _) =>
          Stream.error(const FileSystemException('gone'));
      await seedFolders(tester, ['/music/Rock']);
      await pumpSettings(tester);

      await tester.tap(rescan('/music/Rock'));
      await settle(tester);
      expect(find.text("Couldn't scan Rock"), findsOneWidget);
    });

    uiTest('Rescan all names every folder that fails', (tester) async {
      h.scanner.onScan = (folder, _) =>
          Stream.error(const FileSystemException('gone'));
      await seedFolders(tester, ['/music/Rock', '/music/Jazz']);
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings.rescanAll')));
      await settle(tester);
      // Jazz sorts first; the second snack bar queues behind the first.
      expect(find.text("Couldn't scan Jazz"), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(SettingsPage)))
          .hideCurrentSnackBar();
      await settle(tester);
      expect(find.text("Couldn't scan Rock"), findsOneWidget);
    });

    uiTest('Remove asks first, then forgets the folder but keeps its songs', (
      tester,
    ) async {
      await real(tester, () => h.addTrack('t1'));
      await seedFolders(tester, ['/music/a', '/music/b']);
      await pumpSettings(tester);

      await tester.tap(remove('/music/a'));
      await settle(tester);
      expect(find.text('Remove folder?'), findsOneWidget);

      // Cancelling keeps it.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);
      expect(find.text('/music/a'), findsOneWidget);

      await tester.tap(remove('/music/a'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await settle(tester);

      expect(find.text('/music/a'), findsNothing);
      expect(find.text('/music/b'), findsOneWidget);
      expect(find.byKey(const Key('settings.folder.row.1')), findsNothing);
      final songs = await real(tester, () => h.db.select(h.db.tracks).get());
      expect(songs.map((t) => t.id), ['t1']);
    });

    uiTest('shows when a folder was last scanned', (tester) async {
      await real(tester, () async {
        await h.db
            .into(h.db.libraryFolders)
            .insert(
              LibraryFoldersCompanion.insert(
                path: '/music/a',
                lastScanAt: Value(DateTime(2026, 10, 21, 9, 5)),
              ),
            );
        await h.db
            .into(h.db.libraryFolders)
            .insert(LibraryFoldersCompanion.insert(path: '/music/b'));
      });
      await pumpSettings(tester);

      expect(find.text('Last scanned 2026-10-21 09:05'), findsOneWidget);
      expect(find.text('Not scanned yet'), findsOneWidget);
    });

    uiTest('with no folders it says so', (tester) async {
      await pumpSettings(tester);
      expect(find.text('No music folders yet'), findsOneWidget);
    });

    uiTest('Add folder picks a folder and scans it through the queue', (
      tester,
    ) async {
      h.folderPicker = () async => FolderPicked('/music/New');
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings.addFolder')));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      expect(h.scanner.scannedFolders, ['/music/New']);
      expect(h.scanner.playlistNames, ['New']);
    });
  });

  group('storage', () {
    uiTest('shows the size of the art cache and of the database', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        usage: const StorageUsage(
          artBytes: 12 * 1024 * 1024 + 300 * 1024,
          databaseBytes: 2048,
        ),
      );
      expect(find.text('12.3 MB'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
    });

    test(
      'measureStorage sums art/ and the database with its -wal/-shm',
      () async {
        final paths = AppPaths.at(tmp);
        await paths.ensureCreated();
        File('${paths.art.path}/a.jpg').writeAsBytesSync(Uint8List(1000));
        Directory('${paths.art.path}/sub').createSync();
        File('${paths.art.path}/sub/b.jpg').writeAsBytesSync(Uint8List(500));
        paths.db.writeAsBytesSync(Uint8List(4000));
        File('${paths.db.path}-wal').writeAsBytesSync(Uint8List(300));
        File('${paths.db.path}-shm').writeAsBytesSync(Uint8List(20));

        final usage = await measureStorage(paths);
        expect(usage.artBytes, 1500);
        expect(usage.databaseBytes, 4320);
      },
    );

    test('measureStorage copes with nothing being there yet', () async {
      final usage = await measureStorage(
        AppPaths.at(Directory('${tmp.path}/missing')),
      );
      expect(usage.artBytes, 0);
      expect(usage.databaseBytes, 0);
    });

    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1048575), '1.0 MB');
      expect(formatBytes(12 * 1024 * 1024 + 300 * 1024), '12.3 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

  group('export log', () {
    uiTest('flushes the log, then hands it to the saver', (tester) async {
      AppLog.i('hello from the test');
      String? savedName;
      Uint8List? saved;
      await pumpSettings(
        tester,
        logSaver: (name, bytes) async {
          savedName = name;
          saved = bytes;
          return true;
        },
      );

      await tester.tap(find.byKey(const Key('settings.exportLog')));
      await settle(tester);

      expect(savedName, 'songies.log');
      expect(utf8.decode(saved!), contains('hello from the test'));
      expect(find.text('Log saved'), findsOneWidget);
    });

    uiTest('includes the rotated log before the current one', (tester) async {
      File('${h.paths!.logs.path}/songies.log.1').writeAsStringSync('old\n');
      File('${h.paths!.logs.path}/songies.log').writeAsStringSync('new\n');
      Uint8List? saved;
      await pumpSettings(
        tester,
        logSaver: (name, bytes) async {
          saved = bytes;
          return true;
        },
      );

      await tester.tap(find.byKey(const Key('settings.exportLog')));
      await settle(tester);
      expect(utf8.decode(saved!), 'old\nnew\n');
    });

    uiTest('says so when there is no log yet', (tester) async {
      var asked = 0;
      await pumpSettings(
        tester,
        logSaver: (name, bytes) async {
          asked++;
          return true;
        },
      );

      await tester.tap(find.byKey(const Key('settings.exportLog')));
      await settle(tester);
      expect(find.text('No log yet'), findsOneWidget);
      expect(asked, 0);
    });

    uiTest('a cancelled save says nothing; a failed one says so', (
      tester,
    ) async {
      File('${h.paths!.logs.path}/songies.log').writeAsStringSync('x\n');
      var fail = false;
      await pumpSettings(
        tester,
        logSaver: (name, bytes) async {
          if (fail) throw const FileSystemException('disk full');
          return false;
        },
      );

      await tester.tap(find.byKey(const Key('settings.exportLog')));
      await settle(tester);
      expect(find.text('Log saved'), findsNothing);
      expect(find.text("Couldn't save the log"), findsNothing);

      fail = true;
      await tester.tap(find.byKey(const Key('settings.exportLog')));
      await settle(tester);
      expect(find.text("Couldn't save the log"), findsOneWidget);
    });
  });

  group('appearance', () {
    uiTest('Themes shows the active theme and opens the Themes page', (
      tester,
    ) async {
      await real(
        tester,
        () =>
            SettingsRepository(h.db)
                .setString(kActiveThemeId, kTerminalThemeId),
      );
      await pumpSettings(tester);
      final row = find.byKey(const Key('settings.themes'));
      expect(
        find.descendant(of: row, matching: find.text('Terminal')),
        findsOneWidget,
      );

      await tester.tap(row);
      await settle(tester);
      expect(find.text('Themes page'), findsOneWidget);
    });

    uiTest('Reduce animations is off by default and saves the setting', (
      tester,
    ) async {
      await pumpSettings(tester);
      final toggle = find.byKey(const Key('settings.reduceMotion'));
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(toggle);
      await settle(tester);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(
        await real(
          tester,
          () =>
              SettingsRepository(h.db).getBool(kReduceMotion, fallback: false),
        ),
        isTrue,
      );
    });
  });

  group('youtube', () {
    Finder reset() => find.text('Reset YouTube recommendations');

    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));

    uiTest('Reset YouTube recommendations asks first; Cancel keeps all', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.ensureVisible(reset());
      await tester.tap(reset());
      await settle(tester);
      expect(find.text('Reset YouTube recommendations?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(h.innertube.resets, 0);
    });

    uiTest('confirming forgets the visitor id and reloads the feed', (
      tester,
    ) async {
      await pumpSettings(tester);
      await real(tester, () => container(tester).read(ytmHomeProvider.future));
      expect(h.ytm.homeCalls, hasLength(1));

      await tester.ensureVisible(reset());
      await tester.tap(reset());
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings.ytReset.confirm')));
      await settle(tester);

      expect(h.innertube.resets, 1);
      expect(find.text('YouTube recommendations reset'), findsOneWidget);
      await real(tester, () => container(tester).read(ytmHomeProvider.future));
      expect(h.ytm.homeCalls, hasLength(2));
    });
  });

  group('about', () {
    uiTest('shows the version and the first 8 characters of the device id', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text(appVersion), findsOneWidget);
      final id = h.stamp.deviceId;
      expect(find.text(id.substring(0, 8)), findsOneWidget);
      expect(find.text(id), findsNothing);
    });

    test('appVersion matches pubspec.yaml', () {
      final line = File('pubspec.yaml')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('version:'));
      expect(line.split(':')[1].trim().split('+').first, appVersion);
    });
  });
}
