import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';

import '../core/log.dart';
import '../library/art_cache.dart';

/// Colours derived from a cover. [isFallback] is true for greyscale art,
/// where no meaningful accent exists.
class CoverPalette {
  const CoverPalette({
    required this.dominant,
    required this.vibrant,
    required this.muted,
    this.isFallback = false,
  });

  final Color dominant;
  final Color vibrant;
  final Color muted;
  final bool isFallback;

  Map<String, Object?> toJson() => {
        'dominant': dominant.toARGB32(),
        'vibrant': vibrant.toARGB32(),
        'muted': muted.toARGB32(),
        'isFallback': isFallback,
      };

  factory CoverPalette.fromJson(Map<String, Object?> j) => CoverPalette(
        dominant: Color(j['dominant']! as int),
        vibrant: Color(j['vibrant']! as int),
        muted: Color(j['muted']! as int),
        isFallback: j['isFallback']! as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is CoverPalette &&
      other.dominant == dominant &&
      other.vibrant == vibrant &&
      other.muted == muted &&
      other.isFallback == isFallback;

  @override
  int get hashCode => Object.hash(dominant, vibrant, muted, isFallback);
}

/// Decodes [bytes], downscales to 64x64 and extracts a [CoverPalette], or
/// null if the bytes cannot be decoded. Run it in an isolate.
Future<CoverPalette?> extractCoverPalette(Uint8List bytes) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final small = img.copyResize(decoded,
      width: 64, height: 64, interpolation: img.Interpolation.average);
  final pixels = <int>[];
  for (final px in small) {
    if (px.a < 128) continue;
    pixels.add(
        0xFF000000 | (px.r.toInt() << 16) | (px.g.toInt() << 8) | px.b.toInt());
  }
  if (pixels.isEmpty) return null;

  final populations = (await QuantizerCelebi().quantize(pixels, 64)).colorToCount;
  final ranked = Score.score(populations, filter: false);
  final vibrant = ranked.first;
  final dominant =
      populations.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  final dh = Hct.fromInt(dominant);
  final muted = Hct.from(dh.hue, dh.chroma * 0.4, dh.tone).toInt();
  return CoverPalette(
    dominant: Color(dominant),
    vibrant: Color(vibrant),
    muted: Color(muted),
    isFallback: Hct.fromInt(vibrant).chroma < 15,
  );
}

Future<CoverPalette?> _extractInIsolate(Uint8List bytes) =>
    Isolate.run(() => extractCoverPalette(bytes));

/// Cover palettes with a memory cache and a `<ref>.palette.json` disk cache.
/// Extractions run one at a time: page requests (`supersede: false`) in the
/// order they came, ahead of the newest current-track request.
class CoverPaletteService {
  CoverPaletteService(
    this._art, {
    this.extract = _extractInIsolate,
  });

  final ArtCache _art;
  final Future<CoverPalette?> Function(Uint8List) extract;
  final Map<String, CoverPalette> _memory = {};
  final Map<String, Future<CoverPalette?>> _jobs = {};
  String? _pendingRef;
  Completer<CoverPalette?>? _pending;

  /// Requests that are never superseded, oldest first.
  final List<(String, Completer<CoverPalette?>)> _steady = [];
  bool _busy = false;

  File _paletteFile(String ref) =>
      File('${_art.fileFor(ref).path}.palette.json');

  /// The palette for [artRef], or null for a null ref, a missing or
  /// undecodable file. Never throws.
  ///
  /// By default a request still waiting for extraction is dropped (completes
  /// with null) when a newer one arrives, which suits the playing track.
  /// With [supersede] false it waits its turn and always resolves its own
  /// ref, for page colours (a playlist's cover) that must not be starved.
  Future<CoverPalette?> paletteFor(
    String? artRef, {
    bool supersede = true,
  }) async {
    if (artRef == null) return null;
    final hit = _memory[artRef];
    if (hit != null) return hit;
    try {
      final fromDisk = _readJson(artRef);
      if (fromDisk != null) return _memory[artRef] = fromDisk;

      return await _enqueue(artRef, supersede: supersede);
    } catch (e, s) {
      AppLog.w('Palette for $artRef failed', e, s);
      return null;
    }
  }

  /// Emits the palette for each ref in [artRefs]; only the latest ref counts,
  /// so a result for a superseded ref is never emitted. A null ref emits null.
  Stream<CoverPalette?> paletteStream(Stream<String?> artRefs) {
    late StreamController<CoverPalette?> out;
    StreamSubscription<String?>? sub;
    var latest = 0;
    out = StreamController<CoverPalette?>(
      onListen: () {
        sub = artRefs.listen((ref) {
          final mine = ++latest;
          if (ref == null) {
            out.add(null);
            return;
          }
          paletteFor(ref).then((p) {
            if (mine == latest && !out.isClosed) out.add(p);
          });
        }, onError: out.addError, onDone: out.close);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// One extraction runs at a time. A superseding request waiting behind it
  /// is replaced by a newer one: the replaced request completes with null
  /// without extracting (it is stale), so the newest ref runs next, after the
  /// non-superseding requests already waiting.
  Future<CoverPalette?> _enqueue(String ref, {required bool supersede}) {
    final existing = _jobs[ref];
    if (existing != null) {
      final pending = _pending;
      if (!supersede && ref == _pendingRef && pending != null) {
        // Someone needs this one: it may no longer be dropped.
        _pending = null;
        _pendingRef = null;
        _steady.add((ref, pending));
      }
      return existing;
    }
    final completer = Completer<CoverPalette?>();
    _jobs[ref] = completer.future;
    if (supersede) {
      final stale = _pending;
      if (stale != null) {
        _jobs.remove(_pendingRef);
        stale.complete(null);
      }
      _pendingRef = ref;
      _pending = completer;
    } else {
      _steady.add((ref, completer));
    }
    _pump();
    return completer.future;
  }

  Future<void> _pump() async {
    if (_busy) return;
    final String ref;
    final Completer<CoverPalette?> completer;
    if (_steady.isNotEmpty) {
      (ref, completer) = _steady.removeAt(0);
    } else {
      final pending = _pending;
      final pendingRef = _pendingRef;
      if (pending == null || pendingRef == null) return;
      _pending = null;
      _pendingRef = null;
      ref = pendingRef;
      completer = pending;
    }
    _busy = true;
    CoverPalette? result;
    try {
      result = await _extractAndStore(ref);
    } catch (e, s) {
      AppLog.w('Palette for $ref failed', e, s);
    }
    _jobs.remove(ref);
    _busy = false;
    completer.complete(result);
    unawaited(_pump());
  }

  CoverPalette? _readJson(String ref) {
    final f = _paletteFile(ref);
    if (!f.existsSync()) return null;
    try {
      return CoverPalette.fromJson(
          jsonDecode(f.readAsStringSync()) as Map<String, Object?>);
    } catch (e) {
      AppLog.w('Ignoring bad palette cache for $ref', e);
      return null;
    }
  }

  Future<CoverPalette?> _extractAndStore(String ref) async {
    final cached = _memory[ref];
    if (cached != null) return cached;
    final file = _art.fileFor(ref);
    if (!file.existsSync()) return null;
    final palette = await extract(file.readAsBytesSync());
    if (palette == null) return null;
    _memory[ref] = palette;
    try {
      final target = _paletteFile(ref);
      final tmp = File('${target.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(palette.toJson()), flush: true);
      tmp.renameSync(target.path);
    } on FileSystemException catch (e, s) {
      AppLog.w('Palette cache write failed for $ref', e, s);
    }
    return palette;
  }
}
