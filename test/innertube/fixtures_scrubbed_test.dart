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

void main() {
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

  for (final f in files) {
    test('${f.uri.pathSegments.last} is scrubbed', () {
      final text = f.readAsStringSync();
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
