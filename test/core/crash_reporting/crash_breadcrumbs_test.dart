import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:songies/core/crash_reporting/crash_breadcrumbs.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/player_service.dart';

Track _track(String id) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Secret Title $id',
  artist: 'Secret Artist',
  durationMs: 200000,
  unavailable: false,
  searchText: 'title $id artist',
);

const _player = {'play', 'pause', 'next', 'previous', 'seek', 'track change'};

void main() {
  testWidgets('routeTemplate gives /playlist/:id for /playlist/abc123', (
    tester,
  ) async {
    final seen = <String>[];
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Text('home'),
          routes: [
            GoRoute(path: 'stats', builder: (_, _) => const Text('stats')),
          ],
        ),
        GoRoute(
          path: '/playlist/:id',
          builder: (_, s) => Text('playlist ${s.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    final stop = followRoutes(router, record: seen.add);
    addTearDown(stop);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.go('/playlist/abc123');
    await tester.pumpAndSettle();
    expect(find.text('playlist abc123'), findsOneWidget);
    expect(seen.last, '/playlist/:id');

    router.go('/home');
    await tester.pumpAndSettle();
    router.push('/playlist/def456');
    await tester.pumpAndSettle();
    expect(seen.last, '/playlist/:id', reason: 'pushed pages count too');

    expect(
      seen.where((t) => t.contains('abc123') || t.contains('def456')),
      isEmpty,
    );
    expect(routeTemplate('/playlist/:id'), '/playlist/:id');
  });

  group('player', () {
    final crumbs = <Breadcrumb>[];

    setUp(() async {
      crumbs.clear();
      await Sentry.init((o) {
        o.dsn = 'https://key@example.invalid/1';
        o.beforeBreadcrumb = (c, _) {
          if (c != null && c.category == 'player') crumbs.add(c);
          return null;
        };
      });
    });

    tearDown(Sentry.close);

    test('recordPlayer emits play, pause and track change without titles', () {
      final a = _track('id-aaa111');
      final b = _track('id-bbb222');
      final idle = const PlayerState();
      final loadedA = PlayerState(queue: [a], index: 0);
      final playingA = PlayerState(queue: [a], index: 0, playing: true);
      final pausedA = PlayerState(queue: [a], index: 0);
      final otherQueue = PlayerState(queue: [b], index: 0);

      recordPlayer(idle, loadedA);
      recordPlayer(loadedA, playingA);
      recordPlayer(playingA, pausedA);
      recordPlayer(pausedA, otherQueue);

      final messages = [for (final c in crumbs) c.message];
      expect(messages, ['track change', 'play', 'pause', 'track change']);
      for (final c in crumbs) {
        expect(_player, contains(c.message));
        final text = '${c.message} ${c.data}';
        expect(text, isNot(contains('Secret')));
        expect(text, isNot(contains('aaa111')));
        expect(text, isNot(contains('bbb222')));
      }
    });

    test('recordPlayer tells next, previous and seek apart', () {
      final queue = [_track('a'), _track('b')];
      final at0 = PlayerState(queue: queue, index: 0, playing: true);
      final at1 = PlayerState(queue: queue, index: 1, playing: true);
      final ticked = PlayerState(
        queue: queue,
        index: 1,
        playing: true,
        position: const Duration(milliseconds: 200),
      );
      final jumped = PlayerState(
        queue: queue,
        index: 1,
        playing: true,
        position: const Duration(seconds: 90),
      );

      recordPlayer(at0, at1);
      recordPlayer(at1, ticked);
      recordPlayer(ticked, jumped);
      recordPlayer(jumped, at0);

      expect([for (final c in crumbs) c.message], ['next', 'seek', 'previous']);
    });

    test('nothing is recorded while Sentry is off', () async {
      await Sentry.close();
      final a = _track('id-aaa111');
      recordPlayer(const PlayerState(), PlayerState(queue: [a], index: 0));
      recordRoute('/home');
      expect(crumbs, isEmpty);
    });
  });
}
