import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/core/paths.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/downloads/download_repository.dart';
import 'package:songies/library/art_cache.dart';
import 'package:songies/library/file_hasher.dart';
import 'package:songies/library/library_repository.dart';
import 'package:songies/library/library_scanner.dart';
import 'package:songies/library/tag_reader.dart';
import 'package:songies/sync/file_transfer.dart';
import 'package:songies/sync/merger.dart';
import 'package:songies/sync/peer_repository.dart';
import 'package:songies/sync/sync_auth.dart';
import 'package:songies/sync/sync_client.dart';
import 'package:songies/sync/sync_progress.dart';
import 'package:songies/sync/sync_responder.dart';
import 'package:songies/sync/sync_runner.dart';
import 'package:songies/sync/sync_server.dart';
import 'package:songies/theme/font_service.dart';

import '../helpers/sync_devices.dart';
import '../helpers/sync_fixtures.dart';
import '../helpers/test_db.dart';

class _NoTags implements TagReader {
  @override
  Future<TrackTags> read(File f) async => const TrackTags();
}

/// Timers the responder starts, fired by hand.
class _Timers {
  final made = <_FakeTimer>[];

  Timer create(Duration d, void Function() callback) {
    final t = _FakeTimer(callback);
    made.add(t);
    return t;
  }

  void fire() {
    for (final t in made.where((t) => t.isActive).toList()) {
      t.fire();
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

/// One simulated device with its files: database, app data, scanner, fonts,
/// file transfer, server, responder and runner.
class _Dev {
  _Dev._(this.name, this.dir, this.db, this.stamp);

  final String name;
  final Directory dir;
  final AppDatabase db;
  final SyncStamp stamp;
  late final PeerRepository peers = PeerRepository(db);
  late final AppPaths paths = AppPaths.at(Directory(p.join(dir.path, 'data')));
  late final String fingerprint;
  late final LibraryScanner scanner;
  late final FontService fonts;
  late final FileTransfer files;
  late final SyncServer server;
  late final SyncResponder responder;
  late final SyncRunner runner;
  late final int port;

  /// Font families handed to the engine, in order.
  final registered = <String>[];
  final timers = _Timers();

  /// Makes the scanner fail to read files (so an import fails).
  bool failHash = false;
  final states = <ResponderState>[];

  String get id => stamp.deviceId;

  static Future<_Dev> create(Directory root, String name) async {
    final db = testDb();
    final d = _Dev._(
      name,
      Directory(p.join(root.path, name)),
      db,
      await SyncStamp.load(db),
    );
    await d.paths.ensureCreated();
    final identity = await testIdentity(root, '$name-id');
    d.fingerprint = identity.fingerprint;
    d.scanner = LibraryScanner(
      db,
      d.stamp,
      _NoTags(),
      ArtCache(d.paths.art),
      LibraryRepository(db, d.stamp),
      hasher: (f) => d.failHash
          ? throw FileSystemException('cannot read', f.path)
          : sha256File(f),
    );
    d.fonts = FontService(
      db,
      d.stamp,
      d.paths.fonts,
      register: (family, _) async => d.registered.add(family),
    );
    d.files = FileTransfer(
      db: db,
      paths: d.paths,
      scanner: d.scanner,
      fonts: d.fonts,
    );
    d.runner = SyncRunner(
      db: db,
      stamp: d.stamp,
      peers: d.peers,
      myDeviceId: d.id,
      downloads: DownloadRepository(db),
      files: (c, cancel) => d.files.exchange(c, cancel: cancel),
    );
    d.responder = SyncResponder(
      db: db,
      stamp: d.stamp,
      peers: d.peers,
      myDeviceId: d.id,
      myName: () => name,
      downloads: DownloadRepository(db),
      files: d.files,
      runningLocally: () => d.runner.running,
      timer: d.timers.create,
    );
    d.responder.state.listen(d.states.add);
    d.server = SyncServer(identity, RequestVerifier(d.peers));
    d.responder.register(d.server);
    d.port = await serveLoopback(d.server);
    return d;
  }

  /// A runner that copies no files.
  SyncRunner rowsOnly() => SyncRunner(
    db: db,
    stamp: stamp,
    peers: peers,
    myDeviceId: id,
    downloads: DownloadRepository(db),
  );

  Future<void> dispose() async {
    await server.stop();
    await db.close();
  }

  /// Writes [bytes] as `music/<file>` and imports it; returns the track id.
  Future<String> mp3(String file, List<int> bytes) async {
    final f = File(p.join(dir.path, 'music', file));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return (await scanner.importFile(f.path) as Ok<String>).value;
  }

  Future<LocalFile?> localFile(String trackId) => (db.select(
    db.localFiles,
  )..where((f) => f.trackId.equals(trackId))).getSingleOrNull();

  /// Every file under [d] whose name ends in `.part`.
  List<String> parts(Directory d) => [
    for (final e in d.listSync(recursive: true))
      if (e.path.endsWith('.part')) p.basename(e.path),
  ];
}

Future<void> _pair(_Dev a, _Dev b) async {
  final rnd = Random.secure();
  final key = base64.encode([for (var i = 0; i < 32; i++) rnd.nextInt(256)]);
  PeerRow row(_Dev other) => PeerRow(
    deviceId: other.id,
    name: other.name,
    certFingerprint: other.fingerprint,
    pairKey: key,
    lastSentSeq: 0,
    lastReceivedSeq: 0,
  );
  await a.peers.save(row(b));
  await b.peers.save(row(a));
}

Future<Map<String, Resolution>?> _noClashes(List<PlaylistClash> c) async {
  fail('unexpected clash');
}

Future<List<SyncProgress>> _sync(_Dev a, _Dev b, {SyncRunner? runner}) async =>
    (runner ?? a.runner)
        .run(
          (await a.peers.byId(b.id))!,
          host: '127.0.0.1',
          port: b.port,
          choose: _noClashes,
        )
        .toList();

SyncSummary _done(List<SyncProgress> events) {
  final last = events.last;
  if (last is! SyncDone) fail('sync did not finish: $last');
  return last.summary;
}

final _rnd = Random(7);

Uint8List _bytes(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) _rnd.nextInt(256)]);

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  final root = setUpSyncDevices('songies_file_transfer');
  late _Dev a;
  late _Dev b;
  var n = 0;

