import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';
import 'package:songies/room/room_backend.dart';
import 'package:songies/room/room_protocol.dart';
import 'package:songies/room/room_service.dart';

import 'fake_audio_backend.dart';
import 'fake_remote_hub.dart';
import 'fake_room_hub.dart';
import 'ui_harness.dart';

/// A YouTube track (`source: 'yt'`) that lives only in memory.
Track roomTrack(String id, {String source = 'yt'}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: source,
  ytVideoId: source == 'local' ? null : 'v$id',
  title: 'Song $id',
  artist: 'Artist',
  durationMs: 200000,
  unavailable: false,
  searchText: 'song $id artist',
);

/// The room tables, in memory: every room is `room1` with code `ABCD2345`.
class FakeRoomBackend implements RoomBackend {
  final calls = <String>[];

  @override
  Future<OpenedRoom> open() async {
    calls.add('open');
    return const OpenedRoom(roomId: 'room1', code: 'ABCD2345');
  }

  @override
  Future<String> join(String code) async {
    calls.add('join $code');
    return 'room1';
  }

  @override
  Future<void> leave(String roomId) async => calls.add('leave $roomId');

  @override
  Future<void> remove(String roomId, String userId) async =>
      calls.add('remove $roomId $userId');

  @override
  Future<void> end(String roomId) async => calls.add('end $roomId');
}

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));
}

/// Turns room songs into in-memory tracks (no database).
Future<List<Track?>> roomTracksFor(List<RoomSong> songs) async => [
  for (final s in songs) s.local ? null : roomTrack(s.videoId!.substring(1)),
];

/// Listen together for widget tests: the app's [RoomService] over a fake hub
/// and backend, and another device ([host], named denis) that can host a
/// room the app joins. Make it in `setUp` (its player must start on the real
/// clock).
class RoomRig {
  RoomRig(this.h) {
    hostPlayer = PlayerService(FakeAudioBackend(), _Resolver());
    host = RoomService(
      backend: backend,
      channelFor: (_) => hub.channelFor('h'),
      player: hostPlayer,
      tracksFor: roomTracksFor,
      deviceId: 'h',
      platform: 'linux',
    );
  }

  final UiHarness h;
  final hub = FakeRoomHub();
  final backend = FakeRoomBackend();
  final remoteHub = FakeRemoteHub();
  late final PlayerService hostPlayer;
  late final RoomService host;

  /// The account the app is signed in to; null signed out.
  Profile? profile = const Profile(
    id: 'u1',
    username: 'me',
    email: 'me@example.com',
  );

  /// The app's room service, once the app made it.
  RoomService? service;

  List<Override> get overrides => [
    accountStateProvider.overrideWith(
      (ref) => Stream<AccountState>.value(
        profile == null ? const SignedOut() : SignedIn(profile!),
      ),
    ),
    remoteChannelProvider.overrideWithValue(
      (userId) => remoteHub.channelFor(h.stamp.deviceId),
    ),
    remoteDeviceNameProvider.overrideWith((ref) async => 'This PC'),
    roomServiceProvider.overrideWith((ref) {
      final s = service = RoomService(
        backend: backend,
        channelFor: (_) => hub.channelFor('me'),
        player: ref.watch(playerServiceProvider),
        tracksFor: roomTracksFor,
        deviceId: 'me',
        platform: 'linux',
      );
      ref.onDispose(s.dispose);
      return s;
    }),
  ];

  /// Runs [f] on the test's fake clock until it is done.
  Future<void> run(WidgetTester tester, Future<void> f) async {
    var finished = false;
    unawaited(f.whenComplete(() => finished = true));
    for (var i = 0; i < 40 && !finished; i++) {
      // A player's first command waits on a real-clock microtask.
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(finished, isTrue, reason: 'the room call did not finish');
  }

  /// The other device opens a room playing a song.
  Future<void> hostRoom(WidgetTester tester) => run(
    tester,
    host.open(userId: 'u9', name: 'denis', play: [roomTrack('a')]),
  );

  /// The app joins the other device's room, which then gives it [role].
  Future<void> joinAs(WidgetTester tester, RoomRole role) async {
    await hostRoom(tester);
    await run(tester, service!.join('ABCD2345', userId: 'u1', name: 'me'));
    if (role != RoomRole.listener) {
      await run(tester, host.setRole('me', role));
    }
  }

  /// Someone else's device in the room this app hosts.
  Future<void> guestJoins(
    WidgetTester tester,
    String deviceId,
    String name, {
    String platform = 'android',
  }) async {
    await hub
        .channelFor(deviceId)
        .join(
          RoomPresence(
            userId: 'u-$deviceId',
            deviceId: deviceId,
            name: name,
            platform: platform,
            host: false,
          ),
        );
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Ends everything the test started.
  Future<void> dispose(WidgetTester tester) async {
    unawaited(host.end());
    service?.dispose();
    await tester.pump(const Duration(seconds: 1));
    unawaited(hostPlayer.dispose());
  }
}

/// The container of the app under test.
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));
