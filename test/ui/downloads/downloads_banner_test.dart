import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/downloads/download_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/downloads/downloads_banner.dart';

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

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        extraOverrides: [
          downloadSnapshotProvider.overrideWith((ref) => snaps.stream),
        ],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: DownloadsBanner()),
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

  const banner = 'Downloads failing — update yt-dlp?';

  uiTest('shows while the extractor is failing', (tester) async {
    await pump(tester);
    await emit(tester, const DownloadSnapshot());
    expect(find.text(banner), findsNothing);
    await emit(
      tester,
      const DownloadSnapshot(extractorFailing: true, failedThisRun: 1),
    );
    expect(find.text(banner), findsOneWidget);
    await emit(tester, const DownloadSnapshot(failedThisRun: 1));
    expect(find.text(banner), findsNothing);
  });

  uiTest('Dismiss hides it until the next failure', (tester) async {
    await pump(tester);
    await emit(
      tester,
      const DownloadSnapshot(extractorFailing: true, failedThisRun: 1),
    );
    await tester.tap(find.text('Dismiss'));
    await settle(tester);
    expect(find.text(banner), findsNothing);

    // Something else changes: still dismissed.
    await emit(
      tester,
      const DownloadSnapshot(
        extractorFailing: true,
        failedThisRun: 1,
        queued: 1,
      ),
    );
    expect(find.text(banner), findsNothing);

    await emit(
      tester,
      const DownloadSnapshot(extractorFailing: true, failedThisRun: 2),
    );
    expect(find.text(banner), findsOneWidget);
  });

  uiTest('Update runs the yt-dlp update', (tester) async {
    await pump(tester);
    await emit(
      tester,
      const DownloadSnapshot(extractorFailing: true, failedThisRun: 1),
    );
    await tester.tap(find.text('Update'));
    await settle(tester);
    expect(h.ytRunner.updateCalls, 1);
    expect(find.text('yt-dlp updated to 2026.10.21'), findsOneWidget);
    expect(find.text(banner), findsNothing);
  });
}