  setUp(() async {
    n++;
    a = await _Dev.create(root(), 'A$n');
    b = await _Dev.create(root(), 'B$n');
    await _pair(a, b);
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('needs lists missing audio, fonts and art', () async {
    final h = [
      for (var i = 0; i < 8; i++) _hash([i]),
    ];
    final art = [
      for (var i = 10; i < 14; i++) '${_hash([i])}.jpg',
    ];

    Future<void> track({
      String? hash,
      String source = 'local',
      bool deleted = false,
      String? artwork,
      String? localState,
    }) async {
      final st = await a.stamp.next();
      await a.db
          .into(a.db.tracks)
          .insert(
            trackRow(
              id: st.id,
              fileHash: hash,
              source: source,
              clock: st.clock,
              originDevice: st.originDevice,
              localSeq: st.localSeq,
            ).copyWith(artworkRef: Value(artwork), deleted: Value(deleted)),
          );
      if (localState != null) {
        await a.db
            .into(a.db.localFiles)
            .insert(
              LocalFilesCompanion.insert(
                trackId: st.id,
                path: '/music/${st.id}.mp3',
                state: localState,
                bytes: 1,
                mtimeMs: 0,
              ),
            );
      }
    }

    Future<void> font(String hash, {bool deleted = false}) async {
      final st = await a.stamp.next();
      await a.db
          .into(a.db.fonts)
          .insert(
            FontsCompanion.insert(
              id: st.id,
              clock: st.clock,
              originDevice: st.originDevice,
              localSeq: st.localSeq,
              family: 'F $hash',
              fileHash: hash,
              ext: 'ttf',
              deleted: Value(deleted),
            ),
          );
    }

    await track(hash: h[0]); // no file on this device
    await track(hash: h[1], localState: 'done');
    await track(hash: h[2], localState: 'missing'); // its file is gone
    await track(hash: h[3], deleted: true);
    await track(source: 'yt', artwork: art[0]);
    await track(hash: h[4], localState: 'done', artwork: 'yt2-${art[1]}');
    await track(artwork: 'https://example.com/cover.jpg');
    await track(artwork: art[2]);
    File(p.join(a.paths.art.path, art[2])).writeAsBytesSync([1]);
    final st = await a.stamp.next();
    await a.db
        .into(a.db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: st.id,
            clock: st.clock,
            originDevice: st.originDevice,
            localSeq: st.localSeq,
            name: 'P',
            source: 'local',
            coverRef: Value(art[3]),
          ),
        );
    await font(h[5]);
    await font(h[6]);
    File(p.join(a.paths.fonts.path, '${h[6]}.ttf')).writeAsBytesSync([1]);
    await font(h[7], deleted: true);
    // A copy cut off after 10 bytes.
    File(p.join(a.paths.libraryLocal.path, '${h[0]}.mp3.part'))
        .writeAsBytesSync(List.filled(10, 0));

    final needs = await a.files.needs();

    expect(
      {for (final r in needs) '${r.kind.name} ${r.name} ${r.ext} ${r.have}'},
      {
        'audio ${h[0]} null 10',
        'audio ${h[2]} null 0',
        'font ${h[5]} ttf 0',
        'art ${art[0]} null 0',
        'art yt2-${art[1]} null 0',
        'art ${art[3]} null 0',
      },
    );
    expect(needs, hasLength(6));
  });

  test('copies an MP3 and attaches it to the synced track', () async {
    final song = _bytes(200000);
    final theirs = await b.mp3('song.mp3', song);
    final cover = '${_hash([42])}.jpg';
    final coverBytes = _bytes(3000);
    File(p.join(b.paths.art.path, cover)).writeAsBytesSync(coverBytes);
    final st = await b.stamp.next();
    await b.db
        .into(b.db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: st.id,
            clock: st.clock,
            originDevice: st.originDevice,
            localSeq: st.localSeq,
            name: 'Covered',
            source: 'local',
            coverRef: Value(cover),
          ),
        );
    final other = _bytes(5000);
    final mine = await a.mp3('mine.mp3', other);
    final bDone = b.responder.state.firstWhere((s) => s is ResponderDone);

    final events = await _sync(a, b);

    // Copied either way, the same on both devices.
    expect(_done(events).filesCopied, 3);
    expect(((await bDone) as ResponderDone).summary.filesCopied, 3);

    final onA = (await a.localFile(theirs))!;
    expect(onA.state, 'done');
    expect(onA.path, p.join(a.paths.libraryLocal.path, '${_hash(song)}.mp3'));
    expect(File(onA.path).readAsBytesSync(), song);
    final onB = (await b.localFile(mine))!;
    expect(onB.state, 'done');
    expect(onB.path, p.join(b.paths.libraryLocal.path, '${_hash(other)}.mp3'));
    expect(File(onB.path).readAsBytesSync(), other);
    expect(File(p.join(a.paths.art.path, cover)).readAsBytesSync(), coverBytes);

    expect(await a.files.needs(), isEmpty);
    expect(await b.files.needs(), isEmpty);
    expect(a.parts(a.paths.root), isEmpty);
    expect(b.parts(b.paths.root), isEmpty);
    expect(await snapshot(a.db), await snapshot(b.db));

    final copying = [
      for (final e in events)
        if (e is SyncStep && e.stage == SyncStage.files) e,
    ];
    expect(copying.last.done, 3);
    expect(copying.last.total, 3);
    final receiving = b.states.whereType<Receiving>().where(
      (r) => r.stage == SyncStage.files,
    );
    expect(receiving.last.done, 3);
    expect(receiving.last.total, 3);
    expect(b.states.last, isA<ResponderDone>());
    expect(b.responder.inSession, isFalse);
  });

