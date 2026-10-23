import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/library_scanner.dart';
import 'package:songies/ui/library/pickers.dart';
import 'package:songies/ui/library/library_page.dart';

import '../helpers/ui_harness.dart';

ScanProgress progress({
  int found = 10,
  int processed = 0,
  int added = 0,
  int skipped = 0,
  bool done = false,
}) => ScanProgress(
  found: found,
  processed: processed,
  added: added,
  unchanged: processed - added - skipped,
  skipped: skipped,
  done: done,
);

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpLibrary(
    WidgetTester tester, {
    Size size = const Size(800, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/library',
        routes: [
          GoRoute(
            path: '/library',
            builder: (_, _) => const Scaffold(body: LibraryPage()),
          ),
          GoRoute(
            path: '/library/playlist/:id',
            builder: (_, state) => Scaffold(
              body: Text('Playlist page ${state.pathParameters['id']}'),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Add'));
    await settle(tester);
    await tester.tap(find.text(item));
    await settle(tester);
  }

  uiTest('with no playlists it offers to add a music folder', (tester) async {
    await pumpLibrary(tester);

    expect(find.text('Your Library'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Add a music folder'),
      findsOneWidget,
    );
  });

  uiTest('the empty-state button starts the folder flow', (tester) async {
    var asked = 0;
    h.folderPicker = () async {
      asked++;
      return const FolderPickCancelled();
    };
    await pumpLibrary(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add a music folder'));
    await settle(tester);
    expect(asked, 1);
  });

  uiTest('lists playlists with their size and opens one on tap', (
    tester,
  ) async {
    final id = await real(tester, () async {
      await h.addTrack('t1');
      await h.addTrack('t2');
      return h.addPlaylist('Road trip', ['t1', 't2']);
    });
    await real(tester, () => h.addPlaylist('Alpha', []));
    await pumpLibrary(tester);

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    final names = [
      for (final t in tester.widgetList<Text>(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == 'Alpha' || w.data == 'Road trip') &&
              w.maxLines == 1,
        ),
      ))
        t.data,
    ];
    expect(names, ['Alpha', 'Road trip']);
    expect(find.text('Local · 2 songs'), findsOneWidget);
    expect(find.text('Local · 0 songs'), findsOneWidget);

    await tester.tap(find.text('Road trip'));
    await settle(tester);
    expect(find.text('Playlist page $id'), findsOneWidget);
  });

  uiTest('the Local chip keeps local playlists', (tester) async {
    await real(tester, () => h.addPlaylist('Mine', []));
    await pumpLibrary(tester);

    await tester.tap(find.text('Local'));
    await settle(tester);
    expect(find.text('Mine'), findsOneWidget);
    await tester.tap(find.text('All'));
    await settle(tester);
    expect(find.text('Mine'), findsOneWidget);
  });

  uiTest('the YouTube chip keeps YouTube playlists', (tester) async {
    await real(tester, () async {
      await h.addPlaylist('Mine', []);
      final yt = await h.addPlaylist('Tube mix', []);
      await (h.db.update(h.db.playlists)..where((p) => p.id.equals(yt))).write(
        const PlaylistsCompanion(source: Value('yt')),
      );
    });
    await pumpLibrary(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'YouTube'));
    await settle(tester);
    expect(find.text('Tube mix'), findsOneWidget);
    expect(find.text('Mine'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Local'));
    await settle(tester);
    expect(find.text('Tube mix'), findsNothing);
    expect(find.text('Mine'), findsOneWidget);
  });

  group('new playlist', () {
    uiTest('Save stays disabled while the name is empty', (tester) async {
      await pumpLibrary(tester);
      await openMenu(tester, 'New playlist');

      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Gym');
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    });

    uiTest('Save creates the playlist', (tester) async {
      await pumpLibrary(tester);
      await openMenu(tester, 'New playlist');

      await tester.enterText(find.byType(TextField), ' Gym ');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      expect(find.text('Gym'), findsOneWidget);
      final stored = await real(tester, () => h.repo.watchPlaylists().first);
      expect([for (final p in stored) p.name], ['Gym']);
      expect(find.text('Add a music folder'), findsNothing);
    });

    uiTest('Cancel creates nothing', (tester) async {
      await pumpLibrary(tester);
      await openMenu(tester, 'New playlist');
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(await real(tester, () => h.repo.watchPlaylists().first), isEmpty);
    });
  });

  group('add music folder', () {
    Future<void> chooseFolder(WidgetTester tester) async {
      h.folderPicker = () async => const FolderPicked('/music/Rock');
      await pumpLibrary(tester);
      await openMenu(tester, 'Add music folder');
    }

    uiTest('asks whether to create a playlist, on by default', (tester) async {
      await chooseFolder(tester);

      final checkbox = find.byType(CheckboxListTile);
      expect(find.text("Also create playlist 'Rock'"), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(h.scanner.scannedFolders, isEmpty);
    });

    uiTest('scans with a playlist named after the folder', (tester) async {
      h.scanner.onScan = (folder, name) => Stream.value(
        progress(processed: 10, added: 8, skipped: 2, done: true),
      );
      await chooseFolder(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      expect(h.scanner.scannedFolders, ['/music/Rock']);
      expect(h.scanner.playlistNames, ['Rock']);
      expect(find.text('Added 8 songs from Rock · 2 skipped'), findsOneWidget);
    });

    uiTest('unticking the box scans without a playlist', (tester) async {
      h.scanner.onScan = (folder, name) =>
          Stream.value(progress(processed: 1, added: 1, done: true));
      await chooseFolder(tester);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      expect(h.scanner.playlistNames, [null]);
      expect(find.text('Added 1 song from Rock'), findsOneWidget);
    });

    uiTest('shows progress while scanning', (tester) async {
      final controller = StreamController<ScanProgress>();
      h.scanner.onScan = (folder, name) => controller.stream;
      await chooseFolder(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await flush(tester);
      expect(find.text('Looking for music in Rock…'), findsOneWidget);
      controller.add(progress(processed: 4, added: 4));
      await flush(tester);

      expect(find.text('Scanning Rock · 4 of 10'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      controller.add(progress(processed: 10, added: 10, done: true));
      unawaited(controller.close()); // completes on the fake clock
      await flush(tester);
      await settle(tester);
      expect(find.text('Added 10 songs from Rock'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    uiTest('a failing scan shows a message instead of crashing', (
      tester,
    ) async {
      h.scanner.onScan = (folder, name) =>
          Stream.error(StateError('Folder not found'));
      await chooseFolder(tester);

      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {}; // AppLog echoes to the console.
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);
      debugPrint = originalDebugPrint;

      expect(find.text("Couldn't scan Rock"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    uiTest('cancelling the folder picker does nothing', (tester) async {
      await pumpLibrary(tester);
      await openMenu(tester, 'Add music folder');

      expect(find.byType(AlertDialog), findsNothing);
      expect(h.scanner.scannedFolders, isEmpty);
    });

    uiTest('without permission it explains and offers settings', (
      tester,
    ) async {
      var picked = false;
      h.folderPicker = () async {
        picked = true;
        return const FolderPicked('/music/Rock');
      };
      h.mediaAccess = () async => false;
      await pumpLibrary(tester);
      await openMenu(tester, 'Add music folder');

      expect(find.text('Open settings'), findsOneWidget);
      expect(find.textContaining('permission'), findsWidgets);
      expect(picked, isFalse);
      expect(h.scanner.scannedFolders, isEmpty);
    });
  });
}
