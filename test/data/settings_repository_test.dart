import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = testDb();
    repo = SettingsRepository(db);
  });
  tearDown(() => db.close());

  test('unset bool returns the fallback', () async {
    expect(await repo.getBool('wifi_only', fallback: true), isTrue);
    expect(await repo.getBool('wifi_only', fallback: false), isFalse);
  });

  test('set then get round-trips', () async {
    await repo.setBool('wifi_only', false);
    expect(await repo.getBool('wifi_only', fallback: true), isFalse);
    await repo.setBool('wifi_only', true);
    expect(await repo.getBool('wifi_only', fallback: false), isTrue);
  });

  test('strings round-trip and null clears', () async {
    expect(await repo.getString('k'), isNull);
    await repo.setString('k', 'v');
    expect(await repo.getString('k'), 'v');
    await repo.setString('k', null);
    expect(await repo.getString('k'), isNull);
  });

  test('watchBool emits the fallback then changes', () async {
    final seen = <bool>[];
    final sub = repo.watchBool('wifi_only', fallback: true).listen(seen.add);
    await pumpEventQueue();
    await repo.setBool('wifi_only', false);
    await pumpEventQueue();
    await repo.setBool('wifi_only', true);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [true, false, true]);
  });

  test('platform default flags are injectable', () {
    expect(wifiOnlyDefault(isAndroid: true), isTrue);
    expect(wifiOnlyDefault(isAndroid: false), isFalse);
  });
}
