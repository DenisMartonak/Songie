import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/paths.dart';
import 'package:songies/data/database.dart';
import 'package:songies/ui/playlist/playlist_page.dart';

import '../../helpers/test_db.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late Directory tmp;

  setUp(() async {
    h = await UiHarness.create();
    tmp = Directory.systemTemp.createTempSync('dl_toggle_test');
    h.paths = AppPaths.at(tmp);
  });
  tearDown(() async {
    await h.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester, String playlistId) async {
    tester.view.physicalSize = const Size(800, 900);
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
        ],
      ),
    );
    await settle(tester);
  }

  /// A YouTube playlist of y1, y2 (available) and y3 (unavailable).
  Future<String> ytPlaylist(WidgetTester tester) => real(tester, () async {
    for (final id in ['y1', 'y2', 'y3']) {
      await h.db
          .into(h.db.tracks)
          .insert(
            trackRow(
              id: id,
              source: 'yt',
              ytVideoId: 'v$id',
              title: 'Song $id',
            ).copyWith(unavailable: Value(id == 'y3')),
          );
    }
    final pid = await h.addPlaylist('Mix', ['y1', 'y2', 'y3']);
    await (h.db.update(h.db.playlists)..where((p) => p.id.equals(pid))).write(
      const PlaylistsCompanion(source: Value('yt')),
    );
    return pid;
  });

  /// Marks [ids] as downloaded files of 1 KB each.
  Future<void> downloaded(WidgetTester tester, List<String> ids) =>
      real(tester, () async {
        for (final id in ids) {
          await h.db
              .into(h.db.localFiles)
              .insertOnConflictUpdate(
                LocalFilesCompanion.insert(
                  trackId: id,
                  path: '${h.paths!.libraryYt.path}/v$id.webm',
                  state: 'done',
                  bytes: 1024,
                  mtimeMs: 0,
                ),
              );
        }
      });

  Future<bool> enabled(WidgetTester tester, String pid) => real(
    tester,
    () async =>
        (await h.downloadRepo.watchEnabledPlaylists().first).contains(pid),
  );

  Future<String> entryId(WidgetTester tester, String trackId) => real(
    tester,
    () async => (await (h.db.select(
      h.db.playlistEntries,
    )..where((e) => e.trackId.equals(trackId))).getSingle()).id,
  );

  Finder toggle() => find.byKey(const Key('playlist.download'));

  uiTest('a local playlist has no Download toggle', (tester) async {
    final pid = await real(tester, () async {
      await h.addTrack('t1');
      return h.addPlaylist('Local', ['t1']);
    });
    await pumpPage(tester, pid);
    expect(toggle(), findsNothing);
  });

  uiTest('turning the toggle on queues the songs and says how many', (
    tester,
  ) async {
    final pid = await ytPlaylist(tester);
    await pumpPage(tester, pid);
    expect(find.byIcon(Icons.arrow_circle_down_outlined), findsOneWidget);

    await tester.tap(toggle());
    await settle(tester);

    expect(h.downloadRepo.calls, ['setPlaylistDownload($pid, true)']);
    expect(h.permissionAsks, 1);
    expect(find.text('Downloading 2 songs'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_circle_down), findsOneWidget);
    expect(await enabled(tester, pid), isTrue);
  });

  uiTest('one song is singular', (tester) async {
    final pid = await ytPlaylist(tester);
    await downloaded(tester, ['y2']);
    await pumpPage(tester, pid);
    await tester.tap(toggle());
    await settle(tester);
    expect(find.text('Downloading 1 song'), findsOneWidget);
  });

  group('turning it off', () {
    Future<String> enabledWithFiles(WidgetTester tester) async {
      final pid = await ytPlaylist(tester);
      await real(tester, () => h.downloadRepo.setPlaylistDownload(pid, true));
      await downloaded(tester, ['y1', 'y2']);
      h.downloadRepo.calls.clear();
      return pid;
    }

    uiTest('with files only here asks whether to remove them', (tester) async {
      final pid = await enabledWithFiles(tester);
      await pumpPage(tester, pid);
      await tester.tap(toggle());
      await settle(tester);

      expect(find.text('Remove downloads?'), findsOneWidget);
      expect(
        find.text(
          '2 songs (2.0 KB) are only in this playlist. '
          'Remove them from this device?',
        ),
        findsOneWidget,
      );
      expect(find.text('Keep files'), findsOneWidget);
    });

    uiTest('Remove turns it off and removes those files', (tester) async {
      final pid = await enabledWithFiles(tester);
      await pumpPage(tester, pid);
      await tester.tap(toggle());
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);

      expect(h.downloadRepo.calls, [
        'setPlaylistDownload($pid, false)',
        'removeFiles',
      ]);
      expect(h.downloadRepo.removed.single, unorderedEquals(['y1', 'y2']));
      expect(await enabled(tester, pid), isFalse);
      expect(find.byIcon(Icons.arrow_circle_down_outlined), findsOneWidget);
    });

    uiTest('Keep files turns it off and keeps them', (tester) async {
      final pid = await enabledWithFiles(tester);
      await pumpPage(tester, pid);
      await tester.tap(toggle());
      await settle(tester);
      await tester.tap(find.text('Keep files'));
      await settle(tester);

      expect(h.downloadRepo.calls, ['setPlaylistDownload($pid, false)']);
      expect(await enabled(tester, pid), isFalse);
    });

    uiTest('without files it turns off at once', (tester) async {
      final pid = await ytPlaylist(tester);
      await real(tester, () => h.downloadRepo.setPlaylistDownload(pid, true));
      h.downloadRepo.calls.clear();
      await pumpPage(tester, pid);
      await tester.tap(toggle());
      await settle(tester);

      expect(find.text('Remove downloads?'), findsNothing);
      expect(h.downloadRepo.calls, ['setPlaylistDownload($pid, false)']);
    });
  });

  group('track menu', () {
    uiTest('Download downloads the song and shows it queued', (tester) async {
      final pid = await ytPlaylist(tester);
      final e1 = await entryId(tester, 'y1');
      await pumpPage(tester, pid);

      await tester.tap(find.byKey(Key('track.menu.$e1')));
      await settle(tester);
      expect(find.text('Remove download'), findsNothing);
      await tester.tap(find.text('Download'));
      await settle(tester);

      expect(h.downloadRepo.calls, ['downloadTrack(y1)']);
      expect(h.permissionAsks, 1);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    uiTest('a downloaded song offers Remove download', (tester) async {
      final pid = await ytPlaylist(tester);
      await downloaded(tester, ['y1']);
      final e1 = await entryId(tester, 'y1');
      await pumpPage(tester, pid);
      expect(find.byIcon(Icons.download_done), findsOneWidget);

      await tester.tap(find.byKey(Key('track.menu.$e1')));
      await settle(tester);
      await tester.tap(find.text('Remove download'));
      await settle(tester);

      expect(h.downloadRepo.calls.first, 'removeTrackDownload(y1)');
      expect(find.byIcon(Icons.download_done), findsNothing);
    });

    uiTest("a local song's menu has no Download", (tester) async {
      final pid = await real(tester, () async {
        await h.addTrack('t1');
        return h.addPlaylist('Local', ['t1']);
      });
      final e1 = await entryId(tester, 't1');
      await pumpPage(tester, pid);
      await tester.tap(find.byKey(Key('track.menu.$e1')));
      await settle(tester);
      expect(find.text('Add to queue'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
      expect(find.text('Remove download'), findsNothing);
    });

    uiTest('an unavailable song offers no Download', (tester) async {
      final pid = await ytPlaylist(tester);
      final e3 = await entryId(tester, 'y3');
      await pumpPage(tester, pid);
      await tester.tap(find.byKey(Key('track.menu.$e3')));
      await settle(tester);
      expect(find.text('Add to queue'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });
  });
}
