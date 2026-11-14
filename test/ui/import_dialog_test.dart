import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/library/import_dialog.dart';
import 'package:songies/ui/library/library_page.dart';
import 'package:songies/youtube/yt_import_service.dart';
import 'package:songies/youtube/yt_models.dart';

import '../helpers/ui_harness.dart';

const _link = 'https://music.youtube.com/playlist?list=PLabc';

void main() {
  late UiHarness h;

  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pumpLibrary(WidgetTester tester) async {
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
            routes: [
              GoRoute(
                path: 'playlist/:id',
                builder: (_, state) => Scaffold(
                  body: Text('Playlist page ${state.pathParameters['id']}'),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/settings/youtube',
            builder: (_, _) =>
                const Scaffold(body: Text('YouTube settings stub')),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Add'));
    await settle(tester);
    await tester.tap(find.text('Import from YouTube'));
    await settle(tester);
  }

  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await settle(tester);
  }

  uiTest('the dialog shows its title, hint and buttons', (tester) async {
    await pumpLibrary(tester);
    await openDialog(tester);

    expect(find.text('Import from YouTube'), findsOneWidget);
    expect(find.text('Paste a YouTube Music playlist link'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Import'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.importService.imported, isEmpty);
  });

  uiTest('a valid link imports, opens the playlist and says how many', (
    tester,
  ) async {
    h.importService.onImport = (_) async => const Ok(
      ImportResult(playlistId: 'p1', alreadyExisted: false, added: 3),
    );
    await pumpLibrary(tester);
    await openDialog(tester);
    await submit(tester, _link);

    expect(h.importService.imported, [_link]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Playlist page p1'), findsOneWidget);
    expect(find.text('Imported 3 songs'), findsOneWidget);
  });

  uiTest('a new import marks its playlist pending until the page has rows', (
    tester,
  ) async {
    h.importService.onImport = (_) async => const Ok(
      ImportResult(playlistId: 'p1', alreadyExisted: false, added: 3),
    );
    await pumpLibrary(tester);
    await openDialog(tester);
    await submit(tester, _link);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Playlist page p1')),
    );
    expect(container.read(pendingImportsProvider), {'p1'});
  });

  uiTest('re-importing a playlist already in the library marks nothing', (
    tester,
  ) async {
    h.importService.onImport = (_) async => const Ok(
      ImportResult(playlistId: 'p1', alreadyExisted: true, added: 0),
    );
    await pumpLibrary(tester);
    await openDialog(tester);
    await submit(tester, _link);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Playlist page p1')),
    );
    expect(container.read(pendingImportsProvider), isEmpty);
  });

  uiTest('while importing it shows a spinner and cannot submit twice', (
    tester,
  ) async {
    final done = Completer<Result<ImportResult>>();
    h.importService.onImport = (_) => done.future;
    await pumpLibrary(tester);
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), _link);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump();

    expect(find.text('Importing…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import'),
    );
    expect(button.onPressed, isNull);

    done.complete(
      const Ok(ImportResult(playlistId: 'p1', alreadyExisted: false, added: 1)),
    );
    await settle(tester);
    expect(h.importService.imported, hasLength(1));
    expect(find.text('Playlist page p1'), findsOneWidget);
  });

  uiTest('an invalid link shows the message inline and stays put', (
    tester,
  ) async {
    h.importService.onImport = (_) async => const Err(
      Failure(FailureKind.invalidInput, 'Not a YouTube playlist link'),
    );
    await pumpLibrary(tester);
    await openDialog(tester);
    await submit(tester, 'hello');

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Not a YouTube playlist link'), findsOneWidget);
    expect(find.textContaining('Playlist page'), findsNothing);
  });

  uiTest('a playlist already in the library opens it and suggests Sync', (
    tester,
  ) async {
    h.importService.onImport = (_) async => const Ok(
      ImportResult(playlistId: 'p9', alreadyExisted: true, added: 0),
    );
    await pumpLibrary(tester);
    await openDialog(tester);
    await submit(tester, _link);

    expect(find.text('Playlist page p9'), findsOneWidget);
    expect(
      find.text('Already in your library — use Sync to update it'),
      findsOneWidget,
    );
  });

  uiTest('missing yt-dlp explains and offers to open Settings', (tester) async {
    h.importService.onImport = (_) async =>
        Err(ytFailure(YtErrorKind.missingBinary, 'not installed'));
    await pumpLibrary(tester);
    await openDialog(tester);
    await submit(tester, _link);

    expect(
      find.text("yt-dlp isn't installed — install it in Settings"),
      findsOneWidget,
    );
    await tester.tap(find.text('Open Settings'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('YouTube settings stub'), findsOneWidget);
  });

  uiTest('a throwing import does not leave the dialog busy', (tester) async {
    h.importService.onImport = (_) async => throw StateError('boom');
    await pumpLibrary(tester);
    await openDialog(tester);
    await submit(tester, _link);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Importing…'), findsNothing);
    expect(find.text('Something went wrong — try again'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import'),
    );
    expect(button.onPressed, isNotNull);
  });

  uiTest('an extractor error shows the update hint inline', (tester) async {
    h.importService.onImport = (_) async =>
        Err(ytFailure(YtErrorKind.extractor, 'boom'));
    await pumpLibrary(tester);
    await openDialog(tester);
    await submit(tester, _link);

    expect(
      find.text('YouTube changed something — try Settings → Update yt-dlp'),
      findsOneWidget,
    );
    expect(find.text('Open Settings'), findsNothing);
  });

  uiTest('a shared link opens the dialog prefilled', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => showImportDialog(context, initialLink: _link),
                child: const Text('share'),
              ),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
    await tester.tap(find.text('share'));
    await settle(tester);

    expect(find.text('Import from YouTube'), findsOneWidget);
    expect(find.text(_link), findsOneWidget);
  });
}