  test('resumes from a partial file', () async {
    final song = _bytes(300000);
    final id = await b.mp3('song.mp3', song);
    final hash = _hash(song);
    _done(await _sync(a, b, runner: a.rowsOnly()));
    expect(await a.localFile(id), isNull);

    // The copy was cut after 100000 bytes: receive keeps the part.
    final cut = await a.files.receive(
      FileRef(FileKind.audio, hash, ext: 'mp3'),
      Stream.value(song.sublist(0, 100000)),
      total: song.length,
    );
    expect(cut, isFalse);
    final part = File(p.join(a.paths.libraryLocal.path, '$hash.mp3.part'));
    expect(part.lengthSync(), 100000);
    expect((await a.files.needs()).single.have, 100000);

    final ranges = <String?>[];
    b.server.route('GET', '/files/', (req, peer) async {
      ranges.add(req.headers.value(HttpHeaders.rangeHeader));
      await b.files.serve(req);
    });

    expect(_done(await _sync(a, b)).filesCopied, 1);

    expect(ranges, ['bytes=100000-']);
    expect(part.existsSync(), isFalse);
    expect(File((await a.localFile(id))!.path).readAsBytesSync(), song);
  });

  test('hash mismatch retries once then skips', () async {
    final song = _bytes(5000);
    final id = await b.mp3('song.mp3', song);
    // The file changed on B after it was scanned: its bytes no longer match
    // the track's hash.
    File(p.join(b.dir.path, 'music', 'song.mp3'))
        .writeAsBytesSync(_bytes(5000));
    var gets = 0;
    b.server.route('GET', '/files/', (req, peer) async {
      gets++;
      await b.files.serve(req);
    });

    final events = await _sync(a, b);

    expect(_done(events).filesCopied, 0);
    expect(gets, 2);
    expect(await a.localFile(id), isNull);
    expect(a.parts(a.paths.root), isEmpty);
    expect(
      File(p.join(a.paths.libraryLocal.path, '${_hash(song)}.mp3'))
          .existsSync(),
      isFalse,
    );
    expect((await a.files.needs()).single.name, _hash(song));
  });

