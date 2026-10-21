// Dart port of `fractional-indexing` by rocicorp
// (https://github.com/rocicorp/fractional-indexing), itself based on
// https://observablehq.com/@dgreensp/implementing-fractional-indexing
//
// The upstream source is released under CC0 1.0 (no rights reserved); the
// upstream repository's LICENSE is the CC0 legal code, not MIT.
//
// Only the default alphabet (base 62: 0-9, A-Z, a-z, with A-Z / a-z integer
// heads) is ported. Unlike upstream, which silently swaps out-of-order
// bounds, [keyBetween] throws [ArgumentError] when `a >= b`.

const String _digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const String _headDigits =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const String _zero = '0';
// Smallest possible integer part: 'A' followed by 26 zeros.
final String _smallestInteger = 'A${_zero * 26}';

int _digitValue(String ch) => _digits.indexOf(ch);

/// `a` may be empty, `b` is null or non-empty. `a < b` if `b` is non-null.
/// Neither may end in a zero digit.
String _midpoint(String a, String? b) {
  if (b != null && a.compareTo(b) >= 0) {
    throw ArgumentError('$a >= $b');
  }
  if ((a.isNotEmpty && a[a.length - 1] == _zero) ||
      (b != null && b.isNotEmpty && b[b.length - 1] == _zero)) {
    throw ArgumentError('trailing zero');
  }
  if (b != null) {
    // Strip the longest common prefix, padding `a` with zeros as we go.
    var n = 0;
    while ((n < a.length ? a[n] : _zero) == (n < b.length ? b[n] : null)) {
      n++;
    }
    if (n > 0) {
      return b.substring(0, n) + _midpoint(a.substring(n), b.substring(n));
    }
  }
  // First digits (or lack of digit) differ.
  final digitA = a.isNotEmpty ? _digitValue(a[0]) : 0;
  final digitB = b != null ? _digitValue(b[0]) : _digits.length;
  if (digitB - digitA > 1) {
    // Math.round(0.5 * (digitA + digitB)) in the reference: halves round up.
    final midDigit = (digitA + digitB + 1) ~/ 2;
    return _digits[midDigit];
  }
  // First digits are consecutive.
  if (b != null && b.length > 1) {
    return b.substring(0, 1);
  }
  // `b` is null or a single digit; `a`'s first digit precedes it.
  return _digits[digitA] + _midpoint(a.isEmpty ? '' : a.substring(1), null);
}

int _integerLength(String head) {
  final i = _headDigits.indexOf(head);
  if (i < 0) throw ArgumentError('invalid order key head: $head');
  const half = 26;
  return i < half ? half - i + 1 : i - half + 2;
}

String _integerPart(String key) {
  final length = _integerLength(key[0]);
  if (length > key.length) throw ArgumentError('invalid order key: $key');
  return key.substring(0, length);
}

void _validateInteger(String i) {
  if (i.length != _integerLength(i[0])) {
    throw ArgumentError('invalid integer part of order key: $i');
  }
}

void _validateOrderKey(String key) {
  if (key.isEmpty) throw ArgumentError('invalid order key: empty');
  if (key == _smallestInteger) throw ArgumentError('invalid order key: $key');
  // Throws if the head is bad or the key is too short.
  final i = _integerPart(key);
  final f = key.substring(i.length);
  if (f.isNotEmpty && f[f.length - 1] == _zero) {
    throw ArgumentError('invalid order key: $key');
  }
}

