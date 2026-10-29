import 'dart:async';

import 'package:drift/drift.dart';

import '../data/database.dart';
import 'stats_models.dart';

/// Listening statistics computed from the `listens` table.
///
/// Days are local calendar days. Internally every local time is kept as a
/// "wall clock" value: its local fields stored in a UTC [DateTime], so day
/// arithmetic never crosses a DST jump and an injected `toLocal` (tests)
/// works the same way as the real time zone.
class StatsRepository {
  StatsRepository(
    this._db, {
    DateTime Function() now = DateTime.now,
    DateTime Function(DateTime utc)? toLocal,
    Duration throttle = const Duration(seconds: 5),
  }) : _now = now, // ignore: prefer_initializing_formals
       _toLocal = toLocal ?? ((u) => u.toLocal()),
       _throttle = throttle; // ignore: prefer_initializing_formals

  final AppDatabase _db;
  final DateTime Function() _now;
  final DateTime Function(DateTime utc) _toLocal;
  final Duration _throttle;

  static const _topCount = 10;

  /// Stats for [p], ending today.
  Future<PeriodStats> period(StatsPeriod p) async {
    final today = _day(_wall(_now().toUtc()));
    final end = _addDays(today, 1);
    final start = _addDays(today, -(p.days - 1));
    final prevStart = _addDays(start, -p.days);

    // One indexed range query over the few columns the totals need (a
    // narrow raw select: mapping whole rows dominated the cost). The
    // wall-clock bound is widened by a day so it is safe for any UTC offset;
    // rows are then placed exactly by their local time below.
    final t = _db.listens;
    final from = prevStart.subtract(const Duration(days: 1));
    final rows = await _db
        .customSelect(
          'SELECT id, track_id, started_at, heard_ms, counted, main_artist, '
          'title_snapshot FROM listens '
          'WHERE started_at >= ? AND deleted = 0 ORDER BY started_at',
          variables: [Variable<DateTime>(from)],
          readsFrom: {t},
        )
        .get();

    final buckets = _bucketRanges(p, start, end);
    final bucketHeard = List<int>.filled(buckets.length, 0);
    var totalMs = 0;
    var prevMs = 0;
    var prevAny = false;
    final songs = <String, _SongAcc>{};
    final artists = <String, _ArtistAcc>{};

    for (final r in rows) {
      final local = _wall(r.read<DateTime>('started_at').toUtc());
      if (local.isBefore(prevStart) || !local.isBefore(end)) continue;
      final heardMs = r.read<int>('heard_ms');
      if (local.isBefore(start)) {
        prevMs += heardMs;
        prevAny = true;
        continue;
      }
      totalMs += heardMs;
      bucketHeard[_bucketIndex(p, start, local)] += heardMs;

      final counted = r.read<bool>('counted');
      final trackId = r.read<String>('track_id');
      // Rows come oldest first, so the last write wins as "latest".
      final song = songs.putIfAbsent(trackId, () => _SongAcc(trackId))
        ..add(heardMs, counted)
        ..latestId = r.read<String>('id')
        ..title = r.read<String>('title_snapshot');

      final name = r.read<String>('main_artist').trim();
      if (name.isEmpty) continue;
      final artist = artists.putIfAbsent(name.toLowerCase(), _ArtistAcc.new)
        ..add(heardMs, counted)
        ..name = name;
      artist.songs[trackId] = song;
    }

    final topSongs =
        (songs.values.toList()..sort((a, b) => _rank(a, b, a.title, b.title)))
            .take(_topCount)
            .toList();
    final topArtists =
        (artists.values.toList()..sort((a, b) => _rank(a, b, a.name, b.name)))
            .take(_topCount)
            .toList();
    final samples = {for (final a in topArtists) a: a.mostPlayed()};

    // Snapshots only for the listens shown.
    final snapshotIds = {
      for (final s in topSongs) s.latestId,
      for (final s in samples.values) s.latestId,
    };
    final snapshots = {
      for (final r in await (_db.select(
        t,
      )..where((l) => l.id.isIn(snapshotIds))).get())
        r.id: r,
    };

    return PeriodStats(
      period: p,
      total: Duration(milliseconds: totalMs),
      previousTotal: prevAny ? Duration(milliseconds: prevMs) : null,
      buckets: [
        for (var i = 0; i < buckets.length; i++)
          StatsBucket(
            start: _localOf(buckets[i].$1),
            end: _localOf(buckets[i].$2),
            heard: Duration(milliseconds: bucketHeard[i]),
          ),
      ],
      topArtists: [
        for (final a in topArtists)
          ArtistStat(
            name: a.name,
            plays: a.plays,
            heard: Duration(milliseconds: a.heardMs),
            artworkRef: snapshots[samples[a]!.latestId]?.artworkRef,
            sampleTrackId: samples[a]!.trackId,
          ),
      ],
      topSongs: [
        for (final s in topSongs)
          SongStat(
            trackId: s.trackId,
            title: s.title,
            artist: snapshots[s.latestId]?.artistSnapshot ?? '',
            artworkRef: snapshots[s.latestId]?.artworkRef,
            plays: s.plays,
            heard: Duration(milliseconds: s.heardMs),
          ),
      ],
    );
  }

