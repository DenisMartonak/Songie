import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/shell/right_pane_state.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = testDb();
    settings = SettingsRepository(db);
  });
  tearDown(() => db.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Keeps the stored flag subscribed and waits for it to load.
  Future<bool?> loadedOpen(ProviderContainer c) async {
    c.listen(rightPaneOpenProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return c.read(rightPaneOpenProvider);
  }

  test('open by default, on Friends', () async {
    final c = container();
    expect(await loadedOpen(c), isTrue);
    expect(c.read(rightPaneContentProvider), RightPaneContent.friends);
  });

  test('null until the setting has loaded', () {
    expect(container().read(rightPaneOpenProvider), isNull);
  });

  test('close is remembered', () async {
    final c = container();
    await loadedOpen(c);
    await c.read(rightPaneProvider).close();
    expect(await loadedOpen(container()), isFalse);
  });

  test(
    'toggle lyrics opens on lyrics; again goes back to friends, still open',
    () async {
      final c = container();
      await loadedOpen(c);
      final pane = c.read(rightPaneProvider);
      await pane.toggle(RightPaneContent.lyrics);
      expect(c.read(rightPaneContentProvider), RightPaneContent.lyrics);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(rightPaneOpenProvider), isTrue);
      await pane.toggle(RightPaneContent.lyrics);
      expect(c.read(rightPaneContentProvider), RightPaneContent.friends);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(rightPaneOpenProvider), isTrue);
    },
  );

  test('toggle queue from closed opens on queue', () async {
    final c = container();
    await loadedOpen(c);
    final pane = c.read(rightPaneProvider);
    await pane.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(rightPaneOpenProvider), isFalse);
    await pane.toggle(RightPaneContent.queue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(rightPaneContentProvider), RightPaneContent.queue);
    expect(c.read(rightPaneOpenProvider), isTrue);
  });

  test('showFriends opens on friends', () async {
    final c = container();
    await loadedOpen(c);
    final pane = c.read(rightPaneProvider);
    await pane.toggle(RightPaneContent.queue);
    await pane.close();
    await pane.showFriends();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(rightPaneContentProvider), RightPaneContent.friends);
    expect(c.read(rightPaneOpenProvider), isTrue);
  });

  test('content is not remembered', () async {
    final c = container();
    await loadedOpen(c);
    await c.read(rightPaneProvider).toggle(RightPaneContent.lyrics);
    final c2 = container();
    await loadedOpen(c2);
    expect(c2.read(rightPaneContentProvider), RightPaneContent.friends);
  });
}
