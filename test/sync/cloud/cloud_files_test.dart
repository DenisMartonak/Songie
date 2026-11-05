import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/data/sync_stamp.dart';
import 'package:songies/sync/cloud/cloud_files.dart';
import 'package:songies/sync/cloud/cloud_sync.dart';

import '../../helpers/test_db.dart';
import 'fake_cloud.dart';

const _uid = 'user-a';

/// One device: a database, its fonts and art folders, and [CloudFiles].
class _Dev {
  _Dev(this.db, this.remote, this.fonts, this.art)
    : files = CloudFiles(db: db, remote: remote, fontsDir: fonts, artDir: art);

  final AppDatabase db;
  final FakeRemote remote;
  final Directory fonts;
  final Directory art;
  final CloudFiles files;

  var _seq = 0;
  int get _next => ++_seq;

  Future<void> addFont(String hash, String ext, {String family = 'Fam'}) => db
      .into(db.fonts)
      .insert(
        FontsCompanion.insert(
          id: 'font-$hash-$ext',
          clock: '0000000000001-00000-dev',
          originDevice: 'dev',
          localSeq: _next,
          family: family,
          fileHash: hash,
          ext: ext,
        ),
      );

  Future<void> addTrack(
    String id, {
    String source = 'local',
    String? art,
    String? ytVideoId,
  }) => db
      .into(db.tracks)
      .insert(
        trackRow(
          id: id,
          source: source,
          ytVideoId: ytVideoId,
          localSeq: _next,
        ).copyWith(artworkRef: Value(art)),
      );

  Future<void> addPlaylist(String id, String? cover) => db
      .into(db.playlists)
      .insert(
        PlaylistsCompanion.insert(
          id: id,
          clock: '0000000000001-00000-dev',
          originDevice: 'dev',
          localSeq: _next,
          name: id,
          source: 'local',
          coverRef: Value(cover),
        ),
      );

  Future<void> addListen(String id, String trackId, String? art) => db
      .into(db.listens)
      .insert(
        ListensCompanion.insert(
          id: id,
          clock: '0000000000001-00000-dev',
          originDevice: 'dev',
          localSeq: _next,
          trackId: trackId,
          startedAt: DateTime.utc(2026),
          heardMs: 1000,
          counted: true,
          mainArtist: 'A',
          titleSnapshot: 'T',
          artistSnapshot: 'A',
          artworkRef: Value(art),
        ),
      );

  File fontFile(String hash, String ext) =>
      File(p.join(fonts.path, '$hash.$ext'));
  File artFile(String ref) => File(p.join(art.path, ref));
}

Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);
String _sha(Uint8List b) => sha256.convert(b).toString();

