import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/account/account_backend.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/providers.dart';

import 'fake_account_backend.dart';

void main() {
  test(
    'Supabase init failing leaves the app signed out and logs a warning',
    () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = original);

      final service = AccountService(
        PendingAccountBackend(Future.error(Exception('unreachable'))),
      );
      addTearDown(service.dispose);
      await pumpEventQueue();
      expect(service.state, isA<SignedOut>());
      expect(logs.where((l) => l.contains(' W ')), isNotEmpty);
      await expectLater(
        service.logIn('a@b.c', 'password1'),
        throwsA(
          isA<AccountException>().having(
            (e) => e.error,
            'error',
            AccountError.offline,
          ),
        ),
      );
    },
  );

  test(
    'a pending backend passes calls and user changes through once ready',
    () async {
      final fake = FakeAccountBackend();
      final service = AccountService(PendingAccountBackend(Future.value(fake)));
      addTearDown(service.dispose);
      await service.signUp('a@b.c', 'password1', 'den');
      await service.verifySignup('a@b.c', fake.goodCode);
      expect(service.state, isA<SignedIn>());
      fake.emitUser(null);
      await pumpEventQueue();
      expect(service.state, isA<SignedOut>());
    },
  );

  test('accountStateProvider starts with the current state', () async {
    final fake = FakeAccountBackend();
    final service = AccountService(fake);
    addTearDown(service.dispose);
    final container = ProviderContainer(
      overrides: [accountServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final seen = <AccountState>[];
    container.listen(accountStateProvider, (_, next) {
      if (next.hasValue) seen.add(next.requireValue);
    }, fireImmediately: true);
    await pumpEventQueue();
    expect(seen.single, isA<SignedOut>());
    await service.signUp('a@b.c', 'password1', 'den');
    await service.verifySignup('a@b.c', fake.goodCode);
    await pumpEventQueue();
    expect(seen.last, isA<SignedIn>());
  });
}
