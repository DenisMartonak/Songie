import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/discord/discord_ipc.dart';
import 'package:songies/discord/discord_presence.dart';
import 'package:songies/player/player_service.dart';

import 'fake_discord.dart';

void main() {
  group('discordActivity', () {
    final start = DateTime.utc(2026, 11, 1, 12);

    test('a YouTube song: listening, cover, button and a progress bar', () {
      final a = discordActivity(
        discordTrack('t1', source: 'yt', videoId: 'abc', album: 'RAM'),
        start: start,
        duration: const Duration(minutes: 4),
      );
      expect(a['type'], 2);
      expect(a['details'], 'Get Lucky');
      expect(a['state'], 'Daft Punk');
      expect(a['timestamps'], {
        'start': start.millisecondsSinceEpoch,
        'end': start.add(const Duration(minutes: 4)).millisecondsSinceEpoch,
      });
      final assets = a['assets']! as Map;
      expect(assets['large_image'], 'https://i.ytimg.com/vi/abc/hqdefault.jpg');
      expect(assets['large_text'], 'RAM');
      expect(assets['small_image'], kDiscordLogoAsset);
      expect(a['buttons'], [
        {
          'label': 'Listen on YouTube Music',
          'url': 'https://music.youtube.com/watch?v=abc',
        },
      ]);
    });

    test('a local file: the Songies logo, no button, no end without a '
        'duration', () {
      final a = discordActivity(discordTrack('t1'), start: start);
      final assets = a['assets']! as Map;
      expect(assets['large_image'], kDiscordLogoAsset);
      expect(assets.containsKey('small_image'), isFalse);
      expect(a.containsKey('buttons'), isFalse);
      expect((a['timestamps']! as Map).containsKey('end'), isFalse);
    });

    test('texts fit Discord: 2 to 128 characters, no empty artist', () {
      final a = discordActivity(
        discordTrack('t1', title: 'x' * 200, artist: ' '),
        start: start,
      );
      expect((a['details']! as String).length, 128);
      expect(a.containsKey('state'), isFalse);
      final b = discordActivity(discordTrack('t2', title: 'A'), start: start);
      expect(b['details'], 'A ');
    });
  });

  group('DiscordPresence', () {
    late FakeDiscord discord;
    late StreamController<PlayerState> states;
    late StreamController<bool> enabled;
    late DateTime now;
    late DiscordPresence presence;

    final song = discordTrack('t1', source: 'yt', videoId: 'abc');
    final other = discordTrack('t2', title: 'Instant Crush');

    PlayerState playing(
      dynamic track, {
      Duration position = Duration.zero,
      bool isPlaying = true,
    }) => PlayerState(
      queue: [track],
      index: 0,
      playing: isPlaying,
      position: position,
      duration: const Duration(minutes: 4),
    );

    Future<void> flush() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() {
      discord = FakeDiscord();
      states = StreamController<PlayerState>();
      enabled = StreamController<bool>();
      now = DateTime.utc(2026, 11, 1, 12);
      presence = DiscordPresence(
        states: states.stream,
        enabled: enabled.stream,
        rpc: DiscordRpc(discord.connect),
        clientId: '123',
        now: () => now,
        settle: Duration.zero,
      );
    });

    tearDown(() => presence.dispose());

    test('off: never reaches Discord', () async {
      enabled.add(false);
      states.add(playing(song));
      await flush();
      expect(discord.connects, 0);
    });

    test('on while playing: connects and shows the song', () async {
      enabled.add(true);
      states.add(playing(song, position: const Duration(seconds: 30)));
      await flush();
      expect(discord.connects, 1);
      final a = discord.activities.single!;
      expect(a['details'], 'Get Lucky');
      expect(
        (a['timestamps']! as Map)['start'],
        now.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch,
      );
    });

    test(
      'position ticks send nothing; a seek, a new song and a pause do',
      () async {
        enabled.add(true);
        states.add(playing(song));
        await flush();
        for (var s = 1; s <= 5; s++) {
          now = now.add(const Duration(seconds: 1));
          states.add(playing(song, position: Duration(seconds: s)));
        }
        await flush();
        expect(discord.activities, hasLength(1));

        // A seek to 2:00.
        states.add(playing(song, position: const Duration(minutes: 2)));
        await flush();
        expect(discord.activities, hasLength(2));

        states.add(playing(other));
        await flush();
        expect(discord.activities.last!['details'], 'Instant Crush');

        states.add(playing(other, isPlaying: false));
        await flush();
        expect(discord.activities.last, isNull);
        expect(discord.activities, hasLength(4));
      },
    );

    test('turning it off clears the status and lets go of Discord', () async {
      enabled.add(true);
      states.add(playing(song));
      await flush();
      enabled.add(false);
      await flush();
      expect(discord.activities.last, isNull);
      expect(discord.pipe!.closed, isTrue);
    });

    test('Discord not running: tries again only after a while', () async {
      discord.running = false;
      enabled.add(true);
      states.add(playing(song));
      await flush();
      states.add(playing(other));
      await flush();
      expect(discord.connects, 1);

      discord.running = true;
      now = now.add(DiscordPresence.retryAfter);
      states.add(playing(song));
      await flush();
      expect(discord.connects, 2);
      expect(discord.activities.single!['details'], 'Get Lucky');
    });

    test('Discord quit mid-session: the next change reconnects', () async {
      enabled.add(true);
      states.add(playing(song));
      await flush();
      discord.dropNextWrite = true;
      states.add(playing(other));
      await flush();
      states.add(playing(song));
      await flush();
      expect(discord.connects, 2);
      expect(discord.activities.last!['details'], 'Get Lucky');
    });
  });
}
