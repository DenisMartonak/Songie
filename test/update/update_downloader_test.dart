import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/update/release.dart';
import 'package:songies/update/update_downloader.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late String base;
  final payload = List<int>.generate(50000, (i) => i % 251);
  var sums = '';
  var serveSums = true;
  var cutAt = -1;
  Completer<void>? hold;

  Release release() => Release(
    version: const AppVersion(1, 1, 0),
    notes: '',
    htmlUrl: Uri(),
    assets: [
      ReleaseAsset(
        name: 'songies-1.1.0.apk',
        url: Uri.parse('$base/songies-1.1.0.apk'),
        size: payload.length,
      ),
      ReleaseAsset(
        name: 'SHA256SUMS',
        url: Uri.parse('$base/SHA256SUMS'),
        size: 0,
      ),
    ],
  );

  Future<List<DownloadProgress>> run({UpdateCancel? cancel}) {
    final r = release();
    return UpdateDownloader(dir: dir)
        .download(r, r.pickAsset(UpdatePlatform.android)!, cancel: cancel)
        .toList();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upd_test');
    sums = '${sha256.convert(payload)}  songies-1.1.0.apk\n';
    serveSums = true;
    cutAt = -1;
    hold = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/SHA256SUMS') {
        if (!serveSums) {
          res.statusCode = 404;
          await res.close();
          return;
        }
        res.write(sums);
        await res.close();
        return;
      }
      if (cutAt >= 0) {
        final s = await res.detachSocket(writeHeaders: false);
        s.add(
          ascii.encode(
            'HTTP/1.1 200 OK\r\ncontent-length: ${payload.length}\r\n\r\n',
          ),
        );
        s.add(payload.sublist(0, cutAt));
        await s.flush();
        s.destroy();
        return;
      }
      res.contentLength = payload.length;
      if (hold != null) {
        res.add(payload.sublist(0, 20000));
        await res.flush();
        await hold!.future;
      }
      res.add(payload.sublist(hold != null ? 20000 : 0));
      await res.close();
    });
  });

  tearDown(() async {
    if (hold?.isCompleted == false) hold!.complete();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  List<String> files() =>
      dir.listSync().map((e) => e.path.split('/').last).toList();

  test('download verifies sha256 and renames', () async {
    final events = await run();
    final done = events.last as DownloadDone;
    expect(done.file.readAsBytesSync(), payload);
    expect(files(), ['songies-1.1.0.apk']);
    expect(events.whereType<DownloadDone>(), hasLength(1));
  });

  test('checksum mismatch deletes the file', () async {
    sums = '${'0' * 64}  songies-1.1.0.apk\n';
    final last = (await run()).last as DownloadFailed;
    expect(last.kind, DownloadError.checksumMismatch);
    expect(files(), isEmpty);
  });

  test('missing SHA256SUMS fails as noChecksum', () async {
    serveSums = false;
    final last = (await run()).last as DownloadFailed;
    expect(last.kind, DownloadError.noChecksum);
    expect(files(), isEmpty);
  });

  test('SHA256SUMS without this asset fails as noChecksum', () async {
    sums = '${'a' * 64}  other.apk\n';
    final last = (await run()).last as DownloadFailed;
    expect(last.kind, DownloadError.noChecksum);
  });

  test('cut download leaves no file at the final path', () async {
    cutAt = 20000;
    final last = (await run()).last as DownloadFailed;
    expect(last.kind, DownloadError.network);
    expect(files(), isEmpty);
  });

  test('cancel removes the part file', () async {
    hold = Completer<void>();
    final cancel = UpdateCancel();
    final r = release();
    final events = <DownloadProgress>[];
    final done = UpdateDownloader(dir: dir)
        .download(r, r.pickAsset(UpdatePlatform.android)!, cancel: cancel)
        .listen((e) {
          events.add(e);
          if (e is! DownloadDone && e is! DownloadFailed) {
            cancel.cancel();
            hold!.complete();
          }
        })
        .asFuture<void>();
    await done;
    expect((events.last as DownloadFailed).kind, DownloadError.cancelled);
    expect(files(), isEmpty);
  });
}
