// Dev-only real-network timing of the two playback routes, and live checks
// of the YouTube Music continuations. Run by hand; never imported by lib/
// or by tests, and not part of `flutter test` (it lives outside test/):
//
//   flutter test tool/stream_timing.dart [--dart-define=QUERY=<search>]
//
// It runs under the Flutter test runner only because lib/ imports
// package:flutter (dart:ui), which plain `dart run` can't load. Real HTTP
// works because it uses plain `test()`, never `testWidgets()`: the widget
// test binding (which installs HttpOverrides answering every request with
// 400) is never initialized. Keep it that way. Send the output to a file
// and read it before copying anything into docs.
//
// It picks 5 songs from a live YouTube Music search, resolves each through
// the real InnertubeStreamSource and then through yt-dlp (the app's binary in
// <appData>/bin, else the one on PATH; skipped if there is none), and prints
// `stream <id> via <name> in <ms> ms` per resolve. Then it checks a search
// continuation, a radio continuation, an artist radio (RDEM… playlist with
// a seed videoId) and the consent state.
//
// Output holds only public video ids, route names, times, counts and
// statuses. Never print visitor ids, tokens, stream URLs, cookies or IPs:
// failures print their error kind only. Settings live in an in-memory
// database, so no visitor id is stored anywhere.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/result.dart';
import 'package:songies/data/database.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/innertube/innertube_client.dart';
import 'package:songies/innertube/player_stream_source.dart';
import 'package:songies/innertube/transport.dart';
import 'package:songies/innertube/ytm_models.dart';
import 'package:songies/innertube/ytm_service.dart';
import 'package:songies/player/stream_source.dart';
import 'package:songies/youtube/desktop_ytdlp_runner.dart';
import 'package:songies/youtube/yt_models.dart';
import 'package:songies/youtube/ytdlp_client.dart';
import 'package:songies/youtube/ytdlp_installer.dart';

const _query = String.fromEnvironment('QUERY', defaultValue: 'daft punk');
const _songs = 5;

