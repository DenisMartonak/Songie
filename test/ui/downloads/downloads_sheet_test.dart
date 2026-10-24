import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/downloads/downloads_sheet.dart';

import '../../helpers/test_db.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  late StreamController<DownloadSnapshot> snaps;

  setUp(() async {
    h = await UiHarness.create();
    snaps = StreamController<DownloadSnapshot>();
  });
  tearDown(() async {
    await snaps.close();
    await h.dispose();
  });

  Future<void> pump(WidgetTester tester, {bool compact = false}) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: [
          downloadSnapshotProvider.overrideWith((ref) => snaps.stream),
        ],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: DownloadsIndicator(compact: compact),
              ),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> emit(WidgetTester tester, DownloadSnapshot s) async {
    snaps.add(s);
    await settle(tester);
  }

  const running = DownloadSnapshot(
    active: 1,
    queued: 2,
    completedThisRun: 1,
    totalThisRun: 4,
    progress: {'y1': TrackProgress(50, 100)},
  );

  uiTest('the indicator shows while songs download and hides after', (
    tester,
  ) async {
    await pump(tester);
    await emit(tester, const DownloadSnapshot());
    expect(find.textContaining('Downloading'), findsNothing);

    await emit(tester, running);
    expect(find.text('Downloading 1 of 4'), findsOneWidget);
    final line = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(line.value, closeTo(1.5 / 4, 1e-9));

    await emit(
      tester,
      const DownloadSnapshot(completedThisRun: 4, totalThisRun: 4),
    );
    expect(find.textContaining('Downloading'), findsNothing);
  });

  uiTest('the indicator says Paused during a pause', (tester) async {
    await pump(tester);
    await emit(
      tester,
      const DownloadSnapshot(
        queued: 3,
        completedThisRun: 1,
        totalThisRun: 4,
        userPaused: true,
        pause: DownloadPause(DownloadPauseReason.user),
      ),
    );
    expect(find.text('Paused'), findsOneWidget);
    expect(find.textContaining('Downloading'), findsNothing);
  });

  group('the sheet', () {
    Future<void> openSheet(WidgetTester tester, DownloadSnapshot s) async {
      await real(
        tester,
        () => h.db
            .into(h.db.tracks)
            .insert(
              trackRow(
                id: 'y1',
                source: 'yt',
                ytVideoId: 'v1',
                title: 'First song',
              ),
            ),
      );
      await pump(tester);
      await emit(tester, s);
      await tester.tap(find.byKey(const Key('downloads.indicator')));
      await settle(tester);
    }

    uiTest('lists the active songs and the queued count', (tester) async {
      await openSheet(tester, running);
      expect(find.text('First song'), findsOneWidget);
      expect(find.text('2 queued'), findsOneWidget);
    });

    uiTest('Pause downloads pauses the queue', (tester) async {
      await openSheet(tester, running);
      expect(find.text('Resume'), findsNothing);
      await tester.tap(find.text('Pause downloads'));
      await settle(tester);
      expect(h.downloads.calls, ['pauseByUser']);
    });

    uiTest('Resume clears the user pause and resumes the queue', (
      tester,
    ) async {
      await openSheet(
        tester,
        const DownloadSnapshot(
          active: 1,
          queued: 2,
          completedThisRun: 1,
          totalThisRun: 4,
          userPaused: true,
          pause: DownloadPause(DownloadPauseReason.user),
        ),
      );
      expect(find.text('Pause downloads'), findsNothing);
      await tester.tap(find.text('Resume'));
      await settle(tester);
      expect(h.downloads.calls, ['resumeByUser', 'resume']);
    });

    uiTest('Resume also ends an automatic pause', (tester) async {
      await openSheet(
        tester,
        const DownloadSnapshot(
          queued: 3,
          completedThisRun: 1,
          totalThisRun: 4,
          pause: DownloadPause(DownloadPauseReason.diskFull),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(DownloadsSheet),
          matching: find.text('Storage is full'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Resume'));
      await settle(tester);
      expect(h.downloads.calls, ['resumeByUser', 'resume']);
    });

    uiTest('Retry failed retries every failed song', (tester) async {
      await openSheet(tester, running);
      await tester.tap(find.text('Retry failed'));
      await settle(tester);
      expect(h.downloadRepo.calls, [
        'retryFailed(playlist: null, track: null)',
      ]);
    });
  });
}