  test('missing source is skipped and the song still syncs', () async {
    // Gone before the sync: B does not offer it.
    final gone = await b.mp3('gone.mp3', _bytes(4000));
    File(p.join(b.dir.path, 'music', 'gone.mp3')).deleteSync();
    // Offered, then gone when asked for: a 404.
    final vanished = await b.mp3('vanished.mp3', _bytes(4000));
    var gets = 0;
    b.server.route('GET', '/files/', (req, peer) async {
      gets++;
      await sendJson(req, {'error': 'not_found'}, status: HttpStatus.notFound);
    });

    final events = await _sync(a, b);

    expect(_done(events).filesCopied, 0);
    expect(gets, 1);
    expect(await snapshot(a.db), await snapshot(b.db));
    final tracks = await (a.db.select(
      a.db.tracks,
    )..where((t) => t.deleted.equals(false))).get();
    expect(tracks.map((t) => t.id), containsAll([gone, vanished]));
    expect(await a.localFile(gone), isNull);
    expect(await a.localFile(vanished), isNull);
    expect(await a.files.needs(), hasLength(2));
  });

  test('received font is registered', () async {
    final tmp = Directory(p.join(root().path, 'fixtures$n'))..createSync();
    final fancy = File('assets/fonts/Inter-Regular.ttf')
        .copySync(p.join(tmp.path, 'Fancy Sans-Regular.ttf'));
    final mono = File('assets/fonts/JetBrainsMono-Regular.ttf')
        .copySync(p.join(tmp.path, 'Mono Thing.ttf'));
    expect(await b.fonts.import(fancy.path), isA<Ok<String>>());
    expect(await a.fonts.import(mono.path), isA<Ok<String>>());
    final bDone = b.responder.state.firstWhere((s) => s is ResponderDone);

    expect(_done(await _sync(a, b)).filesCopied, 2);

    expect(((await bDone) as ResponderDone).summary.filesCopied, 2);
    // Each side registers the font it received, and nothing twice.
    expect(a.registered, ['Mono Thing', 'Fancy Sans']);
    expect(b.registered, ['Fancy Sans', 'Mono Thing']);
    final fancyHash = _hash(fancy.readAsBytesSync());
    expect(
      File(p.join(a.paths.fonts.path, '$fancyHash.ttf')).readAsBytesSync(),
      fancy.readAsBytesSync(),
    );
    expect(await a.files.needs(), isEmpty);
    expect(await b.files.needs(), isEmpty);
  });

