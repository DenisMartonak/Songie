import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/update/release.dart';
import 'package:songies/update/update_checker.dart';

import '../helpers/test_db.dart';

Map<String, Object?> releaseJson(String tag, {bool withApk = true}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/o/r/releases/tag/$tag',
  'body': 'notes',
  'assets': [
    if (withApk)
      {
        'name': 'songies-${tag.substring(1)}.apk',
        'browser_download_url': 'https://example.test/a.apk',
        'size': 10,
      },
  ],
};

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  var clock = DateTime(2026, 10, 31, 12);
  var calls = 0;
  Object? Function() response = () => releaseJson('v1.1.0');

  UpdateChecker checker({AppVersion? current}) => UpdateChecker(
    fetch: (url) async {
      calls++;
      expect(url.host, 'api.github.com');
      expect(url.path, '/repos/DenisMartonak/Songie/releases/latest');
      final r = response();
      if (r is Exception) throw r;
      return r as Map<String, Object?>?;
    },
    settings: settings,
    current: current ?? const AppVersion(1, 0, 0),
    platform: UpdatePlatform.android,
    now: () => clock,
  );

  setUp(() {
    db = testDb();
    settings = SettingsRepository(db);
    clock = DateTime(2026, 10, 31, 12);
    calls = 0;
    response = () => releaseJson('v1.1.0');
  });
  tearDown(() => db.close());

  test('startup check is throttled for 12 hours', () async {
    final c = checker();
    expect(await c.checkAtStartup(), isA<UpdateAvailable>());
    expect(
      await settings.getString(kUpdateLastCheckMs),
      '${clock.millisecondsSinceEpoch}',
    );
    clock = clock.add(const Duration(hours: 11));
    expect(await c.checkAtStartup(), isNull);
    expect(calls, 1);
    clock = clock.add(const Duration(hours: 2));
    expect(await c.checkAtStartup(), isA<UpdateAvailable>());
    expect(calls, 2);
  });

  test('startup check stays quiet for the skipped version but offers a newer '
      'one', () async {
    final c = checker();
    await c.skip(const AppVersion(1, 1, 0));
    expect(await settings.getString(kUpdateSkippedVersion), '1.1.0');
    expect(await c.checkAtStartup(), isNull);
    expect(await settings.getString(kUpdateLastCheckMs), isNotNull);
    clock = clock.add(const Duration(hours: 13));
    response = () => releaseJson('v1.2.0');
    final r = await c.checkAtStartup();
    expect(r, isA<UpdateAvailable>());
    expect((r! as UpdateAvailable).release.version, const AppVersion(1, 2, 0));
  });

  test('checkNow ignores skip and throttle', () async {
    final c = checker();
    await c.skip(const AppVersion(1, 1, 0));
    await c.checkAtStartup();
    expect(await c.checkNow(), isA<UpdateAvailable>());
  });

  test('404 is UpToDate', () async {
    response = () => null;
    expect(await checker().checkNow(), isA<UpToDate>());
  });

  test('same or older version is UpToDate', () async {
    expect(
      await checker(current: const AppVersion(1, 1, 0)).checkNow(),
      isA<UpToDate>(),
    );
  });

  test('network error at startup returns CheckFailed silently and never '
      'throws', () async {
    response = () => Exception('offline');
    expect(await checker().checkAtStartup(), isA<CheckFailed>());
    expect(await checker().checkNow(), isA<CheckFailed>());
  });

  test('malformed payload is CheckFailed, not a throw', () async {
    response = () => {'tag_name': 'v1.1.0', 'html_url': 5};
    expect(await checker().checkNow(), isA<CheckFailed>());
  });

  test("release without this platform's asset is UpToDate", () async {
    response = () => releaseJson('v1.1.0', withApk: false);
    expect(await checker().checkNow(), isA<UpToDate>());
  });
}
