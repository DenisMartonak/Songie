// ignore_for_file: deprecated_member_use
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:songies/core/crash_reporting/scrub.dart';

void main() {
  test('scrubPaths hides POSIX, Android, Windows and file:// paths', () {
    expect(scrubPaths('/home/denis/Music/Jazz/a.flac: failed'), '<path>');
    expect(scrubPaths('C:\\Users\\Denis\\Music\\a.mp3'), '<path>');
    expect(scrubPaths('D:/Music/a.mp3, gone'), '<path>');
    expect(scrubPaths(r'\\nas\share\a.mp3'), '<path>');
    expect(scrubPaths('file:///storage/emulated/0/x.m4a'), '<path>');
    expect(scrubPaths('open "/run/media/d/x y.mp3" now'), 'open "<path>" now');
    expect(
      scrubPaths("can't read '/data/user/0/app/f' ok"),
      "can't read '<path>' ok",
    );
    expect(scrubPaths('/tmp/a and /mnt/b and /media/c'), '<path>');
    expect(scrubPaths('no path here'), 'no path here');
    expect(scrubPaths('/playlist/:id'), '/playlist/:id');
  });

  test('scrubPaths hides whole quoted and spaced names', () {
    expect(
      scrubPaths("path = '/home/d/Don't Stop.mp3' (OS Error)"),
      "path = '<path>' (OS Error)",
    );
    expect(scrubPaths('Failed /home/d/My Song.mp3: x'), 'Failed <path>');
    expect(scrubPaths(r'Failed C:\Users\d\My Song.flac: x'), 'Failed <path>');
    expect(scrubPaths('a /tmp/x.mp3 and later b.json'), 'a <path>');
  });

  test('scrubPaths hides whole paths with apostrophes and spaces', () {
    expect(
      scrubPaths(
        "PathNotFoundException: Cannot open file, path = '/storage/emulated/0/Music/Guns N' Roses - Don't Cry.flac' (OS Error: No such file or directory, errno = 2)",
      ),
      "PathNotFoundException: Cannot open file, path = '<path>' (OS Error: No such file or directory, errno = 2)",
    );
    expect(
      scrubPaths('Cannot open /home/d/My Private Folder/secret stuff'),
      'Cannot open <path>',
    );
    expect(
      scrubPaths(
        r"FileSystemException: Cannot open file, path = 'D:\Hudba\AC DC - It's a Long Way.mp3' (OS Error: x, errno = 2)",
      ),
      "FileSystemException: Cannot open file, path = '<path>' (OS Error: x, errno = 2)",
    );
    expect(
      scrubPaths("copy '/home/a/x y' to '/tmp/b/it's z' now"),
      "copy '<path>' to '<path>' now",
    );
    expect(scrubPaths('bad (/home/d/a b) after'), 'bad (<path>');
  });

  test('scrubPaths hides unquoted names holding commas and colons', () {
    expect(scrubPaths('/home/d/Music/Simon, Garfunkel.mp3'), '<path>');
    expect(scrubPaths('/home/d/Artist: Title.mp3'), '<path>');
    expect(scrubPaths('bad /home/d/a: b\nnext line'), 'bad <path>\nnext line');
  });

  test('scrubPaths knows more roots and content URIs', () {
    for (final p in [
      '/sdcard/a',
      '/root/a',
      '/Users/d/a',
      '/var/a',
      '/opt/a',
      '/proc/1/a',
      '~/Music/a',
    ]) {
      expect(scrubPaths('x $p y'), 'x <path>', reason: p);
    }
    expect(scrubPaths('content://media/external/audio/media/12'), '<path>');
  });

  test('scrubPaths leaves package URIs and route templates alone', () {
    for (final t in [
      'package:songies/data/repo.dart',
      'dart:async/zone.dart',
      'https://api.x.com',
    ]) {
      expect(scrubPaths(t), t);
    }
  });

  test('scrubPaths keeps only the scheme and host of web URLs', () {
    expect(
      scrubPaths(
        'HttpException: Connection closed, uri = '
        'https://rr3---sn-abc.googlevideo.com/videoplayback?id=o-x&ip=1.2.3.4',
      ),
      'HttpException: Connection closed, uri = '
      'https://rr3---sn-abc.googlevideo.com/<redacted>',
    );
    expect(
      scrubPaths('GET http://i.ytimg.com/vi/dQw4w9WgXcQ/hq.jpg failed'),
      'GET http://i.ytimg.com/<redacted> failed',
    );
    expect(scrubPaths("'https://h/home/x' x"), "'https://h/<redacted>' x");
    expect(
      scrubPaths('https://u:pw@h.com:8080?q=1'),
      'https://h.com:8080/<redacted>',
    );
    expect(scrubPaths('HTTPS://H.com/a#b'), 'HTTPS://H.com/<redacted>');
  });

  test(
    'scrubEvent scrubs extra, tags, contexts, frames and drops other crumbs',
    () {
      final frame = SentryStackFrame(
        absPath: '/home/d/app/x.dart',
        fileName: '/home/d/app/x.dart',
      );
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'E',
            value: 'v',
            stackTrace: SentryStackTrace(frames: [frame]),
          ),
        ],
        extra: {
          'a': '/tmp/z',
          'n': {'k': '/tmp/q'},
        },
        tags: {'t': '/tmp/z'},
        transaction: '/tmp/t',
        fingerprint: ['/tmp/f'],
        breadcrumbs: [
          Breadcrumb(category: 'http'),
          Breadcrumb(category: 'player'),
        ],
      );
      event.contexts['custom'] = '/tmp/c';
      final out = scrubEvent(event, Hint())!;
      expect(frame.absPath, '<path>');
      expect(frame.fileName, '<path>');
      expect(out.extra, {
        'a': '<path>',
        'n': {'k': '<path>'},
      });
      expect(out.tags, {'t': '<path>'});
      expect(out.transaction, '<path>');
      expect(out.fingerprint, ['<path>']);
      expect(out.contexts['custom'], '<path>');
      expect(out.breadcrumbs!.map((c) => c.category), ['player']);
    },
  );

  test('scrubEvent scrubs exception values and drops user and server name', () {
    final event = SentryEvent(
      exceptions: [SentryException(type: 'E', value: 'bad /home/d/a.flac')],
      message: SentryMessage('open /home/d/b.flac'),
      user: SentryUser(id: 'u'),
      serverName: 'host',
      request: SentryRequest(url: 'https://x', data: 'secret'),
      breadcrumbs: [
        Breadcrumb(
          message: 'at /tmp/x',
          category: 'player',
          data: {'p': '/tmp/y', 'n': 3},
        ),
      ],
    );
    final out = scrubEvent(event, Hint())!;
    expect(out.exceptions!.single.value, 'bad <path>');
    expect(out.message!.formatted, 'open <path>');
    expect(out.user!.id, 'u');
    expect(out.serverName, isNull);
    expect(out.request, isNull);
    expect(out.breadcrumbs!.single.message, 'at <path>');
    expect(out.breadcrumbs!.single.data, {'p': '<path>', 'n': 3});
  });

  test('scrubEvent keeps only the user id', () {
    final event = SentryEvent(
      user: SentryUser(
        id: 'install-1',
        username: 'denis',
        email: 'd@x.com',
        ipAddress: '1.2.3.4',
        name: 'Denis',
        data: {'home': '/home/denis'},
      ),
    );
    final user = scrubEvent(event, Hint())!.user!;
    expect(user.toJson(), {'id': 'install-1'});
    expect(
      scrubEvent(SentryEvent(user: SentryUser(username: 'd')), Hint())!.user,
      isNull,
    );
  });

  test('scrubEvent keeps only the file names of debug images', () {
    final event = SentryEvent(
      debugMeta: DebugMeta(
        images: [
          DebugImage(
            type: 'pe',
            codeFile:
                r'C:\Users\Denis\AppData\Local\Programs\Songies\songies.exe',
            debugFile: r'C:\Users\Denis\build\songies.pdb',
            debugId: 'abc',
            codeId: 'def',
          ),
          DebugImage(
            type: 'elf',
            codeFile: '/home/denis/Apps/Songies.AppImage/lib/libmpv.so.2',
          ),
          DebugImage(type: 'elf', codeFile: 'libc.so.6'),
          DebugImage(type: 'macho'),
        ],
      ),
    );
    final images = scrubEvent(event, Hint())!.debugMeta!.images;
    expect(images.map((i) => i.codeFile), [
      'songies.exe',
      'libmpv.so.2',
      'libc.so.6',
      null,
    ]);
    expect(images.first.debugFile, 'songies.pdb');
    expect(images.first.debugId, 'abc');
    expect(images.first.codeId, 'def');
  });

  test(
    'filterBreadcrumb keeps navigation and player, drops http and ui.click',
    () {
      expect(
        filterBreadcrumb(Breadcrumb(category: 'navigation'), Hint()),
        isNotNull,
      );
      expect(
        filterBreadcrumb(Breadcrumb(category: 'player'), Hint()),
        isNotNull,
      );
      expect(
        filterBreadcrumb(Breadcrumb(category: 'app.lifecycle'), Hint()),
        isNotNull,
      );
      expect(filterBreadcrumb(Breadcrumb(category: 'http'), Hint()), isNull);
      expect(
        filterBreadcrumb(Breadcrumb(category: 'ui.click'), Hint()),
        isNull,
      );
      expect(filterBreadcrumb(Breadcrumb(), Hint()), isNull);
      expect(filterBreadcrumb(null, Hint()), isNull);
      final kept = filterBreadcrumb(
        Breadcrumb(category: 'player', message: 'x /home/a/b'),
        Hint(),
      );
      expect(kept!.message, 'x <path>');
    },
  );
}
