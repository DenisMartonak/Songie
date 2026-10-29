import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/connectivity.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/lyrics/file_lyrics.dart';
import 'package:songies/lyrics/lrclib.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_service.dart';
import 'package:songies/lyrics/lyrics_sources.dart';
import 'package:songies/lyrics/lyrics_store.dart';
import 'package:songies/lyrics/ytm_lyrics.dart';
import 'package:songies/player/player_service.dart';
import 'package:songies/player/track_resolver.dart';
import 'package:songies/providers.dart';

import '../helpers/fake_audio_backend.dart';
import '../helpers/fake_network_status.dart';
import '../helpers/test_db.dart';

class FakeFile implements FileLyricsSource {
  SourceAnswer answer = const Nothing();
  final paths = <String?>[];

  @override
  Future<SourceAnswer> read(String? audioPath) async {
    paths.add(audioPath);
    return answer;
  }
}

class FakeLrclib implements LrclibSource {
  SourceAnswer exactAnswer = const Nothing();
  SourceAnswer searchAnswer = const Nothing();
  final exactQueries = <LyricsQuery>[];
  final searchQueries = <LyricsQuery>[];
  Completer<void>? gate;

  @override
  Future<SourceAnswer> exact(LyricsQuery q) async {
    exactQueries.add(q);
    final g = gate;
    if (g != null) await g.future;
    return exactAnswer;
  }

  @override
  Future<SourceAnswer> search(LyricsQuery q) async {
    searchQueries.add(q);
    return searchAnswer;
  }
}

class FakeYtm implements YtmLyricsSource {
  SourceAnswer answer = const Nothing();
  final videoIds = <String?>[];
  void Function()? onFetch;

  @override
  Future<SourceAnswer> fetch(String? videoId) async {
    videoIds.add(videoId);
    onFetch?.call();
    return answer;
  }
}

class ThrowingFile implements FileLyricsSource {
  @override
  Future<SourceAnswer> read(String? audioPath) async => throw StateError('x');
}

Track track(
  String id, {
  String source = 'local',
  String title = 'Invented Song',
  String artist = 'Invented Artist',
  String? album = 'Invented Album',
  int durationMs = 213400,
  String? ytVideoId,
}) => Track(
  id: id,
  clock: '0000000000001-00000-dev',
  originDevice: 'dev',
  deleted: false,
  localSeq: 1,
  source: source,
  ytVideoId: ytVideoId,
  title: title,
  artist: artist,
  album: album,
  durationMs: durationMs,
  unavailable: false,
  searchText: '',
);

TrackLyrics synced(LyricsSource s, [String text = 'la']) => TrackLyrics(
  kind: LyricsKind.synced,
  source: s,
  lines: [LyricLine(const Duration(seconds: 1), text)],
);

TrackLyrics plain(LyricsSource s, [String text = 'la la']) =>
    TrackLyrics(kind: LyricsKind.plain, source: s, text: text);

const none = TrackLyrics(kind: LyricsKind.none, source: null);

TrackLyrics? shown(LyricsState s) => s is LyricsShown ? s.lyrics : null;

