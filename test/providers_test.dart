import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';

import 'helpers/fake_audio_backend.dart';

class _NoResolver implements TrackResolver {
  @override
  Future<Never> resolve(track) => throw UnimplementedError();
}

void main() {
  late PlayerService player;
  late ProviderContainer container;

  setUp(() {
    player = PlayerService(FakeAudioBackend(), _NoResolver());
    container = ProviderContainer(
      overrides: [playerServiceProvider.overrideWithValue(player)],
    );
  });

  tearDown(() async {
    container.dispose();
    await player.dispose();
  });

  test('playerStateProvider starts with the current state', () async {
    player.setShuffle(true);
    final values = <PlayerState>[];
    container.listen(playerStateProvider, (_, next) {
      if (next.hasValue) values.add(next.requireValue);
    });
    await pumpEventQueue();
    expect(values.last.shuffle, isTrue);
  });

  test(
    'an update emitted as soon as the first value arrives is kept',
    () async {
      final values = <PlayerState>[];
      container.listen(playerStateProvider, (_, next) {
        if (!next.hasValue) return;
        values.add(next.requireValue);
        // Right between the seed and the live stream: must not be lost.
        if (values.length == 1) player.setShuffle(true);
      });
      await pumpEventQueue();
      expect(values.first.shuffle, isFalse);
      expect(values.last.shuffle, isTrue);
    },
  );

  test('searchQueryProvider starts empty and holds what is written', () {
    expect(container.read(searchQueryProvider), '');
    container.read(searchQueryProvider.notifier).set('beyonce');
    expect(container.read(searchQueryProvider), 'beyonce');
  });
}