  /// [period] now and again whenever `listens` changes, at most once per
  /// throttle window (the last change in a burst is always emitted).
  Stream<PeriodStats> watch(StatsPeriod p) {
    late final StreamController<PeriodStats> out;
    StreamSubscription<void>? updates;
    Timer? cooldown;
    var pending = false;
    var chain = Future<void>.value();

    void emit() {
      chain = chain.then((_) async {
        try {
          final s = await period(p);
          if (!out.isClosed) out.add(s);
        } catch (e, st) {
          if (!out.isClosed) out.addError(e, st);
        }
      });
    }

    void fire() {
      emit();
      cooldown = Timer(_throttle, () {
        cooldown = null;
        if (pending) {
          pending = false;
          fire();
        }
      });
    }

    out = StreamController<PeriodStats>(
      onListen: () {
        emit();
        updates = _db
            .tableUpdates(TableUpdateQuery.onTable(_db.listens))
            .listen((_) => cooldown == null ? fire() : pending = true);
      },
      onCancel: () async {
        cooldown?.cancel();
        await updates?.cancel();
        await out.close();
      },
    );
    return out.stream;
  }

  /// The local wall-clock time of [utc], as a UTC-flagged value.
  DateTime _wall(DateTime utc) {
    final l = _toLocal(utc);
    return DateTime.utc(
      l.year,
      l.month,
      l.day,
      l.hour,
      l.minute,
      l.second,
      l.millisecond,
    );
  }

  static DateTime _day(DateTime w) => DateTime.utc(w.year, w.month, w.day);

  static DateTime _addDays(DateTime day, int n) =>
      DateTime.utc(day.year, day.month, day.day + n);

  /// Local midnight for a wall-clock day (DST-aware via [DateTime.new]).
  static DateTime _localOf(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  static List<(DateTime, DateTime)> _bucketRanges(
    StatsPeriod p,
    DateTime start,
    DateTime end,
  ) {
    switch (p) {
      case StatsPeriod.week:
      case StatsPeriod.month:
        return [
          for (var i = 0; i < p.days; i++)
            (_addDays(start, i), _addDays(start, i + 1)),
        ];
      case StatsPeriod.halfYear:
        return [
          for (var i = 0; i < p.days ~/ 7; i++)
            (_addDays(start, i * 7), _addDays(start, i * 7 + 7)),
        ];
      case StatsPeriod.year:
        final out = <(DateTime, DateTime)>[];
        var from = start;
        while (from.isBefore(end)) {
          final next = DateTime.utc(from.year, from.month + 1);
          final to = next.isBefore(end) ? next : end;
          out.add((from, to));
          from = to;
        }
        return out;
    }
  }

  static int _bucketIndex(StatsPeriod p, DateTime start, DateTime local) {
    final day = _day(local).difference(start).inDays;
    return switch (p) {
      StatsPeriod.week || StatsPeriod.month => day,
      StatsPeriod.halfYear => day ~/ 7,
      StatsPeriod.year =>
        (local.year * 12 + local.month) - (start.year * 12 + start.month),
    };
  }

  /// Plays, then minutes (both descending), then name.
  static int _rank(_Acc a, _Acc b, String an, String bn) {
    final byPlays = b.plays.compareTo(a.plays);
    if (byPlays != 0) return byPlays;
    final byHeard = b.heardMs.compareTo(a.heardMs);
    if (byHeard != 0) return byHeard;
    final byName = an.toLowerCase().compareTo(bn.toLowerCase());
    return byName != 0 ? byName : an.compareTo(bn);
  }
}

abstract class _Acc {
  int plays = 0;
  int heardMs = 0;

  void add(int ms, bool counted) {
    if (counted) plays++;
    heardMs += ms;
  }
}

class _SongAcc extends _Acc {
  _SongAcc(this.trackId);

  final String trackId;

  /// Id and title of the most recent listen.
  String latestId = '';
  String title = '';
}

class _ArtistAcc extends _Acc {
  String name = '';

  /// This artist's songs in the period (each with its own totals).
  final songs = <String, _SongAcc>{};

  /// The most-played song, ties broken by minutes.
  _SongAcc mostPlayed() => songs.values.reduce(
    (best, s) =>
        s.plays > best.plays ||
            (s.plays == best.plays && s.heardMs > best.heardMs)
        ? s
        : best,
  );
}