  test('rejects path traversal names', () async {
    final peer = (await a.peers.byId(b.id))!;
    final c = SyncClient.pinned(
      host: '127.0.0.1',
      port: b.port,
      fingerprint: peer.certFingerprint,
      pairKey: base64.decode(peer.pairKey),
      myDeviceId: a.id,
    );
    addTearDown(c.close);
    Matcher status(int code) =>
        throwsA(isA<SyncNetError>().having((e) => e.status, 'status', code));
    final hash = _hash([1]);
    final secret = File(p.join(b.paths.root.path, 'songies.db'))
      ..writeAsStringSync('secret');

    // File routes belong to a sync session that has committed.
    await expectLater(c.getJson('/files/missing'), status(409));
    await c.postJson('/session/begin', {'sync_id': 's1'});
    await expectLater(
      c.getFile('/files/art/${_hash([2])}.jpg').drain<void>(),
      status(409),
    );
    final high = (await c.getJson('/changes?since=0'))['high'] as int;
    await c.postJson('/commit', {
      'sync_id': 's1',
      'initiator_high': 0,
      'responder_high': high,
    });
    expect((await c.getJson('/files/missing'))['files'], isEmpty);

    for (final path in [
      '/files/audio/..%2F..%2Fsongies.db',
      '/files/audio/..%2F..%2F..%2Fdata%2Fsongies.db',
      '/files/art/..%2F..%2Fsongies.db',
      '/files/art/..%2F$hash.jpg',
      '/files/audio/$hash.mp3',
      '/files/audio/${hash.toUpperCase()}',
      '/files/art/$hash',
      '/files/font/%2E%2E',
      '/files/evil/$hash',
      '/files/audio/$hash/more',
    ]) {
      await expectLater(
        c.getFile(path).drain<void>(),
        status(400),
        reason: path,
      );
    }
    for (final path in [
      '/files/audio/..%2F..%2Fsongies.db?ext=mp3',
      '/files/audio/$hash?ext=..%2F..%2Fx',
      '/files/audio/$hash?ext=exe',
      '/files/audio/$hash',
      '/files/font/$hash?ext=..%2Fx',
      '/files/art/..%2F..%2Fx.jpg',
      '/files/art/${_hash([3])}.jpg?ext=mp3',
    ]) {
      await expectLater(
        c.putFile(path, Stream.value([1, 2, 3]), total: 3),
        status(400),
        reason: path,
      );
    }
    expect(
      () => a.files.receive(
        FileRef(FileKind.art, '../x.jpg'),
        Stream.value([1]),
        total: 1,
      ),
      throwsFormatException,
    );

    expect(secret.readAsStringSync(), 'secret');
    final names = [
      for (final e in b.dir.listSync(recursive: true)) p.basename(e.path),
    ];
    expect(names.where((n) => n.startsWith('x')), isEmpty);
    expect(b.parts(b.dir), isEmpty);
    await c.postJson('/files/done', {'sync_id': 's1'});
  });