void main() {
  late AppDatabase db;
  late LyricsStore store;
  late FakeFile file;
  late FakeLrclib lrclib;
  late FakeYtm ytm;
  late FakeNetworkStatus network;
  late DateTime clock;
  late LyricsService service;

  LyricsService build({FileLyricsSource? fileSource}) => LyricsService(
    db: db,
    store: store,
    file: fileSource ?? file,
    lrclib: lrclib,
    ytm: ytm,
    network: network,
    now: () => clock,
  );

  setUp(() async {
    db = testDb();
    store = LyricsStore(db, await SyncStamp.load(db));
    file = FakeFile();
    lrclib = FakeLrclib();
    ytm = FakeYtm();
    network = FakeNetworkStatus();
    clock = DateTime.utc(2026, 10, 29, 12);
    service = build();
  });
  tearDown(() => db.close());

  int onlineCalls() =>
      lrclib.exactQueries.length +
      lrclib.searchQueries.length +
      ytm.videoIds.length;

  group('query and audio path', () {
    test('builds the query from the track', () async {
      await service.lookup(
        track(
          't',
          title: 'Invented Song (Official Video)',
          artist: 'Invented Artist - Topic',
          album: '',
          durationMs: 213600,
        ),
      );
      final q = lrclib.exactQueries.single;
      expect(q.title, 'Invented Song');
      expect(q.artist, 'Invented Artist');
      expect(q.album, isNull);
      expect(q.durationSec, 214);
    });

    test('a zero duration gives a null duration', () async {
      await service.lookup(track('t', durationMs: 0));
      expect(lrclib.searchQueries.single.durationSec, isNull);
    });

    test('the file source gets the done local file path', () async {
      await db
          .into(db.localFiles)
          .insert(
            LocalFilesCompanion.insert(
              trackId: 't',
              path: '/music/t.mp3',
              state: 'done',
              bytes: 1,
              mtimeMs: 1,
            ),
          );
      await db
          .into(db.localFiles)
          .insert(
            LocalFilesCompanion.insert(
              trackId: 'u',
              path: '/music/u.mp3',
              state: 'missing',
              bytes: 1,
              mtimeMs: 1,
            ),
          );
      await service.lookup(track('t'));
      await service.lookup(track('u'));
      await service.lookup(track('v'));
      expect(file.paths, ['/music/t.mp3', null, null]);
    });
  });

  group('rule 1: the file runs first', () {
    test('a synced file answer is shown at once and not stored', () async {
      file.answer = Found(synced(LyricsSource.file));
      final s = await service.lookup(track('t'));
      expect(shown(s), synced(LyricsSource.file));
      expect(onlineCalls(), 0);
      expect(await store.read('t'), isNull);
    });

    test('a synced file answer beats a stored synced one', () async {
      await store.write('t', synced(LyricsSource.lrclib, 'old'), clock);
      file.answer = Found(synced(LyricsSource.file));
      expect(
        shown(await service.lookup(track('t'))),
        synced(LyricsSource.file),
      );
    });

    test('the file is read again on every lookup', () async {
      await service.lookup(track('t'));
      await service.lookup(track('t'));
      expect(file.paths, hasLength(2));
    });
  });

  group('rule 2: stored results', () {
    test('a stored synced result is used without asking online', () async {
      await store.write('t', synced(LyricsSource.lrclib), clock);
      expect(
        shown(await service.lookup(track('t'))),
        synced(LyricsSource.lrclib),
      );
      expect(onlineCalls(), 0);
    });

    test('a stored plain result is used', () async {
      await store.write('t', plain(LyricsSource.youtube), clock);
      expect(
        shown(await service.lookup(track('t'))),
        plain(LyricsSource.youtube),
      );
      expect(onlineCalls(), 0);
    });

    test('a stored synced result beats a plain file answer', () async {
      await store.write('t', synced(LyricsSource.lrclib), clock);
      file.answer = Found(plain(LyricsSource.file));
      expect(
        shown(await service.lookup(track('t'))),
        synced(LyricsSource.lrclib),
      );
    });

    test('a plain file answer beats a stored plain one', () async {
      await store.write('t', plain(LyricsSource.lrclib), clock);
      file.answer = Found(plain(LyricsSource.file));
      expect(shown(await service.lookup(track('t'))), plain(LyricsSource.file));
      expect(onlineCalls(), 0);
    });

    test('a stored none from 29 days ago is not looked up again', () async {
      await store.write('t', none, clock.subtract(const Duration(days: 29)));
      expect(await service.lookup(track('t')), isA<LyricsNone>());
      expect(onlineCalls(), 0);
    });

    test(
      'a fresh stored none with a plain file answer shows the file',
      () async {
        await store.write('t', none, clock);
        file.answer = Found(plain(LyricsSource.file));
        expect(
          shown(await service.lookup(track('t'))),
          plain(LyricsSource.file),
        );
        expect(onlineCalls(), 0);
      },
    );

    test('a stored none from 31 days ago is looked up again', () async {
      await store.write('t', none, clock.subtract(const Duration(days: 31)));
      lrclib.exactAnswer = Found(synced(LyricsSource.lrclib));
      expect(
        shown(await service.lookup(track('t'))),
        synced(LyricsSource.lrclib),
      );
      expect(lrclib.exactQueries, hasLength(1));
    });

    test('force ignores a stored synced result', () async {
      await store.write('t', synced(LyricsSource.lrclib, 'old'), clock);
      lrclib.exactAnswer = Found(synced(LyricsSource.lrclib, 'new'));
      final s = await service.lookup(track('t'), force: true);
      expect(shown(s), synced(LyricsSource.lrclib, 'new'));
      expect(
        (await store.read('t'))!.lyrics,
        synced(LyricsSource.lrclib, 'new'),
      );
    });
  });

  group('rule 3: empty artist', () {
    test('skips online sources and stores nothing', () async {
      final s = await service.lookup(track('t', artist: '  '));
      expect(s, isA<LyricsNone>());
      expect(onlineCalls(), 0);
      expect(await store.read('t'), isNull);
    });

    test('shows a plain file answer', () async {
      file.answer = Found(plain(LyricsSource.file));
      final s = await service.lookup(track('t', artist: ''));
      expect(shown(s), plain(LyricsSource.file));
    });
  });

  group('rule 4: offline', () {
    setUp(() => network.kind = NetworkKind.offline);

    test(
      'with nothing stored gives LyricsOffline, only the file asked',
      () async {
        final s = await service.lookup(track('t'));
        expect(s, isA<LyricsOffline>());
        expect(file.paths, hasLength(1));
        expect(onlineCalls(), 0);
        expect(await store.read('t'), isNull);
      },
    );

    test('with a stored result shows it', () async {
      await store.write('t', plain(LyricsSource.lrclib), clock);
      expect(
        shown(await service.lookup(track('t'))),
        plain(LyricsSource.lrclib),
      );
    });

    test('shows a plain file answer', () async {
      file.answer = Found(plain(LyricsSource.file));
      expect(shown(await service.lookup(track('t'))), plain(LyricsSource.file));
    });
  });

  group('rule 5: source order', () {
    test('a synced exact answer stops the run', () async {
      lrclib.exactAnswer = Found(synced(LyricsSource.lrclib));
      await service.lookup(track('t', source: 'yt', ytVideoId: 'v'));
      expect(lrclib.searchQueries, isEmpty);
      expect(ytm.videoIds, isEmpty);
    });

    test('YouTube Music is asked for YouTube songs only', () async {
      await service.lookup(track('t'));
      expect(ytm.videoIds, isEmpty);
      await service.lookup(track('y', source: 'yt', ytVideoId: 'vid'));
      expect(ytm.videoIds, ['vid']);
    });

    test(
      'LRCLIB plain plus YouTube Music synced gives YouTube synced',
      () async {
        lrclib.exactAnswer = Found(plain(LyricsSource.lrclib));
        ytm.answer = Found(synced(LyricsSource.youtube));
        final s = await service.lookup(
          track('t', source: 'yt', ytVideoId: 'v'),
        );
        expect(shown(s), synced(LyricsSource.youtube));
        expect(lrclib.searchQueries, hasLength(1));
      },
    );
  });

  group('rule 6: the best answer', () {
    test('a plain file answer plus LRCLIB synced gives LRCLIB', () async {
      file.answer = Found(plain(LyricsSource.file));
      lrclib.searchAnswer = Found(synced(LyricsSource.lrclib));
      final s = await service.lookup(track('t'));
      expect(shown(s), synced(LyricsSource.lrclib));
      expect((await store.read('t'))!.lyrics, synced(LyricsSource.lrclib));
    });

    test('the earliest plain online answer wins', () async {
      lrclib.searchAnswer = Found(plain(LyricsSource.lrclib, 'first'));
      ytm.answer = Found(plain(LyricsSource.youtube, 'second'));
      final s = await service.lookup(track('t', source: 'yt', ytVideoId: 'v'));
      expect(shown(s), plain(LyricsSource.lrclib, 'first'));
    });

    test(
      'a plain file answer beats a plain online one, which is stored',
      () async {
        file.answer = Found(plain(LyricsSource.file));
        lrclib.exactAnswer = Found(plain(LyricsSource.lrclib));
        final s = await service.lookup(track('t'));
        expect(shown(s), plain(LyricsSource.file));
        expect(lrclib.searchQueries, hasLength(1));
        expect((await store.read('t'))!.lyrics, plain(LyricsSource.lrclib));
      },
    );
  });

  group('rule 7: storing', () {
    test('an online result is stored with now', () async {
      lrclib.exactAnswer = Found(plain(LyricsSource.lrclib));
      await service.lookup(track('t'));
      final got = (await store.read('t'))!;
      expect(got.lyrics, plain(LyricsSource.lrclib));
      expect(got.fetchedAt.toUtc(), clock);
    });

    test('none is stored when every source answered cleanly', () async {
      final s = await service.lookup(track('t'));
      expect(s, isA<LyricsNone>());
      expect((await store.read('t'))!.lyrics.kind, LyricsKind.none);
    });

    test('none with a plain file answer still stores none', () async {
      file.answer = Found(plain(LyricsSource.file));
      final s = await service.lookup(track('t'));
      expect(shown(s), plain(LyricsSource.file));
      expect((await store.read('t'))!.lyrics.kind, LyricsKind.none);
    });

    test('every source failing while online gives LyricsNone, nothing '
        'stored', () async {
      lrclib.exactAnswer = const Failed('x');
      lrclib.searchAnswer = const Failed('x');
      ytm.answer = const Failed('x');
      final s = await service.lookup(track('t', source: 'yt', ytVideoId: 'v'));
      expect(s, isA<LyricsNone>());
      expect(await store.read('t'), isNull);
    });

    test('every source failing after the connection dropped gives '
        'LyricsOffline, nothing stored', () async {
      lrclib.exactAnswer = const Failed('x');
      lrclib.searchAnswer = const Failed('x');
      ytm.answer = const Failed('x');
      ytm.onFetch = () => network.kind = NetworkKind.offline;
      final s = await service.lookup(track('t', source: 'yt', ytVideoId: 'v'));
      expect(s, isA<LyricsOffline>());
      expect(await store.read('t'), isNull);
    });

    test('every source failing while online, with a plain file, shows the '
        'file', () async {
      file.answer = Found(plain(LyricsSource.file));
      lrclib.exactAnswer = const Failed('x');
      lrclib.searchAnswer = const Failed('x');
      final s = await service.lookup(track('t'));
      expect(shown(s), plain(LyricsSource.file));
      expect(await store.read('t'), isNull);
    });

    test(
      'some failing and the rest nothing gives LyricsNone, nothing stored',
      () async {
        lrclib.searchAnswer = const Failed('x');
        final s = await service.lookup(track('t'));
        expect(s, isA<LyricsNone>());
        expect(await store.read('t'), isNull);
      },
    );

    test('a failure after a plain answer still stores the plain', () async {
      lrclib.exactAnswer = Found(plain(LyricsSource.lrclib));
      lrclib.searchAnswer = const Failed('x');
      await service.lookup(track('t'));
      expect((await store.read('t'))!.lyrics, plain(LyricsSource.lrclib));
    });
  });

  group('rule 8: in-flight de-duplication', () {
    test('two concurrent lookups make one call to each source', () async {
      lrclib.gate = Completer<void>();
      final t = track('t', source: 'yt', ytVideoId: 'v');
      final first = service.lookup(t);
      final second = service.lookup(t);
      await pumpEventQueue();
      lrclib.gate!.complete();
      final results = await Future.wait([first, second]);
      expect(results[0], same(results[1]));
      expect(file.paths, hasLength(1));
      expect(lrclib.exactQueries, hasLength(1));
      expect(lrclib.searchQueries, hasLength(1));
      expect(ytm.videoIds, hasLength(1));
    });

    test('prefetch then lookup makes one call', () async {
      lrclib.gate = Completer<void>();
      final t = track('t');
      service.prefetch(t);
      final s = service.lookup(t);
      await pumpEventQueue();
      lrclib.gate!.complete();
      await s;
      expect(file.paths, hasLength(1));
      expect(lrclib.exactQueries, hasLength(1));
    });

    test('prefetch of null does nothing', () async {
      service.prefetch(null);
      await pumpEventQueue();
      expect(file.paths, isEmpty);
    });

    test('force while one is running joins it', () async {
      lrclib.gate = Completer<void>();
      final t = track('t');
      final first = service.lookup(t);
      final forced = service.lookup(t, force: true);
      await pumpEventQueue();
      lrclib.gate!.complete();
      await Future.wait([first, forced]);
      expect(lrclib.exactQueries, hasLength(1));
    });

    test('a finished lookup is not joined', () async {
      await service.lookup(track('t'), force: true);
      await service.lookup(track('t'), force: true);
      expect(lrclib.exactQueries, hasLength(2));
    });
  });

  group('rule 9: never throws', () {
    test('an unexpected error gives LyricsNone, nothing stored', () async {
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = original);
      service = build(fileSource: ThrowingFile());
      final s = await service.lookup(track('t'));
      expect(s, isA<LyricsNone>());
      expect(await store.read('t'), isNull);
    });
  });

  group('providers', () {
    late PlayerService player;
    late ProviderContainer container;

    setUp(() async {
      final stamp = await SyncStamp.load(db);
      player = PlayerService(FakeAudioBackend(), LocalTrackResolver(db));
      container = ProviderContainer(
        overrides: [
          lyricsServiceProvider.overrideWithValue(service),
          playerServiceProvider.overrideWithValue(player),
          libraryRepositoryProvider.overrideWithValue(
            LibraryRepository(db, stamp),
          ),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      await player.dispose();
    });

    Future<LyricsState> read(String id) async {
      final sub = container.listen(lyricsProvider(id), (_, _) {});
      addTearDown(sub.close);
      return container.read(lyricsProvider(id).future);
    }

    test('looks up a track from the library', () async {
      await db.into(db.tracks).insert(trackRow(id: 'lib', title: 'From Db'));
      lrclib.searchAnswer = Found(plain(LyricsSource.lrclib));
      expect(shown(await read('lib')), plain(LyricsSource.lrclib));
      expect(lrclib.searchQueries.single.title, 'From Db');
    });

    test('an unknown track gives LyricsNone', () async {
      expect(await read('nope'), isA<LyricsNone>());
    });

    test('Search again forces a lookup past the stored result', () async {
      await db.into(db.tracks).insert(trackRow(id: 'lib'));
      await store.write('lib', synced(LyricsSource.lrclib, 'old'), clock);
      expect(shown(await read('lib')), synced(LyricsSource.lrclib, 'old'));
      expect(onlineCalls(), 0);

      lrclib.searchAnswer = Found(synced(LyricsSource.lrclib, 'new'));
      container.read(lyricsRetryProvider('lib').notifier).searchAgain();
      expect(shown(await read('lib')), synced(LyricsSource.lrclib, 'new'));
      expect(lrclib.searchQueries, hasLength(1));
    });
  });
}