/// Returns null when `x` is the largest integer.
String? _incrementInteger(String x) {
  _validateInteger(x);
  final head = x[0];
  final digs = x.substring(1).split('');
  for (var i = digs.length - 1; i >= 0; i--) {
    final d = _digitValue(digs[i]) + 1;
    if (d == _digits.length) {
      digs[i] = _zero;
    } else {
      digs[i] = _digits[d];
      return head + digs.join();
    }
  }
  // Carried out of the whole digit run; `digs` is now all zeros.
  final headIndex = _headDigits.indexOf(head);
  if (headIndex == _headDigits.length - 1) return null;
  final h = _headDigits[headIndex + 1];
  // Grow or shrink the digit run to match the new head's integer length.
  final delta = _integerLength(h) - _integerLength(head);
  if (delta > 0) {
    digs.add(_zero);
  } else if (delta < 0) {
    digs.removeLast();
  }
  return h + digs.join();
}

/// Returns null when `x` is the smallest integer.
String? _decrementInteger(String x) {
  _validateInteger(x);
  final head = x[0];
  final last = _digits[_digits.length - 1];
  final digs = x.substring(1).split('');
  for (var i = digs.length - 1; i >= 0; i--) {
    final d = _digitValue(digs[i]) - 1;
    if (d == -1) {
      digs[i] = last;
    } else {
      digs[i] = _digits[d];
      return head + digs.join();
    }
  }
  // Borrowed out of the whole digit run; `digs` is now all max digits.
  final headIndex = _headDigits.indexOf(head);
  if (headIndex == 0) return null;
  final h = _headDigits[headIndex - 1];
  final delta = _integerLength(h) - _integerLength(head);
  if (delta > 0) {
    digs.add(last);
  } else if (delta < 0) {
    digs.removeLast();
  }
  return h + digs.join();
}

/// Returns a key that sorts strictly between [a] and [b]; null means
/// "no bound" on that side. Throws [ArgumentError] if either key is invalid or
/// `a >= b`.
String keyBetween(String? a, String? b) {
  if (a != null) _validateOrderKey(a);
  if (b != null) _validateOrderKey(b);
  if (a != null && b != null && a.compareTo(b) >= 0) {
    throw ArgumentError('$a >= $b');
  }

  if (a == null) {
    if (b == null) return 'a$_zero';
    final ib = _integerPart(b);
    final fb = b.substring(ib.length);
    if (ib == _smallestInteger) return ib + _midpoint('', fb);
    if (ib.compareTo(b) < 0) return ib;
    final res = _decrementInteger(ib);
    if (res == null) throw ArgumentError('cannot decrement any more');
    return res;
  }

  if (b == null) {
    final ia = _integerPart(a);
    final fa = a.substring(ia.length);
    final i = _incrementInteger(ia);
    return i ?? ia + _midpoint(fa, null);
  }

  final ia = _integerPart(a);
  final fa = a.substring(ia.length);
  final ib = _integerPart(b);
  final fb = b.substring(ib.length);
  if (ia == ib) return ia + _midpoint(fa, fb);
  final i = _incrementInteger(ia);
  if (i == null) throw ArgumentError('cannot increment any more');
  if (i.compareTo(b) < 0) return i;
  return ia + _midpoint(fa, null);
}

/// Returns [n] distinct ascending keys between [a] and [b]. With one bound
/// null the keys are consecutive integers; with both given they are short keys
/// spread evenly inside the range. Throws [ArgumentError] if `n < 0`.
List<String> nKeysBetween(String? a, String? b, int n) {
  if (n < 0) throw ArgumentError('n must be >= 0: $n');
  if (n == 0) return <String>[];
  if (n == 1) return [keyBetween(a, b)];
  if (b == null) {
    var c = keyBetween(a, b);
    final result = [c];
    for (var i = 0; i < n - 1; i++) {
      c = keyBetween(c, b);
      result.add(c);
    }
    return result;
  }
  if (a == null) {
    var c = keyBetween(a, b);
    final result = [c];
    for (var i = 0; i < n - 1; i++) {
      c = keyBetween(a, c);
      result.add(c);
    }
    return result.reversed.toList();
  }
  final mid = n ~/ 2;
  final c = keyBetween(a, b);
  return [...nKeysBetween(a, c, mid), c, ...nKeysBetween(c, b, n - mid - 1)];
}