void main() {
  late Directory tmp;
  late FakeServer server;
  final devs = <_Dev>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cloud_files_test');
    server = FakeServer();
  });

  tearDown(() async {
    for (final d in devs) {
      await d.db.close();
    }
    devs.clear();
    tmp.deleteSync(recursive: true);
  });

  _Dev dev(String name, {String user = _uid}) {
    final d = _Dev(
      testDb(),
      FakeRemote(server)..user = user,
      Directory(p.join(tmp.path, name, 'fonts')),
      Directory(p.join(tmp.path, name, 'art')),
    );
    devs.add(d);
    return d;
  }

  group('fonts', () {
    test('uploaded once as font/ttf, downloaded on the other device', () async {
      final a = dev('a');
      final b = dev('b');
      final bytes = _bytes('a font file');
      final hash = _sha(bytes);
      await a.addFont(hash, 'ttf');
      a.fonts.createSync(recursive: true);
      a.fontFile(hash, 'ttf').writeAsBytesSync(bytes);

      await a.files.reconcile(_uid);
      final path = '$_uid/font/$hash.ttf';
      expect(server.files.keys, [path]);
      expect(server.files[path]!.$2, 'font/ttf');
      expect(a.remote.uploads, [path]);

      // Already there: not sent again.
      await a.files.reconcile(_uid);
      expect(a.remote.uploads, [path]);
      expect(a.remote.downloads, isEmpty);

      await b.addFont(hash, 'ttf');
      await b.files.reconcile(_uid);
      expect(b.fontFile(hash, 'ttf').readAsBytesSync(), bytes);
      expect(b.remote.uploads, isEmpty);

      // Now here: not fetched again.
      await b.files.reconcile(_uid);
      expect(b.remote.downloads, [path]);
    });

    test('otf goes up as font/otf', () async {
      final a = dev('a');
      final bytes = _bytes('an otf');
      final hash = _sha(bytes);
      await a.addFont(hash, 'otf');
      a.fonts.createSync(recursive: true);
      a.fontFile(hash, 'otf').writeAsBytesSync(bytes);
      await a.files.reconcile(_uid);
      expect(server.files['$_uid/font/$hash.otf']!.$2, 'font/otf');
    });

    test('a deleted font row is neither uploaded nor downloaded', () async {
      final a = dev('a');
      final bytes = _bytes('gone');
      final hash = _sha(bytes);
      await a.addFont(hash, 'ttf');
      await a.db
          .update(a.db.fonts)
          .write(const FontsCompanion(deleted: Value(true)));
      a.fonts.createSync(recursive: true);
      a.fontFile(hash, 'ttf').writeAsBytesSync(bytes);
      await a.files.reconcile(_uid);
      expect(server.files, isEmpty);
    });

    test('a downloaded font that fails its hash is not kept', () async {
      final b = dev('b');
      final hash = _sha(_bytes('the real font'));
      server.files['$_uid/font/$hash.ttf'] = (_bytes('tampered'), 'font/ttf');
      await b.addFont(hash, 'ttf');
      await b.files.reconcile(_uid);
      expect(b.fontFile(hash, 'ttf').existsSync(), isFalse);
      expect(
        b.fonts.existsSync() ? b.fonts.listSync() : const <FileSystemEntity>[],
        isEmpty,
      );
    });
  });

  group('artwork', () {
    final h1 = 'a' * 64;
    final h2 = 'b' * 64;
    final h3 = 'c' * 64;
    final h4 = 'd' * 64;
    final h5 = 'e' * 64;

    test('YouTube art is never uploaded', () async {
      final a = dev('a');
      await a.addTrack(
        'yt1',
        source: 'yt',
        ytVideoId: 'v1',
        art: 'yt2-$h1.jpg',
      );
      // Older YouTube art without the yt2- prefix: re-fetchable too.
      await a.addTrack('yt2', source: 'yt', ytVideoId: 'v2', art: '$h2.jpg');
      // A listen of a YouTube track carries the same art.
      await a.addListen('l1', 'yt1', 'yt2-$h1.jpg');
      a.art.createSync(recursive: true);
      a.artFile('yt2-$h1.jpg').writeAsBytesSync(_bytes('jpg1'));
      a.artFile('$h2.jpg').writeAsBytesSync(_bytes('jpg2'));

      await a.files.reconcile(_uid);
      expect(a.remote.uploads, isEmpty);
      expect(server.files, isEmpty);
    });

    test(
      'YouTube art missing here is not downloaded (it is re-fetched)',
      () async {
        final b = dev('b');
        server.files['$_uid/art/yt2-$h1.jpg'] = (_bytes('x'), 'image/jpeg');
        await b.addTrack(
          'yt1',
          source: 'yt',
          ytVideoId: 'v1',
          art: 'yt2-$h1.jpg',
        );
        await b.files.reconcile(_uid);
        expect(b.remote.downloads, isEmpty);
      },
    );

    test(
      'art from tags, custom covers and their listens sync as JPEG',
      () async {
        final a = dev('a');
        final b = dev('b');
        Future<void> rows(_Dev d) async {
          await d.addTrack('t1', art: '$h1.jpg');
          await d.addPlaylist('p1', 'yt2-$h2.jpg'); // A picked cover.
          await d.addTrack('t2');
          await d.addListen('l1', 't2', '$h3.jpg');
          // A listen whose track isn't known here: not uploaded.
          await d.addListen('l2', 'nope', '$h4.jpg');
        }

        await rows(a);
        a.art.createSync(recursive: true);
        for (final r in ['$h1.jpg', 'yt2-$h2.jpg', '$h3.jpg', '$h4.jpg']) {
          a.artFile(r).writeAsBytesSync(_bytes('jpeg $r'));
        }
        // A ref with no file anywhere: nothing to do, no failure.
        await a.addTrack('t3', art: '$h5.jpg');

        await a.files.reconcile(_uid);
        expect(server.files.keys.toSet(), {
          '$_uid/art/$h1.jpg',
          '$_uid/art/yt2-$h2.jpg',
          '$_uid/art/$h3.jpg',
        });
        expect({for (final f in server.files.values) f.$2}, {'image/jpeg'});

        await a.files.reconcile(_uid);
        expect(a.remote.uploads, hasLength(3));

        await rows(b);
        await b.files.reconcile(_uid);
        for (final r in ['$h1.jpg', 'yt2-$h2.jpg', '$h3.jpg']) {
          expect(b.artFile(r).readAsBytesSync(), _bytes('jpeg $r'));
        }
        expect(b.artFile('$h4.jpg').existsSync(), isFalse);
        expect(b.remote.uploads, isEmpty);
      },
    );

    test('a deleted track keeps its art off the bucket', () async {
      final a = dev('a');
      await a.addTrack('t1', art: '$h1.jpg');
      await a.db
          .update(a.db.tracks)
          .write(const TracksCompanion(deleted: Value(true)));
      a.art.createSync(recursive: true);
      a.artFile('$h1.jpg').writeAsBytesSync(_bytes('x'));
      await a.files.reconcile(_uid);
      expect(server.files, isEmpty);
    });
  });

  group('bad names', () {
    test('font and art names outside the rules are refused', () async {
      final a = dev('a');
      final escape = _sha(_bytes('x'));
      await a.addFont('../../evil', 'ttf');
      await a.addFont(escape, 'exe');
      await a.addFont(escape.toUpperCase(), 'ttf');
      await a.addTrack('t1', art: '../$escape.jpg');
      await a.addTrack('t2', art: '$escape.gif');
      await a.addPlaylist('p1', 'yt3-$escape.jpg');
      // Files the bad rows would point at, both here and on the server.
      a.fonts.createSync(recursive: true);
      a.fontFile(escape, 'exe').writeAsBytesSync(_bytes('x'));
      a.art.createSync(recursive: true);
      a.artFile('$escape.gif').writeAsBytesSync(_bytes('x'));
      server.files['$_uid/font/$escape.exe'] = (_bytes('x'), 'font/ttf');
      server.files['$_uid/art/../$escape.jpg'] = (_bytes('x'), 'image/jpeg');

      await a.files.reconcile(_uid);
      expect(a.remote.uploads, isEmpty);
      expect(a.remote.downloads, isEmpty);
      expect(File(p.join(tmp.path, 'evil.ttf')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'a', '$escape.jpg')).existsSync(), isFalse);
    });

    test('names alone are checked too', () {
      expect(CloudFiles.isFontName('${'a' * 64}.ttf'), isTrue);
      expect(CloudFiles.isFontName('${'a' * 64}.otf'), isTrue);
      expect(CloudFiles.isFontName('${'a' * 63}.ttf'), isFalse);
      expect(CloudFiles.isFontName('${'a' * 64}.woff'), isFalse);
      expect(CloudFiles.isArtName('${'a' * 64}.jpg'), isTrue);
      expect(CloudFiles.isArtName('yt2-${'a' * 64}.jpg'), isTrue);
      expect(CloudFiles.isArtName('${'a' * 64}.png'), isFalse);
      expect(CloudFiles.isArtName('x/${'a' * 64}.jpg'), isFalse);
    });
  });

  group('network', () {
    test('offline: nothing thrown, the next run catches up', () async {
      final a = dev('a');
      final bytes = _bytes('f');
      final hash = _sha(bytes);
      await a.addFont(hash, 'ttf');
      a.fonts.createSync(recursive: true);
      a.fontFile(hash, 'ttf').writeAsBytesSync(bytes);

      a.remote.filesOffline = true;
      await a.files.reconcile(_uid);
      expect(server.files, isEmpty);

      a.remote.filesOffline = false;
      await a.files.reconcile(_uid);
      expect(server.files.keys, ['$_uid/font/$hash.ttf']);
    });

    test('a failed upload is retried on the next run', () async {
      final a = dev('a');
      final bytes = _bytes('f');
      final hash = _sha(bytes);
      await a.addFont(hash, 'ttf');
      a.fonts.createSync(recursive: true);
      a.fontFile(hash, 'ttf').writeAsBytesSync(bytes);

      a.remote.failUploads = true;
      await a.files.reconcile(_uid);
      expect(server.files, isEmpty);
      a.remote.failUploads = false;
      await a.files.reconcile(_uid);
      expect(server.files, hasLength(1));
    });

    test('nothing to sync makes no storage call', () async {
      final a = dev('a');
      await a.addTrack(
        'yt1',
        source: 'yt',
        ytVideoId: 'v',
        art: 'yt2-${'a' * 64}.jpg',
      );
      await a.files.reconcile(_uid);
      expect(a.remote.listCalls, 0);
    });
  });

  test('deleteAll empties the folder and leaves other users alone', () async {
    final a = dev('a');
    final hash = 'a' * 64;
    server.files['$_uid/font/$hash.ttf'] = (_bytes('x'), 'font/ttf');
    server.files['$_uid/art/$hash.jpg'] = (_bytes('x'), 'image/jpeg');
    server.files['$_uid/art/yt2-$hash.jpg'] = (_bytes('x'), 'image/jpeg');
    server.files['other/font/$hash.ttf'] = (_bytes('x'), 'font/ttf');

    await a.files.deleteAll(_uid);
    expect(server.files.keys, ['other/font/$hash.ttf']);
  });

  test('deleteAll fails loudly when offline (the account must stay)', () async {
    final a = dev('a');
    server.files['$_uid/art/${'a' * 64}.jpg'] = (_bytes('x'), 'image/jpeg');
    a.remote.filesOffline = true;
    await expectLater(a.files.deleteAll(_uid), throwsA(anything));
    expect(server.files, hasLength(1));
  });

  test('a sync run reconciles the files', () async {
    final a = dev('a');
    final bytes = _bytes('f');
    final hash = _sha(bytes);
    await a.addFont(hash, 'ttf');
    a.fonts.createSync(recursive: true);
    a.fontFile(hash, 'ttf').writeAsBytesSync(bytes);
    final stamp = await SyncStamp.load(a.db);
    final sync = CloudSync(
      db: a.db,
      stamp: stamp,
      remote: a.remote,
      settings: SettingsRepository(a.db),
      fontsDir: a.fonts,
      files: a.files,
    );
    await sync.start(_uid);
    expect(server.files.keys, ['$_uid/font/$hash.ttf']);
    await sync.dispose();
  });
}
