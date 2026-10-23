import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/downloads/download_repository.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/ui/playlist/yt_playlist_actions.dart';
import 'package:songies/youtube/yt_import_service.dart';
import 'package:songies/youtube/yt_models.dart';

import '../helpers/test_db.dart';
import '../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  final now = DateTime(2026, 10, 23, 12);

  setUp(() async {
    h = await UiHarness.create();
    h.now = () => now;
  });
  tearDown(() => h.dispose());

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

  /// A YouTube playlist with tracks y1..y3; y2's entry is removed on YouTube
  /// and y3 is unavailable. Returns the playlist id.
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
      PlaylistsCompanion(
        source: const Value('yt'),
        ytPlaylistUrl: const Value(
          'https://music.youtube.com/playlist?list=PLx',
        ),
        lastYtSyncAt: Value(now.subtract(const Duration(minutes: 5))),
      ),
    );
    await (h.db.update(h.db.playlistEntries)
          ..where((e) => e.trackId.equals('y2')))
        .write(const PlaylistEntriesCompanion(status: Value('removed_on_yt')));
    return pid;
  });

  Future<PlaylistEntry> entryOf(WidgetTester tester, String trackId) => real(
    tester,
    () => (h.db.select(
      h.db.playlistEntries,
    )..where((e) => e.trackId.equals(trackId))).getSingle(),
  );

  Finder syncButton() => find.text('Sync with YouTube');

  group('relativeTimeText', () {
    test('just now, minutes, hours and days', () {
      final t = DateTime(2026, 1, 10, 12);
      expect(
        relativeTimeText(t, t.add(const Duration(seconds: 20))),
        'just now',
      );
      expect(
        relativeTimeText(t, t.add(const Duration(minutes: 7))),
        '7 min ago',
      );
      expect(relativeTimeText(t, t.add(const Duration(hours: 3))), '3 h ago');
      expect(relativeTimeText(t, t.add(const Duration(days: 2))), '2 d ago');
    });
  });

  uiTest('a YouTube playlist shows its source, last sync and Sync', (
    tester,
  ) async {
    final pid = await ytPlaylist(tester);
    await pumpPage(tester, pid);

    expect(
      find.text('YouTube playlist · last synced 5 min ago'),
      findsOneWidget,
    );
    expect(syncButton(), findsOneWidget);
  });

  uiTest('a local playlist has no Sync button', (tester) async {
    final pid = await real(tester, () async {
      await h.addTrack('t1');
      return h.addPlaylist('Local one', ['t1']);
    });
    await pumpPage(tester, pid);

    expect(find.text('Local playlist'), findsOneWidget);
    expect(syncButton(), findsNothing);
  });

  group('sync', () {
    Future<void> syncWith(
      WidgetTester tester,
      Result<SyncResult> result,
    ) async {
      final pid = await ytPlaylist(tester);
      h.importService.onSync = (_) async => result;
      await pumpPage(tester, pid);
      await tester.tap(syncButton());
      await settle(tester);
      expect(h.importService.synced, [pid]);
    }

    SyncResult r(int added, int removed) => SyncResult(
      added: added,
      flaggedRemoved: removed,
      restored: 0,
      addedTrackIds: const [],
    );

    uiTest('nothing new says Up to date', (tester) async {
      await syncWith(tester, Ok(r(0, 0)));
      expect(find.text('Up to date'), findsOneWidget);
    });

    uiTest('new songs only', (tester) async {
      await syncWith(tester, Ok(r(4, 0)));
      expect(find.text('Added 4 new songs'), findsOneWidget);
    });

    uiTest('new and removed songs', (tester) async {
      await syncWith(tester, Ok(r(2, 3)));
      expect(find.text('Added 2, 3 removed on YouTube'), findsOneWidget);
    });

    uiTest('removed songs only', (tester) async {
      await syncWith(tester, Ok(r(0, 1)));
      expect(find.text('Added 0, 1 removed on YouTube'), findsOneWidget);
    });

    uiTest('an extractor error suggests updating yt-dlp', (tester) async {
      await syncWith(tester, Err(ytFailure(YtErrorKind.extractor, 'boom')));
      expect(
        find.text('YouTube changed something — try Settings → Update yt-dlp'),
        findsOneWidget,
      );
    });

    uiTest('new songs of a downloaded playlist are queued', (tester) async {
      final pid = await ytPlaylist(tester);
      await real(tester, () async {
        await h.db
            .into(h.db.tracks)
            .insert(trackRow(id: 'y4', source: 'yt', ytVideoId: 'vy4'));
        await h.repo.addTracks(pid, ['y4']);
        await DownloadRepository(h.db).setPlaylistDownload(pid, true);
        // Only y1 was queued by enabling; y4 comes from the sync.
        await (h.db.delete(
          h.db.localFiles,
        )..where((f) => f.trackId.equals('y4'))).go();
      });
      h.importService.onSync = (_) async => Ok(
        SyncResult(
          added: 1,
          flaggedRemoved: 0,
          restored: 0,
          addedTrackIds: const ['y4'],
        ),
      );
      await pumpPage(tester, pid);
      await tester.tap(syncButton());
      await settle(tester);

      final rows = await real(tester, () => h.db.select(h.db.localFiles).get());
      expect(
        {for (final r in rows) r.trackId: r.state},
        {'y1': 'queued', 'y4': 'queued'},
      );
      expect(h.downloads.kicks, 1);
    });

    uiTest('shows Syncing… and ignores taps while running', (tester) async {
      final pid = await ytPlaylist(tester);
      final done = Completer<Result<SyncResult>>();
      h.importService.onSync = (_) => done.future;
      await pumpPage(tester, pid);

      await tester.tap(syncButton());
      await tester.pump();
      expect(find.text('Syncing…'), findsOneWidget);
      await tester.tap(find.text('Syncing…'));
      await tester.pump();
      expect(h.importService.synced, hasLength(1));

      done.complete(Ok(r(0, 0)));
      await settle(tester);
      expect(syncButton(), findsOneWidget);
    });
  });

  group('rows', () {
    uiTest('a removed row is tagged and Keep keeps it', (tester) async {
      final pid = await ytPlaylist(tester);
      await pumpPage(tester, pid);

      expect(find.text('removed on YT'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await settle(tester);

      final e = await entryOf(tester, 'y2');
      expect(e.kept, isTrue);
      expect(e.status, 'active');
      expect(find.text('removed on YT'), findsNothing);
    });

    uiTest('Delete removes the removed row', (tester) async {
      final pid = await ytPlaylist(tester);
      await pumpPage(tester, pid);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);

      expect((await entryOf(tester, 'y2')).deleted, isTrue);
      expect(find.text('Song y2'), findsNothing);
    });

    uiTest('an unavailable track is tagged', (tester) async {
      final pid = await ytPlaylist(tester);
      await pumpPage(tester, pid);

      expect(find.text('unavailable'), findsOneWidget);
      // Only the removed row offers Keep / Delete.
      expect(find.widgetWithText(TextButton, 'Keep'), findsOneWidget);
    });
  });
}
