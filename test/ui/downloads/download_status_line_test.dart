import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/downloads/download_repository.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/downloads/download_status_line.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  final now = DateTime(2026, 10, 24, 12);

  setUp(() async {
    h = await UiHarness.create();
    h.now = () => now;
  });
  tearDown(() => h.dispose());

  PlaylistDownloadStatus status({
    bool enabled = true,
    int total = 4,
    int done = 0,
    int queued = 0,
    int downloading = 0,
    int failed = 0,
    int bytes = 0,
  }) => PlaylistDownloadStatus(
    enabled: enabled,
    total: total,
    done: done,
    queued: queued,
    downloading: downloading,
    failed: failed,
    bytes: bytes,
  );

  Future<void> pump(
    WidgetTester tester,
    PlaylistDownloadStatus s, {
    DownloadSnapshot snapshot = const DownloadSnapshot(),
    Map<String, String> states = const {},
  }) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: <Override>[
          playlistDownloadProvider('p').overrideWith((ref) => Stream.value(s)),
          downloadSnapshotProvider.overrideWith(
            (ref) => Stream.value(snapshot),
          ),
          trackDownloadStatesProvider('p')
              .overrideWith((ref) => Stream.value(states)),
        ],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: DownloadStatusLine(playlistId: 'p')),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  uiTest('nothing while the download is off', (tester) async {
    await pump(tester, status(enabled: false, done: 2, bytes: 100));
    expect(find.byType(Text), findsNothing);
  });

  uiTest('downloading shows done of total, the size and partial bytes', (
    tester,
  ) async {
    await pump(
      tester,
      status(done: 1, downloading: 1, queued: 2, bytes: 3 * 1024 * 1024),
      states: const {'a': 'done', 'b': 'downloading', 'c': 'queued'},
      snapshot: const DownloadSnapshot(
        active: 2,
        queued: 2,
        // 'x' is another playlist's download and does not count here.
        progress: {'b': TrackProgress(50, 100), 'x': TrackProgress(9, 10)},
      ),
    );
    expect(find.text('Downloading 1 of 4 · 3.0 MB'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(1.5 / 4, 1e-9));
  });

  uiTest('all done shows the count and the size', (tester) async {
    await pump(tester, status(done: 4, bytes: 2048));
    expect(find.text('Downloaded · 4 songs · 2.0 KB'), findsOneWidget);
  });

  uiTest('failures offer Retry, which retries this playlist', (tester) async {
    await pump(tester, status(done: 2, failed: 2));
    expect(find.text('2 failed ·'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(h.downloadRepo.calls, ['retryFailed(playlist: p, track: null)']);
  });

  uiTest('a pause shows its reason without "Paused — "', (tester) async {
    await pump(
      tester,
      status(queued: 4),
      snapshot: const DownloadSnapshot(
        queued: 4,
        pause: DownloadPause(DownloadPauseReason.wifiOnly),
      ),
    );
    expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
    expect(find.textContaining('Paused'), findsNothing);
  });

  uiTest('a throttling pause says when it retries', (tester) async {
    await pump(
      tester,
      status(queued: 4),
      snapshot: DownloadSnapshot(
        queued: 4,
        pause: DownloadPause(
          DownloadPauseReason.throttled,
          resumesAt: now.add(const Duration(seconds: 90)),
        ),
      ),
    );
    expect(
      find.text('YouTube is limiting downloads, retrying in 2 min'),
      findsOneWidget,
    );
  });

  uiTest('a user pause says Paused and offers Resume', (tester) async {
    await pump(
      tester,
      status(done: 1, queued: 3),
      snapshot: const DownloadSnapshot(
        queued: 3,
        userPaused: true,
        pause: DownloadPause(DownloadPauseReason.user),
      ),
    );
    expect(find.text('Paused'), findsOneWidget);
    expect(find.textContaining('Downloading'), findsNothing);
    await tester.tap(find.text('Resume'));
    await settle(tester);
    expect(h.downloads.calls, ['resumeByUser', 'resume']);
  });

  uiTest('a full disk offers Resume, which resumes the queue', (tester) async {
    await pump(
      tester,
      status(queued: 4),
      snapshot: const DownloadSnapshot(
        queued: 4,
        pause: DownloadPause(DownloadPauseReason.diskFull),
      ),
    );
    expect(find.text('Storage is full'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await settle(tester);
    expect(h.downloads.calls, ['resumeByUser', 'resume']);
  });
}
