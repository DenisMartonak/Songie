import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'release.dart';

enum DownloadError { network, checksumMismatch, noChecksum, cancelled }

class DownloadProgress {
  const DownloadProgress(this.received, this.total);
  final int received;
  final int total;
}

class DownloadDone extends DownloadProgress {
  DownloadDone(this.file, int size) : super(size, size);
  final File file;
}

class DownloadFailed extends DownloadProgress {
  const DownloadFailed(this.kind, [int received = 0, int total = 0])
    : super(received, total);
  final DownloadError kind;
}

class UpdateCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class UpdateDownloader {
  UpdateDownloader({required this.dir, HttpClient Function()? client})
    : _client = client ?? HttpClient.new;

  final Directory dir;
  final HttpClient Function() _client;

  /// Fetches `SHA256SUMS`, streams the asset into `<name>.part`, verifies the
  /// digest and renames. The part file is removed on any failure or cancel.
  Stream<DownloadProgress> download(
    Release r,
    ReleaseAsset a, {
    UpdateCancel? cancel,
  }) async* {
    final sums = r.checksums;
    if (sums == null) {
      yield const DownloadFailed(DownloadError.noChecksum);
      return;
    }
    final client = _client();
    final part = File(p.join(dir.path, '${a.name}.part'));
    final target = File(p.join(dir.path, a.name));
    var received = 0;
    var total = a.size;
    DownloadError? failure;
    try {
      await dir.create(recursive: true);
      if (await part.exists()) await part.delete();

      String text;
      try {
        final res = await _get(client, sums.url);
        if (res.statusCode == 404) {
          await res.drain<void>();
          failure = DownloadError.noChecksum;
          text = '';
        } else if (res.statusCode != 200) {
          await res.drain<void>();
          failure = DownloadError.network;
          text = '';
        } else {
          text = await res.transform(utf8.decoder).join();
        }
      } on Object {
        failure = DownloadError.network;
        text = '';
      }
      if (failure == null) {
        if (cancel?.isCancelled ?? false) {
          failure = DownloadError.cancelled;
        } else if (parseSha256Sums(text)[a.name] == null) {
          failure = DownloadError.noChecksum;
        }
      }
      if (failure != null) {
        yield DownloadFailed(failure);
        return;
      }
      final expected = parseSha256Sums(text)[a.name]!;

      final out = _DigestSink();
      final hasher = sha256.startChunkedConversion(out);
      final sink = part.openWrite();
      try {
        final res = await _get(client, a.url);
        if (res.statusCode != 200) {
          await res.drain<void>();
          failure = DownloadError.network;
        } else {
          if (res.contentLength > 0) total = res.contentLength;
          await for (final chunk in res) {
            if (cancel?.isCancelled ?? false) {
              failure = DownloadError.cancelled;
              break;
            }
            sink.add(chunk);
            hasher.add(chunk);
            received += chunk.length;
            yield DownloadProgress(received, total);
          }
        }
      } on Object {
        failure = DownloadError.network;
      } finally {
        hasher.close();
        try {
          await sink.close();
        } on Object {
          failure ??= DownloadError.network;
        }
      }
      if (failure == null && (cancel?.isCancelled ?? false)) {
        failure = DownloadError.cancelled;
      }
      if (failure == null && total > 0 && received != total) {
        failure = DownloadError.network;
      }
      if (failure == null && out.digest.toString() != expected) {
        failure = DownloadError.checksumMismatch;
      }
      if (failure != null) {
        yield DownloadFailed(failure, received, total);
        return;
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      yield DownloadDone(target, received);
    } finally {
      client.close(force: true);
      try {
        if (await part.exists()) await part.delete();
      } on Object {
        // Nothing more to do; the next attempt removes it first.
      }
    }
  }

  Future<HttpClientResponse> _get(HttpClient c, Uri url) async {
    final req = await c.getUrl(url).timeout(const Duration(seconds: 30));
    return req.close().timeout(const Duration(seconds: 30));
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}
