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

  test('scrubPaths leaves URLs and package URIs alone', () {
    for (final t in [
      'https://api.x.com/v1/a',
      'package:songies/data/repo.dart',
      'http://h/home/x',
    ]) {
      expect(scrubPaths(t), t);
    }
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
    expect(out.user, isNull);
    expect(out.serverName, isNull);
    expect(out.request, isNull);
    expect(out.breadcrumbs!.single.message, 'at <path>');
    expect(out.breadcrumbs!.single.data, {'p': '<path>', 'n': 3});
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
