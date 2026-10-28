import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/innertube/webkit_sign_in.dart';
import 'package:songies/innertube/yt_session.dart';

WebviewCookie _c(String name, String value, String domain) => WebviewCookie(
  name: name,
  value: value,
  domain: domain,
  path: '/',
  expires: null,
  secure: true,
  httpOnly: true,
  sessionOnly: false,
);

void main() {
  group('WebKitSignIn.sessionFrom', () {
    test('keeps the YouTube cookies and needs SAPISID', () {
      final s = WebKitSignIn.sessionFrom([
        _c('SAPISID', 'sap', '.youtube.com'),
        _c('YSC', 'y', '.youtube.com'),
        _c('other', 'x', '.example.com'),
      ]);
      expect(s!.cookies.keys.toSet(), {'SAPISID', 'YSC'});
    });

    test('signed-out cookies give no session', () {
      expect(
        WebKitSignIn.sessionFrom([
          _c('YSC', 'y', '.youtube.com'),
          _c('SOCS', 's', '.youtube.com'),
        ]),
        isNull,
      );
    });
  });

  group('WebKitSignIn.webDataDirs', () {
    test('fixed child names under the default XDG homes', () {
      expect(WebKitSignIn.webDataDirs({'HOME': '/home/u'}), [
        '/home/u/.local/share/com.songies.songies',
        '/home/u/.cache/com.songies.songies',
      ]);
    });

    test('absolute XDG_DATA_HOME / XDG_CACHE_HOME win', () {
      expect(
        WebKitSignIn.webDataDirs({
          'HOME': '/home/u',
          'XDG_DATA_HOME': '/x/data',
          'XDG_CACHE_HOME': '/x/cache/',
        }),
        ['/x/data/com.songies.songies', '/x/cache/com.songies.songies'],
      );
    });

    test('relative or empty XDG values are ignored', () {
      expect(
        WebKitSignIn.webDataDirs({
          'HOME': '/home/u',
          'XDG_DATA_HOME': 'rel/data',
          'XDG_CACHE_HOME': '',
        }),
        [
          '/home/u/.local/share/com.songies.songies',
          '/home/u/.cache/com.songies.songies',
        ],
      );
    });

    test('no usable home gives nothing (never a bare parent)', () {
      expect(WebKitSignIn.webDataDirs({}), isEmpty);
      expect(WebKitSignIn.webDataDirs({'HOME': ''}), isEmpty);
      expect(WebKitSignIn.webDataDirs({'HOME': 'relative'}), isEmpty);
      expect(WebKitSignIn.webDataDirs({'HOME': '/'}), [
        '/.local/share/com.songies.songies',
        '/.cache/com.songies.songies',
      ]);
    });

    test('every path ends in the app id', () {
      for (final d in WebKitSignIn.webDataDirs({
        'HOME': '/home/u',
        'XDG_DATA_HOME': '/x/data/..',
      })) {
        expect(p.basename(d), 'com.songies.songies');
      }
    });
  });

  test('forget deletes the WebKit data dirs, leaving their parents', () async {
    final root = Directory.systemTemp.createTempSync('songies_wk_');
    addTearDown(() => root.deleteSync(recursive: true));
    final dirs = WebKitSignIn.webDataDirs({'HOME': root.path});
    for (final d in dirs) {
      Directory(d).createSync(recursive: true);
      File(p.join(d, 'salt')).writeAsStringSync('x');
    }
    final sibling = Directory(p.join(root.path, '.cache', 'other'))
      ..createSync(recursive: true);
    await WebKitSignIn(clear: () async {}, dataDirs: () => dirs).forget();
    for (final d in dirs) {
      expect(Directory(d).existsSync(), isFalse);
      expect(Directory(p.dirname(d)).existsSync(), isTrue);
    }
    expect(sibling.existsSync(), isTrue);
  });

  group('WebKitSignIn', () {
    Future<BuildContext> ctx(WidgetTester tester) async {
      late BuildContext c;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (b) {
              c = b;
              return const SizedBox();
            },
          ),
        ),
      );
      return c;
    }

    testWidgets('clears web data before and after; returns the session', (
      tester,
    ) async {
      final calls = <String>[];
      final route = WebKitSignIn(
        clear: () async => calls.add('clear'),
        openWindow: () async {
          calls.add('open');
          return YtSession({'SAPISID': 'sap'});
        },
      );
      final r = await route.signIn(await ctx(tester));
      expect(r!.session.sapisid, 'sap');
      expect(calls, ['clear', 'open', 'clear']);
    });

    testWidgets('a closed window is no sign-in; data still cleared', (
      tester,
    ) async {
      final calls = <String>[];
      final route = WebKitSignIn(
        clear: () async => calls.add('clear'),
        openWindow: () async {
          calls.add('open');
          return null;
        },
      );
      expect(await route.signIn(await ctx(tester)), isNull);
      expect(calls, ['clear', 'open', 'clear']);
    });

    testWidgets('a window that fails to open is no sign-in, not a crash', (
      tester,
    ) async {
      var clears = 0;
      final route = WebKitSignIn(
        clear: () async => clears++,
        openWindow: () async => throw StateError('no webkit'),
      );
      expect(await route.signIn(await ctx(tester)), isNull);
      expect(clears, 2);
    });

    test('forget clears the web data and never throws', () async {
      var clears = 0;
      await WebKitSignIn(
        clear: () async {
          clears++;
          throw StateError('x');
        },
        // Never the real folders in a test.
        dataDirs: () => throw StateError('y'),
      ).forget();
      expect(clears, 1);
    });

    test('label', () {
      expect(WebKitSignIn().label, 'Sign in to YouTube');
    });
  });
}
