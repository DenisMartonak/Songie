import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show Cookie;
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/innertube/yt_sign_in.dart';

Cookie _c(String name, String value, String? domain) =>
    Cookie(name: name, value: value, domain: domain);

void main() {
  group('YtSessionFromCookies.build', () {
    test('keeps only .youtube.com and .google.com cookies', () {
      final s = YtSessionFromCookies.build([
        _c('SAPISID', 'yt-sap', '.youtube.com'),
        _c('HSID', 'h', 'music.youtube.com'),
        _c('SID', 'g-sid', '.google.com'),
        _c('NID', 'n', 'www.google.com'),
        _c('evil', 'x', '.notyoutube.com'),
        _c('evil2', 'x', 'youtube.com.example.org'),
        _c('evil3', 'x', '.example.com'),
        _c('nodomain', 'x', null),
      ]);
      expect(s, isNotNull);
      expect(s!.cookies.keys.toSet(), {'SAPISID', 'HSID', 'SID', 'NID'});
    });

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

    test('the .youtube.com value wins over a .google.com one', () {
      final s = YtSessionFromCookies.build([
        _c('SAPISID', 'yt', '.youtube.com'),
        _c('SAPISID', 'g', '.google.com'),
      ]);
      expect(s!.cookies['SAPISID'], 'yt');
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
}
