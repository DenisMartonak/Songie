import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/ui/settings/crash_reports_settings.dart';

import '../../helpers/ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() async => h = await UiHarness.create());
  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      h.app(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => Scaffold(
              body: ListView(children: const [CrashReportsSettingsSection()]),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  final row = find.byKey(const Key('settings.crashReports'));

  uiTest('the crash report switch is on by default', (tester) async {
    await pump(tester);
    expect(find.text('Crash reports'), findsOneWidget);
    expect(find.text('Send crash reports'), findsOneWidget);
    expect(find.text('Anonymous: no songs, names or files.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(row).value, isTrue);
  });

  uiTest('turning it off stores false and survives a rebuild', (tester) async {
    await pump(tester);
    await tester.tap(row);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(row).value, isFalse);
    final repo = SettingsRepository(h.db);
    expect(await repo.getBool(kCrashReports, fallback: true), isFalse);

    await pump(tester);
    expect(tester.widget<SwitchListTile>(row).value, isFalse);
  });
}
