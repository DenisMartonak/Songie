import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/account/account_service.dart';
import 'package:songies/core/app_version.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/player/audio_backend.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';
import 'package:songies/remote/remote_controller.dart';
import 'package:songies/remote/remote_protocol.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/fake_cloud_sync.dart';
import 'helpers/fake_remote_hub.dart';
import 'helpers/test_db.dart';

class _NoResolver extends TrackResolver {
  @override
  Future<Never> resolve(track) => throw UnimplementedError();
}

class _Resolver extends TrackResolver {
  @override
  Future<Result<AudioSourceRef>> resolve(Track t) async =>
      Ok(FileSource('/music/${t.id}.mp3'));

  @override
  Future<void> prefetch(Track t) async {}

  @override
  void invalidate(Track t) {}
}

Track track(String id) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: 'local',
  title: 'Title $id',
  artist: 'Artist',
  durationMs: 0,
  unavailable: false,
  searchText: 'title $id artist',
);

RemotePresence presenceOf(String id) => RemotePresence(
  deviceId: id,
  name: 'Device $id',
  platform: 'linux',
  appVersion: '1.0.0',
  playing: false,
);

SignedIn signedIn(String id) =>
    SignedIn(Profile(id: id, username: 'user$id', email: '$id@example.com'));

void main() {
  group('player state', () {
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
  });

  group('remote', () {
    late AppDatabase db;
    late SyncStamp stamp;
    late FakeCloudSync cloud;
    late PlayerService player;
    late FakeRemoteHub hub;
    late ProviderContainer container;
    late StreamController<AccountState> accountChanges;
    late AccountState account;
    late List<String> channelUsers;
    late List<Override> overrides;

    String me() => stamp.deviceId;

    /// The devices 'o' sees on the channel.
    List<String> seenByOther() => [
      for (final p in hub.channelFor('o').present) p.deviceId,
    ];

    void setAccount(AccountState s) {
      account = s;
      accountChanges.add(s);
    }

    RemoteController controller() => container.read(remoteControllerProvider)!;

    setUp(() async {
      db = testDb();
      stamp = await SyncStamp.load(db);
      cloud = FakeCloudSync(db, stamp);
      player = PlayerService(FakeAudioBackend(), _Resolver());
      hub = FakeRemoteHub();
      accountChanges = StreamController<AccountState>.broadcast();
      account = const SignedOut();
      channelUsers = [];
      overrides = [
        playerServiceProvider.overrideWithValue(player),
        syncStampProvider.overrideWithValue(stamp),
        libraryRepositoryProvider.overrideWithValue(
          LibraryRepository(db, stamp),
        ),
        cloudSyncProvider.overrideWithValue(cloud),
        accountStateProvider.overrideWith(
          (ref) => Stream<AccountState>.multi((c) {
            c.addSync(account);
            final sub = accountChanges.stream.listen(c.addSync);
            c.onCancel = sub.cancel;
          }),
        ),
        remoteChannelProvider.overrideWithValue((userId) {
          channelUsers.add(userId);
          return hub.channelFor(me());
        }),
        remoteDeviceNameProvider.overrideWith((ref) async => 'This PC'),
      ];
      container = ProviderContainer(overrides: overrides);
      container.listen(remoteHostFollowerProvider, (_, _) {});
      container.listen(remoteDevicesProvider, (_, _) {});
      container.listen(remoteLinkProvider, (_, _) {});
      container.listen(playerViewProvider, (_, _) {});
      await hub.channelFor('o').join(presenceOf('o'));
      await pumpEventQueue();
    });

    tearDown(() async {
      container.dispose();
      await player.dispose();
      await accountChanges.close();
      await cloud.dispose();
      await db.close();
    });

    test('signed out joins nothing and lists no devices', () async {
      expect(channelUsers, isEmpty);
      expect(container.read(remoteControllerProvider), isNull);
      expect(seenByOther(), ['o']);
      expect(container.read(remoteDevicesProvider).value, isEmpty);
      expect(container.read(remoteLinkProvider).value, isNull);
      expect(container.read(playerViewProvider).isRemote, isFalse);
    });

    test('signing in joins with this device\'s presence', () async {
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      expect(channelUsers, ['u1']);
      expect(container.read(remoteControllerProvider), isNotNull);
      final mine = hub
          .channelFor('o')
          .present
          .singleWhere((p) => p.deviceId == me());
      expect(mine.name, 'This PC');
      expect(mine.platform, Platform.operatingSystem);
      expect(mine.appVersion, appVersion);
      expect(mine.playing, isFalse);
    });

    test('remoteDevicesProvider excludes this device', () async {
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      final devices = container.read(remoteDevicesProvider).value!;
      expect([for (final d in devices) d.deviceId], ['o']);
    });

    test(
      'playerViewProvider switches to remote on select and back on deselect',
      () async {
        setAccount(signedIn('u1'));
        await pumpEventQueue();
        final local = container.read(playerViewProvider);
        expect(local.isRemote, isFalse);

        final o = container.read(remoteDevicesProvider).value!.single;
        await selectRemote(player, controller(), o);
        await pumpEventQueue();
        expect(container.read(remoteLinkProvider).value?.device.deviceId, 'o');
        expect(container.read(playerViewProvider).isRemote, isTrue);

        controller().deselect();
        await pumpEventQueue();
        expect(container.read(remoteLinkProvider).value, isNull);
        expect(container.read(playerViewProvider).isRemote, isFalse);
      },
    );

    test('playerViewStateProvider follows the view', () async {
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      final values = <PlayerState>[];
      container.listen(playerViewStateProvider, (_, next) {
        if (next.hasValue) values.add(next.requireValue);
      });
      player.setShuffle(true);
      await pumpEventQueue();
      expect(values.last.shuffle, isTrue);

      final o = container.read(remoteDevicesProvider).value!.single;
      await selectRemote(player, controller(), o);
      await pumpEventQueue();
      // The remote view starts empty, not with the local shuffle.
      expect(values.last.shuffle, isFalse);
      expect(values.last.queue, isEmpty);
    });

    test('selecting a remote pauses local playback', () async {
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      await player.playQueue([track('a')]);
      expect(player.state.playing, isTrue);

      final o = container.read(remoteDevicesProvider).value!.single;
      await selectRemote(player, controller(), o);
      await pumpEventQueue();
      expect(player.state.playing, isFalse);
      expect(controller().link?.device.deviceId, 'o');
    });

    test('local playback starting ends the remote view', () async {
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      final ended = <(RemotePresence, RemoteEndReason)>[];
      container.read(remoteEndedProvider).listen(ended.add);
      final o = container.read(remoteDevicesProvider).value!.single;
      await selectRemote(player, controller(), o);
      await pumpEventQueue();
      expect(container.read(playerViewProvider).isRemote, isTrue);

      // E.g. a search result tapped while viewing the remote (P3).
      await player.playQueue([track('a')]);
      await pumpEventQueue();
      expect(controller().link, isNull);
      expect(container.read(playerViewProvider).isRemote, isFalse);
      expect(player.state.playing, isTrue);
      expect(ended, hasLength(1));
      expect(ended.single.$1.deviceId, 'o');
      expect(ended.single.$2, RemoteEndReason.deselected);
    });

    test('signing out leaves and returns to This device', () async {
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      final o = container.read(remoteDevicesProvider).value!.single;
      await selectRemote(player, controller(), o);
      await pumpEventQueue();
      expect(seenByOther(), containsAll(['o', me()]));

      setAccount(const SignedOut());
      await pumpEventQueue();
      expect(seenByOther(), ['o']);
      expect(container.read(remoteControllerProvider), isNull);
      expect(container.read(remoteLinkProvider).value, isNull);
      expect(container.read(remoteDevicesProvider).value, isEmpty);
      expect(container.read(playerViewProvider).isRemote, isFalse);
    });

    test(
      'with only the follower listened to, the host follows the account',
      () async {
        // As in main(): only the follower is listened to.
        final alone = ProviderContainer(overrides: overrides);
        addTearDown(alone.dispose);
        container.dispose();
        container = ProviderContainer(overrides: overrides);
        alone.listen(remoteHostFollowerProvider, (_, _) {});
        await pumpEventQueue();

        setAccount(signedIn('u1'));
        await pumpEventQueue();
        expect(seenByOther(), containsAll(['o', me()]));
        setAccount(const SignedOut());
        await pumpEventQueue();
        expect(seenByOther(), ['o']);
      },
    );

    test('switching accounts joins the new account\'s channel', () async {
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      final first = controller();
      setAccount(signedIn('u2'));
      await pumpEventQueue();
      expect(channelUsers, ['u1', 'u2']);
      expect(controller(), isNot(same(first)));
      expect(seenByOther(), containsAll(['o', me()]));
    });

    test('the same account signing in again keeps its session', () async {
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      setAccount(signedIn('u1'));
      await pumpEventQueue();
      expect(channelUsers, ['u1']);
    });
  });
}
