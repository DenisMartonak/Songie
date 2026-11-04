import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:songies/core/crash_reporting/scrub.dart';

void main() {
  test('scrubPaths hides POSIX, Android, Windows and file:// paths', () {
    expect(scrubPaths('/home/denis/Music/Jazz/a.flac failed'), '<path> failed');
    expect(scrubPaths('C:\\Users\\Denis\\Music\\a.mp3'), '<path>');
    expect(scrubPaths('D:/Music/a.mp3 gone'), '<path> gone');
    expect(scrubPaths(r'\\nas\share\a.mp3'), '<path>');
    expect(scrubPaths('file:///storage/emulated/0/x.m4a'), '<path>');
    expect(scrubPaths('open "/run/media/d/x y.mp3" now'), 'open "<path>" now');
    expect(
      scrubPaths("can't read '/data/user/0/app/f' ok"),
      "can't read '<path>' ok",
    );
    expect(
      scrubPaths('/tmp/a and /mnt/b and /media/c'),
      '<path> and <path> and <path>',
    );
    expect(scrubPaths('no path here'), 'no path here');
    expect(scrubPaths('/playlist/:id'), '/playlist/:id');
  });

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
