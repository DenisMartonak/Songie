import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show Cookie;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/innertube/yt_session.dart';
import 'package:songies/innertube/yt_sign_in.dart';

Cookie _c(String name, String value, String? domain) =>
    Cookie(name: name, value: value, domain: domain);

void main() {
  group('YtSessionFromCookies.build', () {
    test('keeps only cookies a browser sends to music.youtube.com (R8)', () {
      final s = YtSessionFromCookies.build([
        _c('SAPISID', 'yt-sap', '.youtube.com'),
        _c('HSID', 'h', 'music.youtube.com'),
        _c('PREF', 'p', 'youtube.com'),
        _c('VISITOR', 'v', '.music.youtube.com'),
        _c('WWW', 'w', 'www.youtube.com'),
        _c('ACC', 'a', 'accounts.youtube.com'),
        _c('SID', 'g-sid', '.google.com'),
        _c('NID', 'n', 'www.google.com'),
        _c('evil', 'x', '.notyoutube.com'),
        _c('evil2', 'x', 'youtube.com.example.org'),
        _c('evil3', 'x', '.example.com'),
        _c('nodomain', 'x', null),
      ]);
      expect(s, isNotNull);
      expect(s!.cookies.keys.toSet(), {'SAPISID', 'HSID', 'PREF', 'VISITOR'});
    });

    test('google.com cookies, account ones included, are dropped', () {
      final s = YtSessionFromCookies.build([
        _c('SAPISID', 'yt-sap', '.youtube.com'),
        _c('LSID', 'acct-lsid', 'accounts.google.com'),
        _c('__Host-GAPS', 'acct-gaps', 'accounts.google.com'),
        _c('__Host-1PLSID', 'acct-1plsid', 'accounts.google.com'),
        _c('SID', 'g-sid', '.google.com'),
        _c('OSID', 'mail', 'mail.google.com'),
        _c('DOCS', 'docs', 'docs.google.com'),
        _c('NID', 'n', 'www.google.com'),
      ]);
      expect(s!.cookies.keys, ['SAPISID']);
      expect(s.cookieHeader(), isNot(contains('acct-')));
    });

    test('expired cookies are dropped', () {
      final now = DateTime.utc(2026, 10, 29);
      final s = YtSessionFromCookies.build([
        _c('SAPISID', 'yt-sap', '.youtube.com'),
        Cookie(
          name: 'OLD',
          value: 'o',
          domain: '.youtube.com',
          expiresDate: now
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        ),
        Cookie(
          name: 'LIVE',
          value: 'l',
          domain: '.youtube.com',
          expiresDate: now.add(const Duration(days: 1)).millisecondsSinceEpoch,
        ),
      ], now: now);
      expect(s!.cookies.keys.toSet(), {'SAPISID', 'LIVE'});
    });

    test('Windows (WebView2) cookies: expiry in seconds, -1 for session', () {
      final now = DateTime.utc(2026, 11, 1);
      final inAYear =
          now.add(const Duration(days: 365)).millisecondsSinceEpoch ~/ 1000;
      final s = YtSessionFromCookies.build([
        Cookie(
          name: 'SAPISID',
          value: 'yt-sap',
          domain: '.youtube.com',
          expiresDate: inAYear,
          isSessionOnly: false,
        ),
        Cookie(
          name: 'YSC',
          value: 'session',
          domain: '.youtube.com',
          expiresDate: -1,
          isSessionOnly: true,
        ),
        Cookie(
          name: 'OLD',
          value: 'o',
          domain: '.youtube.com',
          expiresDate: now.millisecondsSinceEpoch ~/ 1000 - 1,
        ),
      ], now: now);
      expect(s, isNotNull);
      expect(s!.cookies.keys.toSet(), {'SAPISID', 'YSC'});
    });

    test('an expired SAPISID is no session', () {
      final now = DateTime.utc(2026, 10, 29);
      expect(
        YtSessionFromCookies.build([
          Cookie(
            name: 'SAPISID',
            value: 'old',
            domain: '.youtube.com',
            expiresDate: now.millisecondsSinceEpoch - 1000,
          ),
        ], now: now),
        isNull,
      );
    });

    test(
      'invalid names and values are dropped; DQUOTE-wrapped values kept',
      () {
        final s = YtSessionFromCookies.build([
          _c('SAPISID', 'yt-sap', '.youtube.com'),
          _c('QUOTED', '"abc"', '.youtube.com'),
          _c('SPACE', 'a b', '.youtube.com'),
          _c('SEMI', 'a;b', '.youtube.com'),
          _c('HALFQUOTE', '"abc', '.youtube.com'),
          _c('bad name', 'v', '.youtube.com'),
          _c('eq=name', 'v', '.youtube.com'),
          _c('UNI', 'caf\u00e9', '.youtube.com'),
        ]);
        expect(s!.cookies.keys.toSet(), {'SAPISID', 'QUOTED'});
        expect(s.cookies['QUOTED'], '"abc"');
      },
    );

    test('accepts __Secure-3PAPISID in place of SAPISID', () {
      final s = YtSessionFromCookies.build([
        _c('__Secure-3PAPISID', 'p', '.youtube.com'),
      ]);
      expect(s?.sapisid, 'p');
    });

    test('rejects a cookie set without SAPISID or __Secure-3PAPISID', () {
      expect(
        YtSessionFromCookies.build([
          _c('SID', 'a', '.youtube.com'),
          _c('HSID', 'b', '.google.com'),
        ]),
        isNull,
      );
    });

    test('a SAPISID on a foreign domain does not count', () {
      expect(
        YtSessionFromCookies.build([
          _c('SAPISID', 'x', '.example.com'),
          _c('SID', 'a', '.youtube.com'),
        ]),
        isNull,
      );
    });

    test('a SAPISID only on .google.com does not count', () {
      expect(
        YtSessionFromCookies.build([_c('SAPISID', 'x', '.google.com')]),
        isNull,
      );
    });

    test('a .google.com cookie never replaces a .youtube.com one', () {
      final s = YtSessionFromCookies.build([
        _c('SAPISID', 'yt', '.youtube.com'),
        _c('SAPISID', 'g', '.google.com'),
      ]);
      expect(s!.cookies['SAPISID'], 'yt');
      final t = YtSessionFromCookies.build([
        _c('SAPISID', 'g', '.google.com'),
        _c('SAPISID', 'yt', '.youtube.com'),
      ]);
      expect(t!.cookies['SAPISID'], 'yt');
    });

    test('empty names and values are dropped', () {
      final s = YtSessionFromCookies.build([
        _c('SAPISID', 'yt', '.youtube.com'),
        _c('', 'x', '.youtube.com'),
        _c('EMPTY', '', '.youtube.com'),
      ]);
      expect(s!.cookies.keys, ['SAPISID']);
    });

    test('withDomain fills a missing domain from the queried host', () {
      final out = YtSessionFromCookies.withDomain([
        _c('SAPISID', 'v', null),
        _c('SID', 'w', '.google.com'),
      ], 'music.youtube.com');
      expect(out.map((c) => c.domain), ['music.youtube.com', '.google.com']);
    });

    test('the session never prints a cookie value', () {
      final s = YtSessionFromCookies.build([
        _c('SAPISID', 'secret-value', '.youtube.com'),
      ]);
      expect(s.toString(), isNot(contains('secret-value')));
    });
  });

  test('the sign-in page starts at Google for YouTube Music', () {
    expect(
      WebViewSignIn.startUrl,
      'https://accounts.google.com/ServiceLogin?service=youtube'
      '&continue=https://music.youtube.com/',
    );
    expect(WebViewSignIn().label, 'Sign in to YouTube');
  });

  test('the page is done only on music.youtube.com', () {
    expect(
      WebViewSignIn.isDoneUrl(Uri.parse('https://music.youtube.com/')),
      isTrue,
    );
    expect(
      WebViewSignIn.isDoneUrl(
        Uri.parse(
          'https://accounts.google.com/ServiceLogin?continue='
          'https://music.youtube.com/',
        ),
      ),
      isFalse,
    );
    expect(WebViewSignIn.isDoneUrl(null), isFalse);
  });

  group('WebViewSignIn clears the web data', () {
    late List<String> calls;
    YtSession? answer;
    var forgetThrows = false;

    WebViewSignIn make() => WebViewSignIn(
      forgetStored: () async {
        calls.add('forget');
        if (forgetThrows) throw StateError('locked');
      },
      createEnvironment: () async {
        calls.add('env');
        return null;
      },
      openPage: (_, _) async {
        calls.add('open');
        return answer;
      },
      clearAfter: (_) async => calls.add('clearAfter'),
    );

    setUp(() {
      calls = [];
      answer = null;
      forgetThrows = false;
    });

    Future<YtSignInResult?> run(WidgetTester tester, WebViewSignIn r) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));
      return r.signIn(context);
    }

    testWidgets('before the page opens and after it closes', (tester) async {
      answer = YtSession({'SAPISID': 'v'});
      final res = await run(tester, make());
      expect(calls, ['forget', 'env', 'open', 'clearAfter']);
      expect(res?.session.sapisid, 'v');
    });

    testWidgets('also when the user closes the page', (tester) async {
      expect(await run(tester, make()), isNull);
      expect(calls, ['forget', 'env', 'open', 'clearAfter']);
    });

    testWidgets('a failed clear does not stop the sign-in', (tester) async {
      forgetThrows = true;
      answer = YtSession({'SAPISID': 'v'});
      expect(await run(tester, make()), isNotNull);
      expect(calls.first, 'forget');
      expect(calls, contains('open'));
    });

    test('forget clears the stored web data, never throwing', () async {
      forgetThrows = true;
      await make().forget();
      expect(calls, ['forget']);
    });
  });
}
