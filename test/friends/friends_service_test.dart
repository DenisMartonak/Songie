import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/friends/activity_backend.dart';
import 'package:songies/friends/friends_backend.dart';
import 'package:songies/friends/friends_service.dart';

import '../helpers/fake_activity_backend.dart';
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

  test('a new listener gets the current state first, then changes', () async {
    backend.me = 'a';
    await service.signedIn('a');
    await service.send('b');
    final seen = <FriendsState>[];
    final sub = service.states.listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.linkOf('b'), FriendLink.outgoing);
    await service.remove('b');
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.linkOf('b'), isNull);
    await sub.cancel();
    service.dispose();
  });

  test('an older load landing last does not undo a newer one', () async {
    backend.me = 'a';
    await as('b', () => backend.send('a'));
    await service.signedIn('a');
    expect(service.state.linkOf('b'), FriendLink.incoming);
    // A slow refresh (say, opening the Friends page) is under way...
    final slow = Completer<void>();
    backend.loadGates.add(slow.future);
    final r1 = service.refresh();
    await Future<void>.delayed(Duration.zero);
    // ...when the request is accepted, and that refresh lands first.
    await service.accept('b');
    expect(service.state.linkOf('b'), FriendLink.friend);
    slow.complete();
    await r1;
    expect(service.state.linkOf('b'), FriendLink.friend);
    service.dispose();
  });

  group('activity', () {
    late FakeActivityBackend activity;
    const halo = NowPlaying(title: 'Halo', artist: 'Beyonce');

    setUp(() {
      activity = FakeActivityBackend()
        ..friendsOf = (id) => id == 'a' ? {'b'} : {'a'};
      service = FriendsService(backend, activity: activity);
    });

    /// Acts as friend b on the activity server.
    Future<void> asB(Future<void> Function() f) async {
      activity.me = 'b';
      await f();
      activity.me = 'a';
    }

    Future<void> befriend() async {
      backend.me = 'a';
      await service.signedIn('a');
      await service.send('b');
      await as('b', () => backend.accept('a'));
    }

    test("refresh brings friends' activity", () async {
      await befriend();
      await asB(() => activity.publishNowPlaying(halo, roomCode: 'ABCD2345'));
      await service.refresh();
      expect(service.state.activity['b']!.nowPlaying, halo);
      expect(service.state.activity['b']!.roomCode, 'ABCD2345');
      expect(service.state.listening('b', DateTime.now()), isTrue);
      service.dispose();
    });

    test(
      'a friend who stops sharing loses their status at the next refresh',
      () async {
        await befriend();
        await asB(() => activity.publishNowPlaying(halo));
        await service.refresh();
        await asB(() => activity.setSharing(listening: false));
        await service.refresh();
        expect(service.state.activity['b']!.nowPlaying, isNull);
        expect(service.state.listening('b', DateTime.now()), isFalse);
        service.dispose();
      },
    );

    test('a status older than 15 minutes is not listening', () async {
      await befriend();
      await asB(() => activity.publishNowPlaying(halo));
      await service.refresh();
      final later = DateTime.now().add(const Duration(minutes: 16));
      expect(service.state.listening('b', later), isFalse);
      service.dispose();
    });

    test(
      'a failed activity fetch keeps the friends and the old activity',
      () async {
        await befriend();
        await asB(() => activity.publishNowPlaying(halo));
        await service.refresh();
        activity.error = const FriendsException(FriendsError.offline);
        await service.refresh();
        expect(service.state.friends.single.id, 'b');
        expect(service.state.activity['b']!.nowPlaying, halo);
        service.dispose();
      },
    );

    test('watching closely refreshes every minute until released', () {
      fakeAsync((async) {
        backend.me = 'a';
        service.signedIn('a');
        async.flushMicrotasks();
        backend.calls.clear();
        final token = service.watchClosely();
        async.elapse(const Duration(minutes: 3));
        expect(backend.calls.where((c) => c == 'load'), hasLength(3));
        service.stopWatching(token);
        backend.calls.clear();
        // Until the regular 5-minute refresh, nothing more.
        async.elapse(const Duration(seconds: 110));
        expect(backend.calls, isEmpty);
        service.dispose();
      });
    });
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