  /// A signed client from A to B, with A's session on B in its files phase.
  Future<SyncClient> committedSession() async {
    final peer = (await a.peers.byId(b.id))!;
    final c = SyncClient.pinned(
      host: '127.0.0.1',
      port: b.port,
      fingerprint: peer.certFingerprint,
      pairKey: base64.decode(peer.pairKey),
      myDeviceId: a.id,
    );
    addTearDown(c.close);
    await c.postJson('/session/begin', {'sync_id': 's1'});
    final high = (await c.getJson('/changes?since=0'))['high'] as int;
    await c.postJson('/commit', {
      'sync_id': 's1',
      'initiator_high': 0,
      'responder_high': high,
    });
    return c;
  }

  Matcher status(int code) =>
      throwsA(isA<SyncNetError>().having((e) => e.status, 'status', code));

  /// A track on [d] with [hash] and no file there (or a cover [artwork]).
  Future<String> track(
    _Dev d, {
    String? hash,
    String? artwork,
    bool deleted = false,
  }) async {
    final st = await d.stamp.next();
    await d.db
        .into(d.db.tracks)
        .insert(
          trackRow(
            id: st.id,
            fileHash: hash,
            clock: st.clock,
            originDevice: st.originDevice,
            localSeq: st.localSeq,
          ).copyWith(artworkRef: Value(artwork), deleted: Value(deleted)),
        );
    return st.id;
  }

  /// Counts B's file downloads, which it still serves.
  List<String?> countGets({Future<void> Function()? before}) {
    final ranges = <String?>[];
    b.server.route('GET', '/files/', (req, peer) async {
      ranges.add(req.headers.value(HttpHeaders.rangeHeader));
      await before?.call();
      await b.files.serve(req);
    });
    return ranges;
  }

  test("a deleted row's cover is neither offered nor served", () async {
    final cover = '${_hash([9])}.jpg';
    File(p.join(b.paths.art.path, cover)).writeAsBytesSync(_bytes(100));
    await track(b, artwork: cover, deleted: true);
    final c = await committedSession();

    await expectLater(
      c.getFile('/files/art/$cover').drain<void>(),
      status(404),
    );
    final offered = await c.postJson('/files/have', {
      'files': [
        {'kind': 'art', 'name': cover},
      ],
      'pushing': 0,
    });
    expect(offered['files'], isEmpty);

    // Once a live row uses it, it is served.
    await track(b, artwork: cover);
    final got = await c
        .getFile('/files/art/$cover')
        .fold<int>(0, (n, chunk) => n + chunk.length);
    expect(got, 100);
    await c.postJson('/files/done', {'sync_id': 's1'});
  });

  test('refuses unneeded, overlong and out-of-range uploads', () async {
    final hash = _hash([5]);
    await track(b, hash: hash);
    final c = await committedSession();
    final part = File(p.join(b.paths.libraryLocal.path, '$hash.mp3.part'));

    // A file B does not lack.
    await expectLater(
      c.putFile(
        '/files/audio/${_hash([6])}?ext=mp3',
        Stream.value([1, 2, 3]),
        total: 3,
      ),
      status(409),
    );
    // Resuming past the partial file B has (none): refused, and no empty
    // part is left behind.
    await expectLater(
      c.putFile(
        '/files/audio/$hash?ext=mp3',
        Stream.value(List.filled(10, 1)),
        from: 10,
        total: 20,
      ),
      status(400),
    );
    expect(part.existsSync(), isFalse);
    // More bytes than announced (HTTP itself stops a PUT body at its
    // Content-Length, so this goes to receive directly): the part is deleted.
    expect(
      await b.files.receive(
        FileRef(FileKind.audio, hash, ext: 'mp3'),
        Stream.fromIterable([List.filled(10, 1), List.filled(10, 1)]),
        total: 15,
      ),
      isFalse,
    );
    expect(part.existsSync(), isFalse);
    await c.postJson('/files/done', {'sync_id': 's1'});
  });

