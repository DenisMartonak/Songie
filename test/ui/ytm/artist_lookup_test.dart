import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/providers.dart';
import 'package:songies/ui/ytm/artist_lookup.dart';

import '../../helpers/fake_ytm.dart';
import '../../helpers/ui_harness.dart';

Track _track(String id, {String source = 'yt', String? videoId}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  unavailable: false,
  localSeq: 1,
  source: source,
  title: 'T',
  artist: 'A',
  durationMs: 0,
  searchText: 't a',
  ytVideoId: videoId,
);

Track _yt() => _track('y1', videoId: 'vy1');

YtmRadio _radio(List<YtmArtistRef> artists) => YtmRadio(
  const [],
  null,
  current: YtmSong(
    videoId: 'vy1',
    title: 'T',
    artists: artists,
    durationMs: 1000,
  ),
);

void main() {
  late FakeYtmService ytm;
  late ArtistLookup lookup;
  setUp(() {
    ytm = FakeYtmService();
    lookup = ArtistLookup(ytm);
  });

  test('forTrack of a local track is null without calling YouTube', () async {
    expect(await lookup.forTrack(_track('t1', source: 'local')), isNull);
    expect(ytm.radioCalls, isEmpty);
  });

  test('forTrack of a yt track returns the first artist with a browseId', () async {
    ytm.radioAnswer = Ok(
      _radio(const [
        YtmArtistRef(name: 'A'),
        YtmArtistRef(browseId: 'UC2', name: 'B'),
        YtmArtistRef(browseId: 'UC3', name: 'C'),
      ]),
    );
    expect(await lookup.forTrack(_yt()), 'UC2');
    expect(ytm.radioCalls, ['vy1']);
  });

  test('forTrack caches: two calls, one radio request', () async {
    ytm.radioAnswer = Ok(_radio(const []));
    expect(await lookup.forTrack(_yt()), isNull);
    expect(await lookup.forTrack(_yt()), isNull);
    expect(ytm.radioCalls, hasLength(1));
  });

  test('forTrack after an Err tries again next time', () async {
    ytm.radioAnswer = const Err(Failure(FailureKind.unknown, 'down'));
    expect(await lookup.forTrack(_yt()), isNull);
    ytm.radioAnswer = Ok(
      _radio(const [YtmArtistRef(browseId: 'UC9', name: 'A')]),
    );
    expect(await lookup.forTrack(_yt()), 'UC9');
    expect(ytm.radioCalls, hasLength(2));
  });

  group('openArtist', () {
    late UiHarness h;
    setUp(() async => h = await UiHarness.create());
    tearDown(() => h.dispose());

    uiTest('with no id found opens Search with the name', (tester) async {
      await tester.pumpWidget(
        h.app(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => openArtist(
                    context,
                    ref,
                    track: _yt(),
                    name: 'Nobody',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
            GoRoute(
              path: '/search',
              builder: (_, _) => Consumer(
                builder: (_, ref, _) =>
                    Text('search: ${ref.watch(searchQueryProvider)}'),
              ),
            ),
          ],
        ),
      );
      await settle(tester);
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.text('search: Nobody'), findsOneWidget);
    });
  });
}
