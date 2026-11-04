import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/island/island_controller.dart';
import 'package:songies/ui/island/island_host.dart';
import 'package:songies/ui/library/add_to_playlist_sheet.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/theme/theme_repository.dart';
import 'package:songies/ui/settings/themes/theme_file.dart';
import 'package:songies/ui/shell/player_error_islands.dart';
import 'package:songies/ui/widgets/artwork.dart';

import '../../helpers/ui_harness.dart';
import '../settings/themes/theme_test_harness.dart';

final _island = find.byKey(const Key('island'));

void main() {
  uiTest('removing a song from a playlist shows an island with its cover and '
      'Undo', (tester) async {
    final h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final id = await real(tester, () async {
      await h.addTrack('t1', title: 'Song one');
      await h.addTrack('t2', title: 'Song two');
      return h.addPlaylist('Road trip', ['t1', 't2']);
    });
    await tester.pumpWidget(
      h.app(
        initialLocation: '/playlist/$id',
        routes: [
          GoRoute(
            path: '/playlist/:id',
            builder: (_, state) =>
                Scaffold(body: PlaylistPage(id: state.pathParameters['id']!)),
          ),
        ],
      ),
    );
    await settle(tester);

    await tester.drag(find.text('Song one'), const Offset(-700, 0));
    await settle(tester);

    expect(
      find.descendant(of: _island, matching: find.text('Removed Song one')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _island, matching: find.byType(Artwork)),
      findsOneWidget,
    );
    expect(find.descendant(of: _island, matching: find.text('Undo')), findsOne);
    expect(await real(tester, () => h.orderOf(id)), ['t2']);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await real(tester, () => h.orderOf(id)), ['t1', 't2']);
  });

  group('player errors', () {
    late StreamController<PlayerState> states;

    setUp(() => states = StreamController<PlayerState>.broadcast());
    tearDown(() => states.close());

    uiTest('a player error shows a failure island with Sign in for '
        'age-restricted songs', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: PlayerErrorIslands(child: SizedBox())),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: Text('settings page')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playerStateProvider.overrideWith((ref) => states.stream)],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, c) => IslandHost(child: c!),
          ),
        ),
      );
      states.add(const PlayerState());
      await tester.pump();
      await tester.pump();
      states.add(
        const PlayerState(
          notice: PlayerNotice(
            trackTitle: 'Song',
            reason: 'ytdlp:ageRestricted:x',
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(_island, findsOneWidget);
      expect(
        find.descendant(
          of: _island,
          matching: find.byIcon(Icons.warning_amber_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _island, matching: find.text('Sign in')),
        findsOneWidget,
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('settings page'), findsOneWidget);
    });
  });

  uiTest('an Add to playlist failure shows above the open sheet', (
    tester,
  ) async {
    final h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    h.repo = _FailingCreate(h.db, h.stamp);
    await real(tester, () => h.addTrack('t1'));
    late Islands islands;
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () {
                    islands = Islands.of(context);
                    showAddToPlaylistSheet(context, ref, ['t1']);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Open'));
    await settle(tester);
    expect(find.byKey(const Key('addToPlaylist.sheet')), findsOneWidget);

    islands.show("Couldn't add to Gym", kind: IslandKind.failure);
    await settle(tester);
    expect(find.text("Couldn't add to Gym"), findsOneWidget);
    expect(_island.hitTestable(), findsOneWidget);
    expect(tester.getRect(_island).bottom, closeTo(800 - 16, 1));

    islands.clear();
    await settle(tester);

    // And the real failure, once the sheet and the name dialog are done.
    await tester.tap(find.byKey(const Key('addToPlaylist.new')));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Gym');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(find.text("Couldn't create playlist"), findsOneWidget);
    expect(_island, findsOneWidget);
  });

  uiTest('no SnackBar is ever shown', (tester) async {
    final t = await real(tester, ThemeHarness.create);
    addTearDown(t.dispose);
    await t.pump(
      tester,
      location: '/settings/themes',
      extraOverrides: [
        themeFileSaverProvider.overrideWithValue((name, bytes) async => true),
      ],
    );
    await tester.tap(find.byKey(Key('themes.menu.$kTerminalThemeId')));
    await settle(tester);
    await tester.tap(find.text('Export'));
    await settle(tester);
    expect(find.text('Theme exported'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(_island, findsOneWidget);
  });
}

/// A library repository that cannot create playlists.
class _FailingCreate extends LibraryRepository {
  _FailingCreate(super.db, super.stamp);

  @override
  Future<Result<String>> createPlaylist(String name) async =>
      const Err(Failure(FailureKind.unknown, 'boom'));
}
