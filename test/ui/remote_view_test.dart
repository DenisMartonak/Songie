import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/providers.dart';
import 'package:songies/remote/player_view.dart';
import 'package:songies/remote/remote_controller.dart';
import 'package:songies/ui/lyrics/lyrics_view.dart';
import 'package:songies/ui/now_playing/now_playing_header.dart';
import 'package:songies/ui/now_playing/now_playing_queue.dart';
import 'package:songies/ui/playlist/playlist_page.dart';
import 'package:songies/ui/shell/player_bar.dart';

import '../helpers/fake_lyrics_service.dart';
import '../helpers/ui_harness.dart';

Track _track(String id, {String source = 'local', String? title}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: source,
  title: title ?? 'Remote $id',
  artist: source == kRemoteUnknownSource ? '' : 'Artist',
  durationMs: 200000,
  unavailable: false,
  searchText: '',
);

Track _unknown(String id) =>
    _track(id, source: kRemoteUnknownSource, title: 'Unknown song');

/// A view of another device that records the commands the UI sends it.
class _FakeView implements PlayerView {
  _FakeView(this.state);

  final calls = <String>[];
  final _states = StreamController<PlayerState>.broadcast();

  @override
  PlayerState state;

  @override
  Stream<PlayerState> get states => _states.stream;
  @override
  bool get isRemote => true;

  void emit(PlayerState s) {
    state = s;
    _states.add(s);
  }

  Future<void> _log(String call) async => calls.add(call);

  @override
  Future<void> play() => _log('play');
  @override
  Future<void> pause() => _log('pause');
  @override
  Future<void> togglePlay() => _log('togglePlay');
  @override
  Future<void> next() => _log('next');
  @override
  Future<void> previous() => _log('previous');
  @override
  Future<void> seek(Duration d) => _log('seek');
  @override
  Future<void> setVolume(double v) => _log('setVolume');
  @override
  Future<void> setShuffle(bool on) => _log('setShuffle($on)');
  @override
  Future<void> setRepeat(RepeatMode m) => _log('setRepeat(${m.name})');
  @override
  Future<void> playAt(int i) => _log('playAt($i)');
  @override
  Future<void> removeAt(int i) => _log('removeAt($i)');
  @override
  Future<void> move(int from, int to) => _log('move($from,$to)');
  @override
  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    String? sourcePlaylistId,
  }) => _log(
    'playTracks(${[for (final t in tracks) t.id]},$startIndex,$sourcePlaylistId)',
  );
  @override
  Future<void> addNext(List<Track> tracks) =>
      _log('addNext(${[for (final t in tracks) t.id]})');
  @override
  Future<void> addToEnd(List<Track> tracks) =>
      _log('addToEnd(${[for (final t in tracks) t.id]})');
}

void main() {
  late UiHarness h;
  late _FakeView view;
  late FakeLyricsService lyrics;

  setUp(() async {
    h = await UiHarness.create();
    lyrics = FakeLyricsService();
    view = _FakeView(const PlayerState());
  });
  tearDown(() async {
    await h.dispose();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget body, {
    String location = '/',
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      h.app(
        initialLocation: location,
        extraOverrides: [
          playerViewProvider.overrideWithValue(view),
          lyricsServiceProvider.overrideWithValue(lyrics),
        ],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(body: body),
          ),
          GoRoute(
            path: '/playlist/:id',
            builder: (_, state) =>
                Scaffold(body: PlaylistPage(id: state.pathParameters['id']!)),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  uiTest('player bar shows the remote song and its play sends play to the '
      'remote, local player untouched', (tester) async {
    view.state = PlayerState(queue: [_track('r1')], index: 0);
    await pump(tester, const Align(child: PlayerBar()));

    expect(find.text('Remote r1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('playerBar.playPause')));
    await settle(tester);

    expect(view.calls, ['togglePlay']);
    expect(h.player.state.queue, isEmpty);
    expect(h.player.state.playing, isFalse);

    await tester.tap(find.byKey(const Key('playerBar.repeat')));
    await tester.tap(find.byKey(const Key('playerBar.shuffle')));
    await settle(tester);
    expect(view.calls, ['togglePlay', 'setRepeat(all)', 'setShuffle(true)']);
  });

  uiTest('queue reorder and remove go to the view', (tester) async {
    view.state = PlayerState(
      queue: [_track('r1'), _track('r2'), _track('r3'), _track('r4')],
      index: 0,
    );
    await pump(tester, const NowPlayingQueue());

    await tester.timedDrag(
      find.byKey(const Key('queue.handle.1')),
      const Offset(0, 70),
      const Duration(milliseconds: 600),
    );
    await settle(tester);
    expect(view.calls, ['move(1,2)']);

    await tester.drag(find.text('Remote r4'), const Offset(-900, 0));
    await settle(tester);
    expect(view.calls.last, 'removeAt(3)');

    await tester.tap(find.text('Remote r3'));
    await settle(tester);
    expect(view.calls.last, 'playAt(2)');
    expect(h.player.state.queue, isEmpty);
  });

  uiTest('Unknown song shows for a missing id and has no song menu', (
    tester,
  ) async {
    view.state = PlayerState(queue: [_unknown('gone'), _track('r2')], index: 0);
    await pump(
      tester,
      const Column(
        children: [
          NowPlayingHeader(wide: true, onClose: _noop),
          Expanded(child: NowPlayingQueue()),
          PlayerBar(),
        ],
      ),
    );

    expect(find.text('Unknown song'), findsWidgets);
    // No ⋯ in the header.
    expect(find.byKey(const Key('nowPlaying.more')), findsNothing);
    // Long-press on the queue row and right-click on the bar open nothing.
    await tester.longPress(find.byKey(const Key('queue.row.0')));
    await settle(tester);
    expect(find.text('Add to playlist'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(PlayerBar),
        matching: find.text('Unknown song'),
      ),
      buttons: 2,
    );
    await settle(tester);
    expect(find.text('Add to playlist'), findsNothing);
    // A known song still has its menu.
    await tester.longPress(find.byKey(const Key('queue.row.1')));
    await settle(tester);
    expect(find.text('Add to playlist'), findsOneWidget);
  });

  uiTest("lyrics don't look up an unknown song", (tester) async {
    view.state = PlayerState(
      queue: [_unknown('gone'), _unknown('gone2')],
      index: 0,
    );
    await pump(tester, const LyricsView(density: LyricsDensity.large));

    expect(find.text('No lyrics found for this song'), findsOneWidget);
    expect(find.text('Search again'), findsNothing);
    expect(lyrics.lookups, isEmpty);
    expect(lyrics.prefetched, isEmpty);

    // A song in the library is looked up as before.
    await real(tester, () => h.addTrack('r2'));
    view.emit(PlayerState(queue: [_unknown('gone'), _track('r2')], index: 1));
    await settle(tester);
    expect(lyrics.lookups.map((l) => l.id), ['r2']);
  });

  uiTest('playlist Play all plays on the selected device', (tester) async {
    final id = await real(tester, () async {
      await h.addTrack('t1');
      await h.addTrack('t2');
      return h.addPlaylist('Road trip', ['t1', 't2']);
    });
    await pump(tester, const SizedBox(), location: '/playlist/$id');

    await tester.tap(find.byKey(const Key('playlist.play')));
    await settle(tester);
    expect(view.calls, ['setShuffle(false)', 'playTracks([t1, t2],0,$id)']);

    await tester.tap(find.text('Song t2'));
    await settle(tester);
    expect(view.calls.last, 'playTracks([t1, t2],1,$id)');
    expect(h.player.state.queue, isEmpty);
  });
}

void _noop() {}