void main() {
  test('stream timing (real network)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final client = InnertubeClient(
      HttpInnertubeTransport(),
      SettingsRepository(db),
    );
    var consentAsked = 0;
    final consentSub = client.consentRequired.listen((_) => consentAsked++);
    final ytm = YtmService(client);

    // Songs from a live search.
    final search = await ytm.search(_query, YtmSearchKind.songs);
    final page = _ok(search, 'search');
    final songs = page?.items.whereType<YtmSong>().take(_songs).toList() ?? [];
    print(
      'search songs: ${page?.items.length ?? 0} items, using ${songs.length}',
    );

    // Innertube.
    final innertube = InnertubeStreamSource(client);
    for (final s in songs) {
      await _time(innertube, s.videoId);
    }

    // yt-dlp (the app's binary, else the system one).
    final ytdlp = _findYtDlp();
    if (ytdlp == null) {
      print('yt-dlp: not found, skipped');
    } else {
      final route = YtDlpClient(
        DesktopYtDlpRunner(
          binary: () => File('/nonexistent'),
          installer: YtDlpInstaller(
            Directory.systemTemp,
            download: (_) => throw UnsupportedError('no install'),
            isWindows: false,
          ),
          systemBinary: ytdlp,
        ),
      );
      for (final s in songs) {
        await _time(route, s.videoId);
      }
    }

    // (a) Search continuation.
    final more = page?.continuation;
    if (more == null) {
      print('check search continuation: FAIL (first page has no token)');
    } else {
      final r = await ytm.search(
        _query,
        YtmSearchKind.songs,
        continuation: more,
      );
      final p = _ok(r, 'search continuation');
      final fresh = _newIds(_songIds(page!.items), _songIds(p?.items ?? []));
      print(
        'check search continuation: ${_verdict(fresh)} '
        '(${p?.items.length ?? 0} more items, $fresh new songs, '
        'next token ${p?.continuation != null})',
      );
    }

    // (b) Radio continuation.
    if (songs.isNotEmpty) {
      final seed = songs.first.videoId;
      final radio = _ok(await ytm.radio(seed), 'radio');
      print(
        'radio $seed: ${radio?.songs.length ?? 0} songs, '
        'current ${radio?.current != null}, token ${radio?.continuation != null}',
      );
      final token = radio?.continuation;
      if (token == null) {
        print('check radio continuation: FAIL (first page has no token)');
      } else {
        final next = _ok(
          await ytm.radio(seed, continuation: token),
          'radio continuation',
        );
        final fresh = _newIds(
          {seed, ...radio!.songs.map((s) => s.videoId)},
          (next?.songs ?? []).map((s) => s.videoId),
        );
        print(
          'check radio continuation: ${_verdict(fresh)} '
          '(${next?.songs.length ?? 0} more songs, $fresh new, '
          'next token ${next?.continuation != null})',
        );
      }
    }

    // (c) Artist radio: the RDEM… playlist started from the first top song.
    final artists = _ok(
      await ytm.search(_query, YtmSearchKind.artists),
      'artist search',
    );
    final artist = artists?.items.whereType<YtmArtist>().firstOrNull;
    if (artist == null) {
      print('check artist radio: FAIL (no artist found)');
    } else {
      final ap = _ok(await ytm.artist(artist.browseId), 'artist page');
      final playlist = ap?.radioPlaylistId;
      final top = ap?.topSongs ?? const <YtmSong>[];
      print(
        'artist page: ${top.length} top songs, radio playlist '
        '${playlist == null ? 'missing' : 'RDEM ${playlist.startsWith('RDEM')}'}',
      );
      if (playlist == null || top.isEmpty) {
        print('check artist radio: FAIL (no radio playlist or top song)');
      } else {
        final seed = top.first.videoId;
        final r = _ok(
          await ytm.radio(seed, playlistId: playlist),
          'artist radio',
        );
        print(
          'check artist radio: ${_verdict(r?.songs.length)} '
          '(seed $seed, ${r?.songs.length ?? 0} songs, current ${r?.current != null})',
        );
      }
    }

    // (d) Consent.
    print(
      'check consent: asked $consentAsked time(s), '
      'given ${await client.consentGiven()}',
    );

    await consentSub.cancel();
    client.dispose();
    await db.close();
  }, timeout: Timeout.none);
}

Future<void> _time(StreamSource s, String videoId) async {
  final sw = Stopwatch()..start();
  final r = await s.resolveStream(videoId);
  final ms = sw.elapsedMilliseconds;
  switch (r) {
    case Ok():
      print('stream $videoId via ${s.name} in $ms ms');
    case Err(:final failure):
      // The kind only: messages can carry yt-dlp output.
      print(
        'stream $videoId via ${s.name} FAILED (${ytErrorKindOf(failure)?.name ?? failure.kind.name}) in $ms ms',
      );
  }
}

T? _ok<T>(Result<T> r, String what) {
  switch (r) {
    case Ok(:final value):
      return value;
    case Err(:final failure):
      print('$what: Err ${failure.kind.name}');
      return null;
  }
}

Set<String> _songIds(List<Object> items) =>
    items.whereType<YtmSong>().map((s) => s.videoId).toSet();

/// How many of [later] are not in [first]: a continuation that repeats the
/// first page counts as a failure.
int _newIds(Set<String> first, Iterable<String> later) =>
    later.toSet().difference(first).length;

String _verdict(int? n) => (n ?? 0) > 0 ? 'OK' : 'FAIL';

/// The app's own binary (`<appData>/bin/yt-dlp`, what the app runs by
/// default on Linux), else the system one on PATH.
String? _findYtDlp() {
  final env = Platform.environment;
  final xdg = env['XDG_DATA_HOME'];
  final home = env['HOME'] ?? '';
  final data = xdg != null && xdg.isNotEmpty ? xdg : '$home/.local/share';
  final app = File('$data/songies/bin/yt-dlp');
  if (app.existsSync()) return app.path;
  for (final dir in (env['PATH'] ?? '').split(':')) {
    if (dir.isNotEmpty && File('$dir/yt-dlp').existsSync()) {
      return '$dir/yt-dlp';
    }
  }
  return null;
}
