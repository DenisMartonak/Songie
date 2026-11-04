import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/library/library_scanner.dart';
import 'package:songies/ui/library/library_page.dart';
import 'package:songies/ui/library/pickers.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> startFlow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 900);
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
        ],
      ),
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add a music folder'));
    await settle(tester);
  }

  const messages = {
    FolderPickError.unsupportedLocation:
        "That folder can't be used — pick one under Internal storage or the SD "
        'card (not Downloads or a cloud folder)',
    FolderPickError.noFileManager: 'No file manager found to pick a folder',
    FolderPickError.busy: 'The folder picker is already open',
    FolderPickError.unknown: "Couldn't open the folder picker",
  };
  for (final entry in messages.entries) {
    uiTest('a failed pick (${entry.key.name}) is explained', (tester) async {
      h.folderPicker = () async => FolderPickFailed(entry.key);
      await startFlow(tester);
      expect(find.text(entry.value), findsOneWidget);
    });
  }

  uiTest('a cancelled pick shows nothing', (tester) async {
    await startFlow(tester);
    expect(find.byKey(const Key('island')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  uiTest('a refused permission still shows the dialog', (tester) async {
    h.mediaAccess = () async => false;
    await startFlow(tester);
    expect(find.text('Allow access to your music'), findsOneWidget);
  });

  uiTest('a folder with no MP3 files says so', (tester) async {
    h.scanner.onScan = (folder, name) => Stream.value(
      const ScanProgress(
        found: 0,
        processed: 0,
        added: 0,
        unchanged: 0,
        skipped: 0,
        done: true,
      ),
    );
    h.folderPicker = () async => const FolderPicked('/music/Empty');
    await startFlow(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);
    expect(find.text('No MP3 files in Empty'), findsOneWidget);
  });
}
