import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/update/release.dart';
import 'package:songies/update/update_notifications.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('songies/update_notifier');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AppDatabase db;
  late SettingsRepository settings;
  late List<MethodCall> calls;
  late bool openRequested;
  late int permissionAsks;

  setUp(() {
    db = testDb();
    settings = SettingsRepository(db);
    calls = [];
    openRequested = false;
    permissionAsks = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'takeOpenRequest') return openRequested;
      return null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await db.close();
  });

  ChannelUpdateNotifications make() => ChannelUpdateNotifications(
    settings: settings,
    askPermission: () async => permissionAsks++,
  );

  test(
    'skip tells the background check which version to keep quiet about',
    () async {
      await make().skip(const AppVersion(1, 4, 2));
      expect(calls.single.method, 'skip');
      expect(calls.single.arguments, {'version': '1.4.2'});
    },
  );

  test(
    'takeOpenRequest says whether Songies was opened from the notification',
    () async {
      expect(await make().takeOpenRequest(), isFalse);
      openRequested = true;
      expect(await make().takeOpenRequest(), isTrue);
    },
  );

  test('a tap while Songies runs arrives as an open request', () async {
    final n = make();
    final opens = <void>[];
    final sub = n.openRequests.listen(opens.add);
    addTearDown(sub.cancel);
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('openUpdate')),
      (_) {},
    );
    await pumpEventQueue();
    expect(opens, hasLength(1));
  });

  test('the notification permission is asked once, ever', () async {
    await make().askPermissionOnce();
    await make().askPermissionOnce(); // the next start
    expect(permissionAsks, 1);
  });

  test('a channel failure is swallowed', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'x'),
    );
    await make().skip(const AppVersion(1, 4, 2));
    expect(await make().takeOpenRequest(), isFalse);
  });
}
