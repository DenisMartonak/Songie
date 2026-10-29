import 'dart:async';

import 'package:songies/data/database.dart';
import 'package:songies/lyrics/lyrics_service.dart';

/// Answers lookups from [answers] (or a [gates] completer when one is set)
/// and records every lookup and prefetch.
class FakeLyricsService implements LyricsService {
  final answers = <String, LyricsState>{};
  final gates = <String, Completer<LyricsState>>{};
  final lookups = <({String id, bool force})>[];
  final prefetched = <String?>[];

  @override
  Future<LyricsState> lookup(Track t, {bool force = false}) {
    lookups.add((id: t.id, force: force));
    final gate = gates[t.id];
    if (gate != null) return gate.future;
    return Future.value(answers[t.id] ?? const LyricsNone());
  }

  @override
  void prefetch(Track? t) => prefetched.add(t?.id);
}
