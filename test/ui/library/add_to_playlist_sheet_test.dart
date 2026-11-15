// Add to playlist: checkboxes that start where the song already is, and
// Save that adds and removes only what changed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/library/favorites.dart';
import 'package:songies/ui/library/add_to_playlist_sheet.dart';

import '../../helpers/ui_harness.dart';

Finder _key(String k) => find.byKey(Key(k));

bool _checked(WidgetTester tester, String id) =>
    tester.widget<Checkbox>(_key('addToPlaylist.check.$id')).value ?? false;

void main() {
  group('playlistSaveMessage', () {
    test('names one playlist, counts several, joins both', () {
      expect(
        playlistSaveMessage(added: ['Rock'], removed: []),
        'Added to Rock',
      );
      expect(
        playlistSaveMessage(added: ['A', 'B', 'C'], removed: []),
        'Added to 3 playlists',
      );
      expect(
        playlistSaveMessage(added: [], removed: ['Rock']),
        'Removed from Rock',
      );
      expect(
        playlistSaveMessage(added: [], removed: ['A', 'B']),
        'Removed from 2 playlists',
      );
      expect(
        playlistSaveMessage(added: ['Rock'], removed: ['Jazz']),
        'Added to Rock · Removed from Jazz',
      );
      expect(playlistSaveMessage(added: [], removed: []), isNull);
    });
  });

  late UiHarness h;

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showAddToPlaylistSheet(context, ref, 't1'),
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
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(_key('addToPlaylist.save'));
    await settle(tester);
  }

  uiTest('boxes start ticked where the song already is', (tester) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    late String rock, jazz;
    await real(tester, () async {
      await h.addTrack('t1');
      rock = await h.addPlaylist('Rock', ['t1']);
      jazz = await h.addPlaylist('Jazz', []);
      final favorites = FavoritesRepository(h.db, h.stamp);
      await favorites.ensureFavorites();
      await favorites.star('t1');
    });
    await open(tester);

    expect(_checked(tester, rock), isTrue);
    expect(_checked(tester, jazz), isFalse);
    expect(_checked(tester, kFavoritesPlaylistId), isTrue);
    expect(find.text('2 selected'), findsOneWidget);
  });

  uiTest('Favorites is pinned first, once', (tester) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    await real(tester, () async {
      await h.addTrack('t1');
      await h.addPlaylist('Rock', []);
      await FavoritesRepository(h.db, h.stamp).ensureFavorites();
    });
    await open(tester);

    expect(_key('addToPlaylist.favorites'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('None selected'), findsOneWidget);
  });

  uiTest('followed playlists are not listed', (tester) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    await real(tester, () async {
      await h.addTrack('t1');
      await h.repo.createFollowedPlaylist(
        code: 'c',
        name: 'Theirs',
        owner: 'o',
      );
    });
    await open(tester);

    expect(find.text('Theirs'), findsNothing);
  });

  uiTest('Save adds, removes and un-stars only what changed', (tester) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    late String rock, jazz, pop;
    await real(tester, () async {
      await h.addTrack('t1');
      await h.addTrack('t2');
      rock = await h.addPlaylist('Rock', ['t1', 't2']);
      jazz = await h.addPlaylist('Jazz', ['t2']);
      pop = await h.addPlaylist('Pop', []);
      final favorites = FavoritesRepository(h.db, h.stamp);
      await favorites.ensureFavorites();
      await favorites.star('t1');
    });
    await open(tester);

    await tester.tap(_key('addToPlaylist.$jazz'));
    await tester.tap(_key('addToPlaylist.$rock'));
    await tester.tap(_key('addToPlaylist.favorites'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await save(tester);

    expect(
      find.text('Added to Jazz · Removed from 2 playlists'),
      findsOneWidget,
    );
    expect(await real(tester, () => h.orderOf(jazz)), ['t2', 't1']);
    expect(await real(tester, () => h.orderOf(rock)), ['t2']);
    expect(await real(tester, () => h.orderOf(pop)), isEmpty);
    final starred = await real(
      tester,
      () => FavoritesRepository(h.db, h.stamp).watchIds().first,
    );
    expect(starred, isNot(contains('t1')));
  });

  uiTest('unticking a song that is in a playlist twice removes both', (
    tester,
  ) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    late String rock;
    await real(tester, () async {
      await h.addTrack('t1');
      rock = await h.addPlaylist('Rock', ['t1', 't1']);
    });
    await open(tester);

    expect(_checked(tester, rock), isTrue);
    await tester.tap(_key('addToPlaylist.$rock'));
    await save(tester);

    expect(find.text('Removed from Rock'), findsOneWidget);
    expect(await real(tester, () => h.orderOf(rock)), isEmpty);
  });

  uiTest('closing without Save changes nothing', (tester) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    late String rock;
    await real(tester, () async {
      await h.addTrack('t1');
      rock = await h.addPlaylist('Rock', []);
    });
    await open(tester);

    await tester.tap(_key('addToPlaylist.$rock'));
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);

    expect(_key('addToPlaylist.sheet'), findsNothing);
    expect(await real(tester, () => h.orderOf(rock)), isEmpty);
  });

  uiTest('+ makes a playlist that shows ticked', (tester) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    await real(tester, () => h.addTrack('t1'));
    await open(tester);

    await tester.tap(_key('addToPlaylist.new'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'New one');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await settle(tester);

    expect(find.text('New one'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    await save(tester);
    expect(find.text('Added to New one'), findsOneWidget);
    final id = (await real(
      tester,
      () => h.repo.watchPlaylists().first,
    )).firstWhere((p) => p.name == 'New one').id;
    expect(await real(tester, () => h.orderOf(id)), ['t1']);
  });

  uiTest('search filters by name', (tester) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    await real(tester, () async {
      await h.addTrack('t1');
      await h.addPlaylist('Rock', []);
      await h.addPlaylist('Jazz', []);
    });
    await open(tester);

    await tester.tap(_key('addToPlaylist.search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ro');
    await tester.pump();

    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Jazz'), findsNothing);
    expect(_key('addToPlaylist.favorites'), findsNothing);
  });

  uiTest('a wide window shows a dialog, a phone a sheet', (tester) async {
    h = await real(tester, UiHarness.create);
    addTearDown(h.dispose);
    await real(tester, () => h.addTrack('t1'));
    await open(tester, size: const Size(1000, 800));
    expect(
      find.ancestor(
        of: _key('addToPlaylist.sheet'),
        matching: find.byType(Dialog),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);

    await open(tester);
    expect(
      find.ancestor(
        of: _key('addToPlaylist.sheet'),
        matching: find.byType(Dialog),
      ),
      findsNothing,
    );
    expect(_key('addToPlaylist.sheet'), findsOneWidget);
  });
}
