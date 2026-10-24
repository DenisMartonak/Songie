import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/downloads/download_repository.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/downloads/download_ring.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required bool enabled,
    int done = 0,
    int total = 4,
  }) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: [
          downloadEnabledPlaylistsProvider.overrideWith(
            (ref) => Stream.value(enabled ? {'p'} : <String>{}),
          ),
          playlistDownloadProvider('p').overrideWith(
            (ref) => Stream.value(
              PlaylistDownloadStatus(
                enabled: enabled,
                total: total,
                done: done,
                queued: total - done,
                downloading: 0,
                failed: 0,
                bytes: 0,
              ),
            ),
          ),
        ],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: Center(child: DownloadRing(playlistId: 'p')),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  uiTest('hidden while the download is off', (tester) async {
    await pump(tester, enabled: false);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  uiTest('a 14 px ring at done / total', (tester) async {
    await pump(tester, enabled: true, done: 1);
    final ring = find.byType(CircularProgressIndicator);
    expect(tester.widget<CircularProgressIndicator>(ring).value, 0.25);
    expect(tester.getSize(ring), const Size(14, 14));
  });

  uiTest('a filled check when complete', (tester) async {
    await pump(tester, enabled: true, done: 4);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
