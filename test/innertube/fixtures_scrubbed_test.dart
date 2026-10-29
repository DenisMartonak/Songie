import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fixtures are committed to a public repo: no visitor id (it encodes the
/// visitor's country), rollout token, queue params or real IP may be left.
List<int>? decodeB64(String s) {
  if (s.length < 8 || !RegExp(r'^[A-Za-z0-9_\-+/]+={0,2}$').hasMatch(s)) {
    return null;
  }
  final n = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll('=', '');
  try {
    return base64.decode(base64.normalize(n));
  } on FormatException {
    return null;
  }
}

/// Real visitor data: protobuf 0x0A 0x0B + an 11-char id (base64 "Cgt").
bool visitorShaped(String s) {
  final b = decodeB64(s);
  return b != null && b.length >= 13 && b[0] == 0x0A && b[1] == 0x0B;
}

/// Every (key, string value) pair in [v].
void strings(Object? v, String key, void Function(String, String) f) {
  if (v is Map) {
    v.forEach((k, c) => strings(c, '$k', f));
  } else if (v is List) {
    for (final c in v) {
      strings(c, key, f);
    }
  } else if (v is String) {
    f(key, v);
  }
}

/// Plan 7: signed-in fixtures must hold no session cookie, account id,
/// email, account photo or datasync id. Returns what was found, if anything.
/// Channel ids are checked only in [signedIn] fixtures: the Plan 5 ones hold
/// public artist channels.
String? accountLeak(String text, {required bool signedIn}) {
  for (final bad in ['SAPISID', '__Secure-', 'LOGIN_INFO', 'datasyncId']) {
    if (text.contains(bad)) return bad;
  }
  // Session cookies by name, as whole words (not `__Secure-3PSID`, caught
  // above, or a longer word that merely ends in SID).
  final cookie = RegExp(r'\b(SID|HSID|SSID|APISID)=|\bSIDCC\b')
      .firstMatch(text);
  if (cookie != null) return cookie[0];
  if (text.contains('lh3.googleusercontent.com/a/')) return 'account photo';
  if (RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}')
      .hasMatch(text)) {
    return 'email';
  }
  if (signedIn) {
    for (final m in channelId.allMatches(text)) {
      if (m[0] != publicChannel) return 'channel id';
    }
  }
  return null;
}

/// A channel id as a whole token: not part of a longer word such as
/// `STYLE_LARGE_TRANSLUCENT_AND_SELECTED_WHITE`.
final channelId = RegExp(
  r'(?<![A-Za-z0-9_-])UC[A-Za-z0-9_-]{22}(?![A-Za-z0-9_-])',
);

/// Plan 5's public artist (Daft Punk), the only channel allowed in
/// signed-in fixtures.
const publicChannel = 'UCRr1xG_2WIDs18a6cIiCxeA';

/// The Plan 7 fixtures recorded with (or for) a signed-in request.
bool isSignedInFixture(String name) =>
    name.startsWith('home_signed_') || name.contains('signed_in');

void main() {
  test('the account-leak check flags secrets (self-check)', () {
    for (final bad in [
      'Cookie: SAPISID=abc',
      '__Secure-3PSID=x',
      'LOGIN_INFO',
      '"datasyncId":"x||y"',
      'https://lh3.googleusercontent.com/a/ACg8ocK=s48',
      'someone@gmail.com',
      'a.b-c@mail.example.co.uk',
      'SID=abc',
      'Cookie: HSID=a; SSID=b',
      'x APISID=y',
      'SIDCC',
      'Cookie: a=b; SIDCC=AKEy',
    ]) {
      expect(accountLeak(bad, signedIn: false), isNotNull, reason: bad);
    }
    expect(
      accountLeak('UCabcdefghijklmnopqrstuv', signedIn: true),
      'channel id',
    );
    expect(accountLeak('UCabcdefghijklmnopqrstuv', signedIn: false), isNull);
    expect(accountLeak(publicChannel, signedIn: true), isNull);
    expect(
      accountLeak('STYLE_LARGE_TRANSLUCENT_AND_SELECTED_WHITE', signedIn: true),
      isNull,
    );
    expect(accountLeak('@DaftPunk', signedIn: true), isNull);
    // Word boundaries: longer words containing the names are fine.
    for (final ok in [
      'INSIDE=1',
      'XSID=1',
      'PRESIDCC',
      'SIDCCX',
      'VISITOR_SID=1',
    ]) {
      expect(accountLeak(ok, signedIn: true), isNull, reason: ok);
    }
    expect(
      accountLeak('https://lh3.googleusercontent.com/abc=w60', signedIn: true),
      isNull,
    );
  });

  test('the detector flags visitor-shaped values (self-check)', () {
    final real = base64Url.encode([0x0A, 0x0B, ...utf8.encode('abcdefghijk')]);
    expect(visitorShaped(real), isTrue);
    expect(visitorShaped(real.replaceAll('=', '')), isTrue);
    expect(
      visitorShaped(base64.encode([0x0A, 0x0B, ...List.filled(20, 7)])),
      isTrue,
    );
    expect(visitorShaped('FAKE_VISITOR_DATA'), isFalse);
    expect(visitorShaped('hello'), isFalse);
  });

  final files = Directory('test/fixtures/innertube')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();

  test('there are fixtures to check', () => expect(files, isNotEmpty));
  test('the Plan 7 signed-in fixtures exist', () {
    final names = files.map((f) => f.uri.pathSegments.last).toSet();
    expect(
      names,
      containsAll(['home_signed_in.json', 'home_signed_out_marker.json']),
    );
  });

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    test('$name is scrubbed', () {
      final text = f.readAsStringSync();
      expect(
        accountLeak(text, signedIn: isSignedInFixture(name)),
        isNull,
        reason: 'account data left in $name',
      );
      strings(jsonDecode(text), '', (key, v) {
        expect(visitorShaped(v), isFalse, reason: 'visitor-shaped at $key');
        if (key == 'rolloutToken' || key == 'queueContextParams') {
          expect(v, startsWith('FAKE_'), reason: 'unscrubbed $key');
        }
        if (key.toLowerCase().contains('visitordata')) {
          expect(v, startsWith('FAKE_'), reason: 'unscrubbed $key');
        }
      });
      // vd= in links and any other base64 inside URLs.
      expect(RegExp(r"[?&]vd=(?!FAKE_)").hasMatch(text), isFalse);
      for (final m in RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b').allMatches(text)) {
        final s = m.group(0)!;
        final parts = s.split('.').map(int.parse);
        expect(
          s == '203.0.113.1' || parts.any((p) => p > 255),
          isTrue,
          reason: 'non-documentation IP $s',
        );
      }
    });
  }
}
