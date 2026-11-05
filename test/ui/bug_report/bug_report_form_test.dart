import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:songies/bug_report/bug_report.dart';
import 'package:songies/bug_report/bug_report_sender.dart';
import 'package:songies/core/log.dart';
import 'package:songies/core/paths.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/bug_report/bug_report_form.dart';
import 'package:songies/ui/settings/settings_page.dart';
import 'package:songies/ui/settings/storage_usage.dart';

import '../../helpers/ui_harness.dart';

const _webhook = 'https://discord.example/api/webhooks/1/x';

void main() {
  late UiHarness h;
  late Directory tmp;
  late List<http.BaseRequest> requests;
  late int status;
  Completer<void>? hold;
  late DateTime clock;
  late Screenshot? pick;

  setUp(() async {
    h = await UiHarness.create();
    tmp = Directory.systemTemp.createTempSync('songies_bug_');
    h.paths = AppPaths.at(tmp);
    await h.paths!.ensureCreated();
    await AppLog.init(h.paths!.logs);
    requests = [];
    status = 204;
    clock = DateTime.utc(2026, 11, 5, 12);
    pick = null;
  });
  tearDown(() async {
    await h.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    bool built = true,
    double width = 800,
    bool nested = false,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((r) async {
      await hold?.future;
      return http.Response('', status);
    });
    final recording = _Recording(client, requests);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        extraOverrides: [
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(artBytes: 0, databaseBytes: 0),
          ),
          bugReportsBuiltProvider.overrideWithValue(built),
          bugReportSenderProvider.overrideWithValue(
            BugReportSender(
              client: recording,
              webhook: _webhook,
              now: () => clock,
            ),
          ),
          deviceSummaryProvider.overrideWithValue(
            () async => const DeviceSummary(
              platform: 'linux',
              os: 'Linux 6',
              model: 'desktop',
            ),
          ),
          screenshotPickerProvider.overrideWithValue(() async => pick),
        ],
        routes: [
          GoRoute(
            path: '/settings',
            // [nested]: Settings inside its own navigator, like a shell branch.
            builder: (_, _) => nested
                ? Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: SettingsPage()),
                    ),
                  )
                : const Scaffold(body: SettingsPage()),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> openForm(WidgetTester tester) async {
    final button = find.byKey(const Key('settings.reportBug'));
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await settle(tester);
  }

  /// Lets a send finish: its file, database and HTTP work spans both clocks.
  Future<void> afterSend(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      // The log is read on another isolate, which takes real time.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await flush(tester);
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> fill(
    WidgetTester tester, [
    String text = 'It crashed badly',
  ]) async {
    await tester.enterText(
      find.byKey(const Key('bugReport.description')),
      text,
    );
    await tester.pump();
  }

  bool sendEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const Key('bugReport.send')))
      .enabled;

  uiTest('no Report a bug entry when the webhook is not built in', (
    tester,
  ) async {
    await pump(tester, built: false);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pump();
    expect(find.byKey(const Key('settings.reportBug')), findsNothing);
    expect(find.text('Report a bug'), findsNothing);
    expect(find.text('Check for updates'), findsOneWidget);
  });

  uiTest('Settings shows Report a bug directly above Check for updates and '
      'it opens the form', (tester) async {
    await pump(tester);
    final button = find.byKey(const Key('settings.reportBug'));
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('settings.checkForUpdates')),
    );
    await tester.pump();
    final bug = tester.getRect(button);
    final update = tester.getRect(
      find.byKey(const Key('settings.checkForUpdates')),
    );
    expect(bug.bottom, lessThanOrEqualTo(update.top));
    expect(bug.left, update.left);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.bug_report_outlined),
      ),
      findsOneWidget,
    );
    await openForm(tester);
    expect(find.text('What happened?'), findsOneWidget);
    expect(find.text('Your name (optional)'), findsOneWidget);
    expect(find.text('Attach screenshot'), findsOneWidget);
    expect(
      find.text("Includes the app version, your device and the app's log."),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
  });

  uiTest('Send is disabled until the description has 10 characters', (
    tester,
  ) async {
    await pump(tester);
    await openForm(tester);
    expect(sendEnabled(tester), isFalse);
    await fill(tester, '   short   ');
    await tester.pump();
    expect(sendEnabled(tester), isFalse);
    await fill(tester, 'ten chars!');
    await tester.pump();
    expect(sendEnabled(tester), isTrue);
  });

  uiTest('the name is prefilled from the last report', (tester) async {
    await real(
      tester,
      () => SettingsRepository(h.db).setString(kBugReportName, 'Mira'),
    );
    await pump(tester);
    await openForm(tester);
    final field = tester.widget<TextField>(
      find.byKey(const Key('bugReport.name')),
    );
    expect(field.controller!.text, 'Mira');
  });

  uiTest('attaching a screenshot shows a thumbnail that can be removed; '
      'an 8 MB image is refused', (tester) async {
    await pump(tester);
    await openForm(tester);
    pick = (fileName: 'big.png', size: 8 * 1024 * 1024, bytes: null);
    await tester.tap(find.byKey(const Key('bugReport.attach')));
    await settle(tester);
    expect(find.text('That image is too big'), findsOneWidget);
    expect(find.byKey(const Key('bugReport.thumbnail')), findsNothing);

    pick = (fileName: 'ok.png', size: 100, bytes: Uint8List(100));
    await tester.tap(find.byKey(const Key('bugReport.attach')));
    await settle(tester);
    expect(find.byKey(const Key('bugReport.thumbnail')), findsOneWidget);
    expect(find.text('ok.png'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bugReport.removeScreenshot')));
    await tester.pump();
    expect(find.byKey(const Key('bugReport.thumbnail')), findsNothing);
    expect(find.text('Attach screenshot'), findsOneWidget);
  });

  uiTest('a successful send closes the form, shows the island and keeps '
      'the name', (tester) async {
    await pump(tester);
    await openForm(tester);
    await fill(tester);
    await tester.enterText(find.byKey(const Key('bugReport.name')), ' Mira ');
    await tester.tap(find.byKey(const Key('bugReport.send')));
    await afterSend(tester);
    expect(requests, hasLength(1));
    expect(requests.single.url.toString(), _webhook);
    expect(find.text('What happened?'), findsNothing);
    expect(find.text('Bug report sent'), findsOneWidget);
    final saved = await real(
      tester,
      () => SettingsRepository(h.db).getString(kBugReportName),
    );
    expect(saved, 'Mira');
    await tester.pump(const Duration(seconds: 10));
  });

  uiTest('a failed send keeps the form filled and shows the inline error; '
      'Send works again', (tester) async {
    status = 500;
    await pump(tester);
    await openForm(tester);
    await fill(tester);
    await tester.tap(find.byKey(const Key('bugReport.send')));
    await afterSend(tester);
    expect(
      find.text("Couldn't send. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.text('It crashed badly'), findsOneWidget);
    expect(sendEnabled(tester), isTrue);
    status = 204;
    await tester.tap(find.byKey(const Key('bugReport.send')));
    await afterSend(tester);
    expect(requests, hasLength(2));
    expect(find.text('What happened?'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });

  uiTest('a second report within a minute shows the too-soon message', (
    tester,
  ) async {
    await pump(tester);
    await openForm(tester);
    await fill(tester);
    await tester.tap(find.byKey(const Key('bugReport.send')));
    await afterSend(tester);
    await tester.pump(const Duration(seconds: 10));
    await openForm(tester);
    await fill(tester);
    await tester.tap(find.byKey(const Key('bugReport.send')));
    await afterSend(tester);
    expect(
      find.text('You just sent one. Try again in a minute.'),
      findsOneWidget,
    );
    expect(requests, hasLength(1));
  });

  uiTest('the form cannot be dismissed while sending, and a success closes '
      'only the form', (tester) async {
    hold = Completer<void>();
    await pump(tester);
    await openForm(tester);
    await fill(tester);
    await tester.tap(find.byKey(const Key('bugReport.send')));
    await flush(tester);
    // Barrier tap, Esc and system back all leave the form open.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await Navigator.of(tester.element(find.byType(BugReportForm))).maybePop();
    // A dismissed route needs a few frames to leave the tree.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(BugReportForm), findsOneWidget);
    hold!.complete();
    await afterSend(tester);
    expect(find.byType(BugReportForm), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  uiTest('desktop width opens a dialog, phone width a full page', (
    tester,
  ) async {
    await pump(tester);
    await openForm(tester);
    expect(find.byType(Dialog), findsOneWidget);
  });

  uiTest('the phone page is on the root navigator, above a shell branch', (
    tester,
  ) async {
    await pump(tester, width: 500, nested: true);
    await openForm(tester);
    final ctx = tester.element(find.byType(BugReportForm));
    expect(
      Navigator.of(ctx),
      same(Navigator.of(ctx, rootNavigator: true)),
      reason: 'a branch navigator would keep the tab bar and mini player',
    );
  });

  uiTest('a success after the form is no longer on top still ends the '
      'sending state', (tester) async {
    hold = Completer<void>();
    await pump(tester, width: 500);
    await openForm(tester);
    await fill(tester);
    await tester.tap(find.byKey(const Key('bugReport.send')));
    await flush(tester);
    // Another page lands on top while the report is on its way.
    final ctx = tester.element(find.byType(BugReportForm));
    unawaited(
      Navigator.of(ctx).push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Other'))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    hold!.complete();
    await afterSend(tester);
    expect(find.text('Bug report sent'), findsOneWidget);
    expect(
      find.byType(BugReportForm, skipOffstage: false),
      findsNothing,
      reason: 'route removed',
    );
    expect(find.text('Other'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  uiTest('the thumbnail is decoded at thumbnail size', (tester) async {
    await pump(tester);
    await openForm(tester);
    pick = (fileName: 'ok.png', size: 100, bytes: Uint8List(100));
    await tester.tap(find.byKey(const Key('bugReport.attach')));
    await settle(tester);
    final image = tester.widget<Image>(
      find.byKey(const Key('bugReport.thumbnail')),
    );
    expect((image.image as ResizeImage).width, 112);
  });

  uiTest('phone width opens a full page', (tester) async {
    await pump(tester, width: 500);
    await openForm(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BugReportForm), findsOneWidget);
    expect(tester.getSize(find.byType(Scaffold).last).width, 500);
  });
}

/// Records what is sent, then answers like [_inner].
class _Recording extends http.BaseClient {
  _Recording(this._inner, this.requests);
  final http.Client _inner;
  final List<http.BaseRequest> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return _inner.send(request);
  }
}
