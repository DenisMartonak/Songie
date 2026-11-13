import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/friends/friends_backend.dart';
import 'package:songies/friends/friends_service.dart';

import '../helpers/fake_friends_backend.dart';

void main() {
  late FakeFriendsBackend backend;
  late FriendsService service;

  setUp(() {
    backend = FakeFriendsBackend()
      ..addUser('a', 'ann')
      ..addUser('b', 'ben')
      ..addUser('c', 'cat');
    service = FriendsService(backend);
  });

  /// Acts as [id] on the backend, as another device would.
  Future<void> as(String id, Future<void> Function() f) async {
    final before = backend.me;
    backend.me = id;
    await f();
    backend.me = before;
  }

  test('signing in loads; every 5 minutes it refreshes', () {
    fakeAsync((async) {
      backend.me = 'a';
      service.signedIn('a');
      async.flushMicrotasks();
      expect(service.state.loaded, isTrue);
      expect(service.state.incoming, isEmpty);
      as('b', () => backend.send('a'));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 4));
      expect(service.state.incoming, isEmpty);
      async.elapse(const Duration(minutes: 1));
      expect(service.state.incoming.single.username, 'ben');
      expect(service.state.linkOf('b'), FriendLink.incoming);
      service.dispose();
    });
  });

  test('crossed requests end as friends', () async {
    backend.me = 'a';
    await service.signedIn('a');
    await as('b', () => backend.send('a'));
    await service.send('b');
    expect(service.state.friends.single.id, 'b');
    expect(service.state.incoming, isEmpty);
    expect(service.state.outgoing, isEmpty);
    service.dispose();
  });

  test(
    'actions refresh, and failures rethrow without changing state',
    () async {
      backend.me = 'a';
      await service.signedIn('a');
      await service.send('c');
      expect(service.state.linkOf('c'), FriendLink.outgoing);
      backend.error = const FriendsException(FriendsError.offline);
      await expectLater(service.remove('c'), throwsA(isA<FriendsException>()));
      expect(service.state.linkOf('c'), FriendLink.outgoing);
      backend.error = null;
      await service.remove('c');
      expect(service.state.linkOf('c'), isNull);
      service.dispose();
    },
  );

  test('signing out clears at once and stops refreshing', () {
    fakeAsync((async) {
      backend.me = 'a';
      as('b', () => backend.send('a'));
      service.signedIn('a');
      async.flushMicrotasks();
      expect(service.state.incoming, hasLength(1));
      final seen = <FriendsState>[];
      final sub = service.states.listen(seen.add);
      service.signedOut();
      async.flushMicrotasks();
      expect(service.state.incoming, isEmpty);
      expect(service.state.loaded, isFalse);
      expect(seen.last.incoming, isEmpty);
      backend.calls.clear();
      async.elapse(const Duration(minutes: 10));
      expect(backend.calls, isNot(contains('load')));
      sub.cancel();
      service.dispose();
    });
  });

  test('a load that finishes after signing out is dropped', () async {
    backend.me = 'a';
    await as('b', () => backend.send('a'));
    final loading = service.signedIn('a');
    service.signedOut();
    await loading;
    expect(service.state.incoming, isEmpty);
    service.dispose();
  });

  test('a refresh drops someone whose account is gone', () async {
    backend.me = 'a';
    await service.signedIn('a');
    await service.send('b');
    await as('b', () => backend.accept('a'));
    await service.refresh();
    expect(service.state.friends.single.id, 'b');
    backend.deleteUser('b');
    await service.refresh();
    expect(service.state.friends, isEmpty);
    service.dispose();
  });

  test('search under 2 letters asks nothing', () async {
    backend.me = 'a';
    await service.signedIn('a');
    expect(await service.search(' b '), isEmpty);
    expect(backend.calls, isNot(contains('search')));
    expect((await service.search('be')).single.username, 'ben');
    // Never yourself.
    expect(await service.search('an'), isEmpty);
    service.dispose();
  });
}