  test('a stalled upload lets the session time out', () async {
    final hash = _hash([5]);
    await track(b, hash: hash);
    final c = await committedSession();
    final bytes = StreamController<List<int>>();
    final put = c.putFile(
      '/files/audio/$hash?ext=mp3',
      bytes.stream,
      total: 200000,
    );
    unawaited(put.then((_) {}, onError: (Object _) {}));
    // Enough to get past the client's write buffer.
    bytes.add(List.filled(100000, 1));
    final part = File(p.join(b.paths.libraryLocal.path, '$hash.mp3.part'));
    for (var i = 0; i < 500; i++) {
      if (part.existsSync() && part.lengthSync() > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(part.lengthSync(), greaterThan(0));
    expect(b.responder.inSession, isTrue);

    b.timers.fire(); // 15 minutes without a chunk

    expect(b.responder.inSession, isFalse);
    await pumpEventQueue();
    expect(b.states.last, isA<ResponderDone>());
    bytes.addError(StateError('peer gone'));
    await bytes.close();
  });

  test('a cancelled copy keeps its part and resumes next time', () async {
    final song = _bytes(300000);
    final id = await b.mp3('song.mp3', song);
    final hash = _hash(song);
    _done(await _sync(a, b, runner: a.rowsOnly()));
    final part = File(p.join(a.paths.libraryLocal.path, '$hash.mp3.part'));
    final cancel = SyncCancel();
    // Sends a first piece, cancels once A has written some of it, then
    // sends the rest.
    b.server.route('GET', '/files/', (req, peer) async {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.binary
        ..contentLength = song.length;
      try {
        req.response.add(song.sublist(0, 100000));
        await req.response.flush();
        for (var i = 0; i < 500; i++) {
          if (part.existsSync() && part.lengthSync() > 0) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        cancel.cancel();
        req.response.add(song.sublist(100000));
        await req.response.close();
      } catch (_) {
        // A stopped reading.
      }
    });

    final events = await a.runner
        .run(
          (await a.peers.byId(b.id))!,
          host: '127.0.0.1',
          port: b.port,
          choose: _noClashes,
          cancel: cancel,
        )
        .toList();

    expect(_done(events).filesCopied, 0);
    final kept = part.lengthSync();
    expect(kept, inExclusiveRange(0, song.length));
    expect(await a.localFile(id), isNull);

    final ranges = countGets();
    expect(_done(await _sync(a, b)).filesCopied, 1);
    expect(ranges, ['bytes=$kept-']);
    expect(part.existsSync(), isFalse);
    expect(File((await a.localFile(id))!.path).readAsBytesSync(), song);
  });

  test('a song deleted during its copy is not brought back', () async {
    final song = _bytes(5000);
    final id = await b.mp3('song.mp3', song);
    _done(await _sync(a, b, runner: a.rowsOnly()));
    final gets = countGets(
      before: () async {
        final st = await a.stamp.next();
        await (a.db.update(a.db.tracks)..where((t) => t.id.equals(id))).write(
          TracksCompanion(
            deleted: const Value(true),
            clock: Value(st.clock),
            originDevice: Value(st.originDevice),
            localSeq: Value(st.localSeq),
          ),
        );
      },
    );

    expect(_done(await _sync(a, b)).filesCopied, 0);

    expect(gets, hasLength(1));
    final row = await (a.db.select(
      a.db.tracks,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.deleted, isTrue);
    expect(await a.localFile(id), isNull);
    expect(a.parts(a.paths.root), isEmpty);
    expect(
      File(p.join(a.paths.libraryLocal.path, '${_hash(song)}.mp3'))
          .existsSync(),
      isFalse,
    );
  });

  test('a copy that cannot be attached is not downloaded again', () async {
    final id = await b.mp3('song.mp3', _bytes(5000));
    a.failHash = true;
    final gets = countGets();

    expect(_done(await _sync(a, b)).filesCopied, 0);

    expect(gets, hasLength(1));
    expect(await a.localFile(id), isNull);
  });

  test('a failed /files/done still finishes the run', () async {
    await b.mp3('song.mp3', _bytes(5000));
    b.server.route('POST', '/files/done', (req, peer) async {
      await sendJson(req, {'error': 'server'}, status: 500);
    });

    expect(_done(await _sync(a, b)).filesCopied, 1);
  });
}
