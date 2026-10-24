import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/downloads/track_download_icon.dart';

import '../../helpers/test_db.dart';
import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester, String trackId) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: [
          trackDownloadStatesProvider('p').overrideWith(
            (ref) => Stream.value(const {
              'q': 'queued',
              'd': 'downloading',
              'ok': 'done',
              'f': 'failed',
            }),
          ),
          downloadSnapshotProvider.overrideWith(
            (ref) => Stream.value(
              const DownloadSnapshot(
                active: 1,
                progress: {'d': TrackProgress(40, 100)},
              ),
            ),
          ),
        ],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: TrackDownloadIcon(playlistId: 'p', trackId: trackId),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  uiTest('queued shows a schedule icon', (tester) async {
    await pump(tester, 'q');
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  uiTest('downloading shows a 16 px ring at the fraction', (tester) async {
    await pump(tester, 'd');
    final ring = find.byType(CircularProgressIndicator);
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0.4);
    expect(tester.getSize(ring), const Size(16, 16));
  });

  uiTest('done shows download_done', (tester) async {
    await pump(tester, 'ok');
    expect(find.byIcon(Icons.download_done), findsOneWidget);
  });

  uiTest('no row shows nothing', (tester) async {
    await pump(tester, 'other');
    expect(find.byType(Icon), findsNothing);
  });

  uiTest('failed shows the error on tap and offers Retry', (tester) async {
    await real(tester, () async {
      await h.db
          .into(h.db.tracks)
          .insert(trackRow(id: 'f', source: 'yt', ytVideoId: 'vf'));
      await h.db
          .into(h.db.localFiles)
          .insert(
            LocalFilesCompanion.insert(
              trackId: 'f',
              path: '',
              state: 'downloading',
              bytes: 0,
              mtimeMs: 0,
            ),
          );
      await h.downloadRepo.markFailed('f', 'This video is private');
    });
    await pump(tester, 'f');
    await tester.tap(find.byIcon(Icons.error_outline));
    await settle(tester);
    expect(find.text('This video is private'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(h.downloadRepo.calls, ['retryFailed(playlist: null, track: f)']);
    expect(find.text('This video is private'), findsNothing);
  });
}
