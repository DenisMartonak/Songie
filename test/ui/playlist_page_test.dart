import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/library/library_scanner.dart';
import 'package:songies/ui/library/add_songs_sheet.dart';
import 'package:songies/ui/playlist/playlist_page.dart';

import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpPage(
    WidgetTester tester,
    String playlistId, {
    Size size = const Size(800, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/playlist/$playlistId',
        routes: [
          GoRoute(
            path: '/playlist/:id',
            builder: (_, state) =>
                Scaffold(body: PlaylistPage(id: state.pathParameters['id']!)),
          ),
          GoRoute(
            path: '/library',
            builder: (_, _) => const Scaffold(body: Text('Library stub')),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<List<String>> order(WidgetTester tester, String id) =>
      real(tester, () => h.orderOf(id));

  /// Three 200 s songs in a playlist called "Road trip".
  Future<String> threeSongs(WidgetTester tester) => real(tester, () async {
    await h.addTrack('t1');
    await h.addTrack('t2');
    await h.addTrack('t3');
    return h.addPlaylist('Road trip', ['t1', 't2', 't3']);
  });

  List<String?> shownTitles(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(find.textContaining('Song t')))
      t.data,
  ];

  uiTest('shows the header and the rows in position order', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('Local playlist'), findsOneWidget);
    expect(find.text('3 songs · 0 h 10 min'), findsOneWidget);
    expect(shownTitles(tester), ['Song t1', 'Song t2', 'Song t3']);
    expect(find.text('3:20'), findsNWidgets(3));
  });

  uiTest('dragging row 3 above row 1 reorders the playlist', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.timedDrag(
      find.byIcon(Icons.drag_handle).at(2),
      const Offset(0, -150),
      const Duration(milliseconds: 600),
    );
    await settle(tester);

    expect(await order(tester, id), ['t3', 't1', 't2']);
    expect(shownTitles(tester), ['Song t3', 'Song t1', 'Song t2']);
  });

  uiTest('swipe-removing a row can be undone to the same place', (
    tester,
  ) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.drag(find.text('Song t2'), const Offset(-700, 0));
    await settle(tester);
    expect(find.text('Song t2'), findsNothing);
    expect(await order(tester, id), ['t1', 't3']);
    expect(find.text('2 songs · 0 h 6 min'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await order(tester, id), ['t1', 't2', 't3']);
    expect(find.text('Song t2'), findsOneWidget);
  });

  uiTest('undo restores the first and the last row too', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.drag(find.text('Song t1'), const Offset(-700, 0));
    await settle(tester);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await order(tester, id), ['t1', 't2', 't3']);

    await tester.drag(find.text('Song t3'), const Offset(-700, 0));
    await settle(tester);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await order(tester, id), ['t1', 't2', 't3']);
  });

  uiTest('tapping a row plays the playlist from that row', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.tap(find.text('Song t2'));
    await settle(tester);

    final state = h.player.state;
    expect([for (final t in state.queue) t.id], ['t1', 't2', 't3']);
    expect(state.index, 1);
    expect(state.sourcePlaylistId, id);
  });

  uiTest('Play starts at the top unshuffled; Shuffle turns shuffle on', (
    tester,
  ) async {
    final id = await threeSongs(tester);
    h.player.setShuffle(true);
    await pumpPage(tester, id);

    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await settle(tester);
    expect(h.player.state.shuffle, isFalse);
    expect([for (final t in h.player.state.queue) t.id], ['t1', 't2', 't3']);
    expect(h.player.state.index, 0);
    expect(h.player.state.sourcePlaylistId, id);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Shuffle'));
    await settle(tester);
    expect(h.player.state.shuffle, isTrue);
    expect(h.player.state.queue, hasLength(3));
    expect(h.player.state.sourcePlaylistId, id);
  });

  uiTest('a missing file is tagged and does not start playback', (
    tester,
  ) async {
    final id = await real(tester, () async {
      await h.addTrack('t1');
      await h.addTrack('t2', missing: true);
      return h.addPlaylist('P', ['t1', 't2']);
    });
    await pumpPage(tester, id);

    expect(find.text('File missing'), findsOneWidget);
    expect(find.text('Locate'), findsOneWidget);

    await tester.tap(find.text('Song t2'));
    await settle(tester);
    await tester.tap(find.text('File missing'));
    await settle(tester);
    expect(h.player.state.queue, isEmpty);
    expect(h.backend.calls, isEmpty);
  });

  uiTest('Locate with the same file only re-imports it', (tester) async {
    final id = await real(tester, () async {
      await h.addTrack('t1', missing: true);
      return h.addPlaylist('P', ['t1']);
    });
    h.filePicker = () async => '/new/place.mp3';
    h.scanner.onImport = (_) async => const Ok('t1');
    await pumpPage(tester, id);

    await tester.tap(find.text('Locate'));
    await settle(tester);

    expect(h.scanner.imported, ['/new/place.mp3']);
    expect(await order(tester, id), ['t1']);
  });

  uiTest('Locate with a different file swaps the entry track', (tester) async {
    final id = await real(tester, () async {
      await h.addTrack('t1', missing: true);
      await h.addTrack('t2');
      return h.addPlaylist('P', ['t1']);
    });
    h.filePicker = () async => '/new/place.mp3';
    h.scanner.onImport = (_) async => const Ok('t2');
    await pumpPage(tester, id);

    await tester.tap(find.text('Locate'));
    await settle(tester);

    expect(await order(tester, id), ['t2']);
    expect(find.text('File missing'), findsNothing);
    expect(find.text('Song t2'), findsOneWidget);
  });

  uiTest('Locate shows a message when the file cannot be imported', (
    tester,
  ) async {
    final id = await real(tester, () async {
      await h.addTrack('t1', missing: true);
      return h.addPlaylist('P', ['t1']);
    });
    h.filePicker = () async => '/new/place.mp3';
    h.scanner.onImport = (_) async =>
        const Err(Failure(FailureKind.invalidInput, 'Empty file'));
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {}; // AppLog echoes to the console.
    await pumpPage(tester, id);

    await tester.tap(find.text('Locate'));
    await settle(tester);

    debugPrint = originalDebugPrint;
    expect(find.text("Couldn't use that file"), findsOneWidget);
    expect(await order(tester, id), ['t1']);
  });

  uiTest('Locate does nothing when the picker is cancelled', (tester) async {
    final id = await real(tester, () async {
      await h.addTrack('t1', missing: true);
      return h.addPlaylist('P', ['t1']);
    });
    await pumpPage(tester, id);

    await tester.tap(find.text('Locate'));
    await settle(tester);
    expect(h.scanner.imported, isEmpty);
  });

  uiTest('undo still places the song after its old neighbour when the '
      'neighbours were reordered meanwhile', (tester) async {
    final id = await real(tester, () async {
      for (final t in ['t1', 't2', 't3', 't4']) {
        await h.addTrack(t);
      }
      return h.addPlaylist('P', ['t1', 't2', 't3', 't4']);
    });
    await pumpPage(tester, id);

    await tester.drag(find.text('Song t2'), const Offset(-700, 0));
    await settle(tester);
    // t3 jumps in front of t1: the removed song's neighbours are now out of
    // order (t1 is after t3).
    await real(tester, () async {
      final entries = await h.repo.watchPlaylistTracks(id).first;
      final t1 = entries.firstWhere((e) => e.track.id == 't1').entryId;
      final t3 = entries.firstWhere((e) => e.track.id == 't3').entryId;
      await h.repo.moveEntry(t3, beforeEntryId: t1);
    });
    await settle(tester);
    expect(await order(tester, id), ['t3', 't1', 't4']);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await order(tester, id), ['t3', 't1', 't2', 't4']);
    expect(find.text("Couldn't restore the song's position"), findsNothing);
  });

  group('Locate on Android (folder based)', () {
    uiTest('scans the chosen folder and stays quiet when the song is found', (
      tester,
    ) async {
      h.locateByFolder = true;
      final id = await real(tester, () async {
        await h.addTrack('t1', missing: true);
        return h.addPlaylist('P', ['t1']);
      });
      h.folderPicker = () async => '/storage/Music';
      h.scanner.onScan = (folder, name) async* {
        // The scan finds the file by content and repairs its local file row.
        await (h.db.update(h.db.localFiles)
              ..where((f) => f.trackId.equals('t1')))
            .write(const LocalFilesCompanion(state: Value('done')));
        yield const ScanProgress(
          found: 1,
          processed: 1,
          added: 0,
          unchanged: 1,
          skipped: 0,
          done: true,
        );
      };
      await pumpPage(tester, id);

      await tester.tap(find.text('Locate'));
      await settle(tester);

      expect(h.scanner.scannedFolders, ['/storage/Music']);
      expect(h.scanner.playlistNames, [null]);
      expect(h.scanner.imported, isEmpty, reason: 'no single-file import');
      expect(find.text('File missing'), findsNothing);
      expect(find.textContaining("Couldn't find"), findsNothing);
      expect(await order(tester, id), ['t1']);
    });

    uiTest('says so when the song is not in the folder', (tester) async {
      h.locateByFolder = true;
      final id = await real(tester, () async {
        await h.addTrack('t1', missing: true);
        return h.addPlaylist('P', ['t1']);
      });
      h.folderPicker = () async => '/storage/Music';
      h.scanner.onScan = (folder, name) => Stream.value(
        const ScanProgress(
          found: 3,
          processed: 3,
          added: 3,
          unchanged: 0,
          skipped: 0,
          done: true,
        ),
      );
      await pumpPage(tester, id);

      await tester.tap(find.text('Locate'));
      await settle(tester);

      expect(find.text("Couldn't find that song in Music"), findsOneWidget);
      expect(find.text('File missing'), findsOneWidget);
    });

    uiTest('does nothing when the folder picker is cancelled', (tester) async {
      h.locateByFolder = true;
      final id = await real(tester, () async {
        await h.addTrack('t1', missing: true);
        return h.addPlaylist('P', ['t1']);
      });
      await pumpPage(tester, id);

      await tester.tap(find.text('Locate'));
      await settle(tester);
      expect(h.scanner.scannedFolders, isEmpty);
      expect(h.scanner.imported, isEmpty);
    });

    uiTest('reports a scan that fails', (tester) async {
      h.locateByFolder = true;
      final id = await real(tester, () async {
        await h.addTrack('t1', missing: true);
        return h.addPlaylist('P', ['t1']);
      });
      h.folderPicker = () async => '/storage/Music';
      h.scanner.onScan = (folder, name) => Stream.error(StateError('gone'));
      await pumpPage(tester, id);

      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {}; // AppLog echoes to the console.
      await tester.tap(find.text('Locate'));
      await settle(tester);
      debugPrint = originalDebugPrint;

      expect(find.text("Couldn't scan Music"), findsOneWidget);
    });
  });

  uiTest('a 300 character title stays on one line without overflow', (
    tester,
  ) async {
    final long = 'x' * 300;
    final id = await real(tester, () async {
      await h.addTrack('t1', title: long, artist: 'y' * 300);
      return h.addPlaylist('P', ['t1']);
    });
    await pumpPage(tester, id, size: const Size(360, 800));

    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text(long));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  uiTest('rename changes the name; an empty name cannot be saved', (
    tester,
  ) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Rename'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' Holiday ');
    await tester.pump();
    await tester.tap(save);
    await settle(tester);

    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('Road trip'), findsNothing);
  });

  uiTest('delete asks first, then removes the playlist', (tester) async {
    final id = await threeSongs(tester);
    await pumpPage(tester, id);

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(
      await real(tester, () => h.repo.watchPlaylists().first),
      hasLength(1),
    );

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(await real(tester, () => h.repo.watchPlaylists().first), isEmpty);
    expect(find.text('Library stub'), findsOneWidget);
  });

  uiTest('an empty playlist offers Add songs', (tester) async {
    final id = await real(tester, () async {
      return h.addPlaylist('Empty', []);
    });
    await pumpPage(tester, id);

    expect(find.text('0 songs · 0 h 0 min'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add songs'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add songs'));
    await settle(tester);
    expect(find.byType(AddSongsSheet), findsOneWidget);
  });

  group('AddSongsSheet', () {
    uiTest('adds the selected songs to the playlist', (tester) async {
      final id = await real(tester, () async {
        await h.addTrack('t1', title: 'Alpha');
        await h.addTrack('t2', title: 'Bravo');
        await h.addTrack('t3', title: 'Charlie');
        return h.addPlaylist('P', ['t1']);
      });
      await pumpPage(tester, id);

      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Add songs'));
      await settle(tester);

      final none = find.widgetWithText(FilledButton, 'Add (0)');
      expect(tester.widget<FilledButton>(none).onPressed, isNull);
      await tester.tap(find.text('Charlie'));
      await tester.tap(find.text('Bravo'));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Add (2)'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add (2)'));
      await settle(tester);

      expect(find.byType(AddSongsSheet), findsNothing);
      expect(await order(tester, id), ['t1', 't3', 't2']);
    });

    uiTest('searching narrows the list and keeps the selection', (
      tester,
    ) async {
      final id = await real(tester, () async {
        await h.addTrack('t1', title: 'Alpha', artist: 'Beyonce');
        await h.addTrack('t2', title: 'Bravo');
        return h.addPlaylist('P', []);
      });
      await pumpPage(tester, id);

      await tester.tap(find.widgetWithText(FilledButton, 'Add songs'));
      await settle(tester);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);

      await tester.tap(find.text('Bravo'));
      await tester.enterText(find.byType(TextField), 'beyonce');
      await settle(tester);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Add (1)'), findsOneWidget);
    });
  });
}
