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
import 'package:songies/ui/settings/discord_settings.dart';
import 'package:songies/ui/settings/settings_categories.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';
import 'package:songies/update/update_checker.dart';
import 'package:songies/update/update_installer.dart'
    show updateInstallerProvider;

import '../helpers/fake_updater.dart';
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
    bool discordSupported = true,
    String discordClientId = '123',
    String location = '/settings',
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: location,
        extraOverrides: [
          storageUsageProvider.overrideWith((ref) async => usage),
          if (logSaver != null) logSaverProvider.overrideWithValue(logSaver),
          discordSupportedProvider.overrideWithValue(discordSupported),
          discordClientIdProvider.overrideWithValue(discordClientId),
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
          // As the app's router: a sibling, so categories don't stack.
          GoRoute(
            path: '/settings/:category',
            builder: (_, s) => Scaffold(
              body: SettingsPage(
                category: settingsCategoryFromSlug(
                  s.pathParameters['category'],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  /// Scrolls Settings until [target] is on screen.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(target);
    await tester.pump();
  }

  Finder rescan(String path) => find.byKey(Key('settings.rescan.$path'));
  Finder remove(String path) => find.byKey(Key('settings.remove.$path'));

  for (final (width, back) in [(400.0, true), (1280.0, false)]) {
    uiTest(
      'Settings over another page: Back ${back ? 'on a phone' : 'not on desktop'}',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          h.app(
            initialLocation: '/home',
            extraOverrides: [
              storageUsageProvider.overrideWith(
                (ref) async =>
                    const StorageUsage(artBytes: 0, databaseBytes: 0),
              ),
            ],
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const Scaffold(body: Text('Home stub')),
              ),
              GoRoute(
                path: '/settings',
                builder: (_, _) => const Scaffold(body: SettingsPage()),
              ),
            ],
          ),
        );
        await settle(tester);
        GoRouter.of(tester.element(find.text('Home stub'))).push('/settings');
        await settle(tester);
        expect(find.byTooltip('Back'), back ? findsOneWidget : findsNothing);
      },
    );
  }

  group('categories', () {
    Finder tile(String slug) => find.byKey(Key('settings.category.$slug'));
    const slugs = [
      'library',
      'playback',
      'youtube',
      'appearance',
      'privacy',
      'discord',
      'about',
    ];

    Future<GoRouter> pumpAt(
      WidgetTester tester,
      Size size, {
      String location = '/settings',
    }) async {
      await pumpSettings(tester, location: location);
      tester.view.physicalSize = size;
      await settle(tester);
      return GoRouter.of(tester.element(find.byType(SettingsPage).first));
    }

    uiTest('a phone lists the categories; one opens its page and Back '
        'returns', (tester) async {
      final router = await pumpAt(tester, const Size(400, 900));
      for (final slug in slugs) {
        expect(tile(slug), findsOneWidget);
      }
      expect(find.byKey(const Key('settings.addFolder')), findsNothing);

      await tester.tap(tile('about'));
      await settle(tester);
      expect(router.state.uri.path, '/settings/about');
      expect(find.byKey(const Key('settings.checkForUpdates')), findsOneWidget);
      expect(tile('library'), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(router.state.uri.path, '/settings');
      expect(tile('about'), findsOneWidget);
    });

    uiTest('on a phone, Back from a category opened directly goes to the '
        'list', (tester) async {
      final router = await pumpAt(
        tester,
        const Size(400, 900),
        location: '/settings/youtube',
      );
      expect(find.byKey(const Key('settings.ytReset')), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      expect(router.state.uri.path, '/settings');
      expect(tile('youtube'), findsOneWidget);
    });

    uiTest('wide shows the list beside Library; picking a category swaps '
        'the page without stacking', (tester) async {
      final router = await pumpAt(tester, const Size(1000, 900));
      for (final slug in slugs) {
        expect(tile(slug), findsOneWidget);
      }
      expect(find.byKey(const Key('settings.addFolder')), findsOneWidget);
      final couldPop = router.canPop();

      await tester.tap(tile('about'));
      await settle(tester);
      expect(router.state.uri.path, '/settings/about');
      expect(find.byKey(const Key('settings.checkForUpdates')), findsOneWidget);
      expect(find.byKey(const Key('settings.addFolder')), findsNothing);
      expect(tile('library'), findsOneWidget);
      expect(router.canPop(), couldPop);
      expect(find.byTooltip('Back'), findsNothing);
    });

    uiTest('an unknown category shows Library', (tester) async {
      await pumpAt(tester, const Size(1000, 900), location: '/settings/nope');
      expect(find.byKey(const Key('settings.addFolder')), findsOneWidget);
    });

    uiTest('where Discord status cannot work, its category shows Library', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        location: '/settings/discord',
        discordSupported: false,
      );
      expect(tile('discord'), findsNothing);
      expect(find.byKey(const Key('settings.addFolder')), findsOneWidget);
    });
  });

  uiTest('Settings starts with Music folders; the account is on the profile', (
    tester,
  ) async {
    await pumpSettings(tester);
    final titles = tester
        .widgetList<SettingsSectionTitle>(find.byType(SettingsSectionTitle))
        .map((t) => t.title)
        .toList();
    expect(titles.first, 'Music folders');
    expect(titles, isNot(contains('Account')));
    expect(find.widgetWithText(FilledButton, 'Sign up'), findsNothing);
  });

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

    uiTest('Rescan all names every folder that fails, in one message', (
      tester,
    ) async {
      h.scanner.onScan = (folder, _) =>
          Stream.error(const FileSystemException('gone'));
      await seedFolders(tester, ['/music/Rock', '/music/Jazz']);
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings.rescanAll')));
      await settle(tester);
      expect(find.text("Couldn't scan Jazz and Rock"), findsOneWidget);
    });

    uiTest('Rescan all lists three failing folders with commas', (
      tester,
    ) async {
      h.scanner.onScan = (folder, _) => folder == '/music/Ok'
          ? const Stream.empty()
          : Stream.error(const FileSystemException('gone'));
      await seedFolders(tester, [
        '/music/Rock',
        '/music/Jazz',
        '/music/Ok',
        '/music/Pop',
      ]);
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('settings.rescanAll')));
      await settle(tester);
      expect(find.text("Couldn't scan Jazz, Pop and Rock"), findsOneWidget);
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
        location: '/settings/about',
        logSaver: (name, bytes) async {
          savedName = name;
          saved = bytes;
          return true;
        },
      );

      await reveal(tester, find.byKey(const Key('settings.exportLog')));
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
        location: '/settings/about',
        logSaver: (name, bytes) async {
          saved = bytes;
          return true;
        },
      );

      await reveal(tester, find.byKey(const Key('settings.exportLog')));
      await tester.tap(find.byKey(const Key('settings.exportLog')));
      await settle(tester);
      expect(utf8.decode(saved!), 'old\nnew\n');
    });

    uiTest('says so when there is no log yet', (tester) async {
      var asked = 0;
      await pumpSettings(
        tester,
        location: '/settings/about',
        logSaver: (name, bytes) async {
          asked++;
          return true;
        },
      );

      await reveal(tester, find.byKey(const Key('settings.exportLog')));
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
        location: '/settings/about',
        logSaver: (name, bytes) async {
          if (fail) throw const FileSystemException('disk full');
          return false;
        },
      );

      await reveal(tester, find.byKey(const Key('settings.exportLog')));
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
      await pumpSettings(tester, location: '/settings/appearance');
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
      await pumpSettings(tester, location: '/settings/appearance');
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

  group('discord', () {
    final toggle = find.byKey(const Key('settings.discord'));

    uiTest('is off by default and saves the setting', (tester) async {
      await pumpSettings(tester, location: '/settings/discord');
      expect(find.text("Show what I'm listening to"), findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await settle(tester);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(
        await real(
          tester,
          () =>
              SettingsRepository(h.db)
                  .getBool(kDiscordPresence, fallback: false),
        ),
        isTrue,
      );
    });

    uiTest('without an application id it says so and cannot be turned on', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        location: '/settings/discord',
        discordClientId: '',
      );
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      expect(
        find.text('Not set up in this version of Songies yet'),
        findsOneWidget,
      );
    });

    uiTest('is hidden where Discord status cannot work', (tester) async {
      await pumpSettings(
        tester,
        location: '/settings/discord',
        discordSupported: false,
      );
      expect(toggle, findsNothing);
      expect(find.text('Discord'), findsNothing);
    });
  });

  group('youtube', () {
    Finder reset() => find.text('Reset YouTube recommendations');

    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));

    uiTest('Reset YouTube recommendations asks first; Cancel keeps all', (
      tester,
    ) async {
      await pumpSettings(tester, location: '/settings/youtube');
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
      await pumpSettings(tester, location: '/settings/youtube');
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
      await pumpSettings(tester, location: '/settings/about');
      await reveal(tester, find.text(appVersion));

      expect(find.text(appVersion), findsOneWidget);
      final id = h.stamp.deviceId;
      expect(find.text(id.substring(0, 8)), findsOneWidget);
      expect(find.text(id), findsNothing);
    });

    group('settings button shows No updates found / connection error', () {
      late FakeUpdateChecker checker;

      setUp(() => checker = FakeUpdateChecker());

      Future<void> pumpWithUpdater(WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          h.app(
            initialLocation: '/settings',
            extraOverrides: [
              storageUsageProvider.overrideWith(
                (ref) async =>
                    const StorageUsage(artBytes: 0, databaseBytes: 0),
              ),
              updateCheckerProvider.overrideWithValue(checker),
              updateDownloaderProvider.overrideWithValue(
                FakeUpdateDownloader(),
              ),
              updateInstallerProvider.overrideWithValue(FakeUpdateInstaller()),
            ],
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const Scaffold(
                  body: SettingsPage(category: SettingsCategory.about),
                ),
              ),
            ],
          ),
        );
        await settle(tester);
        await tester.scrollUntilVisible(
          find.text('Check for updates'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Check for updates'));
        await tester.pump();
      }

      uiTest('Checking…, then No updates found.', (tester) async {
        final answer = Completer<UpdateCheck>();
        checker.onNow = () => answer.future;
        await pumpWithUpdater(tester);
        await tester.tap(find.text('Check for updates'));
        await tester.pump();
        expect(find.text('Checking…'), findsOneWidget);
        answer.complete(const UpToDate());
        await settle(tester);
        expect(find.text('Checking…'), findsNothing);
        expect(find.text('No updates found.'), findsOneWidget);
      });

      uiTest('a failed check asks to check the connection', (tester) async {
        checker.onNow = () async => CheckFailed(const SocketException('x'));
        await pumpWithUpdater(tester);
        await tester.tap(find.text('Check for updates'));
        await settle(tester);
        expect(
          find.text("Couldn't check for updates. Check your connection."),
          findsOneWidget,
        );
      });

      uiTest('an available update opens the dialog', (tester) async {
        checker.onNow = () async => availableFor(testRelease);
        await pumpWithUpdater(tester);
        await tester.tap(find.text('Check for updates'));
        await settle(tester);
        expect(find.text('Songies 1.1.0 is available'), findsOneWidget);
        expect(find.text('No updates found.'), findsNothing);
      });
    });

    test('appVersion and appBuild match pubspec.yaml', () {
      final line = File('pubspec.yaml')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('version:'));
      final version = line.split(':')[1].trim().split('+');
      expect(version.first, appVersion);
      expect(version.last, appBuild);
    });
  });
}
