import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../innertube/ytm_models.dart';
import '../../providers.dart';
import '../../stats/stats_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/contrast.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../motion/pressable.dart';
import '../stats/stats_chart.dart';
import '../widgets/artwork.dart';
import '../widgets/favorite_star.dart';
import '../widgets/song_menu.dart';
import '../ytm/artist_lookup.dart';

/// Rows shown before Show more.
const int _shownTop = 5;

/// "+12% vs the previous 7 days", "−8% vs …" (a true minus), or "Same as
/// the previous 7 days" when it rounds to 0 %. Null without a previous
/// period.
String? statsChangeText(PeriodStats stats) {
  final previous = stats.previousTotal;
  if (previous == null || previous == Duration.zero) return null;
  final pct =
      ((stats.total.inMilliseconds - previous.inMilliseconds) *
              100 /
              previous.inMilliseconds)
          .round();
  final than = switch (stats.period) {
    StatsPeriod.week => 'the previous 7 days',
    StatsPeriod.month => 'the previous 30 days',
    StatsPeriod.halfYear => 'the previous 6 months',
    StatsPeriod.year => 'the previous 12 months',
  };
  if (pct == 0) return 'Same as $than';
  final sign = pct > 0 ? '+' : '−';
  return '$sign${pct.abs()}% vs $than';
}

/// The picker's short label.
String _short(StatsPeriod p) => switch (p) {
  StatsPeriod.week => '7d',
  StatsPeriod.month => '30d',
  StatsPeriod.halfYear => '6m',
  StatsPeriod.year => '12m',
};

/// The span in "the last 30 days".
String _span(StatsPeriod p) => switch (p) {
  StatsPeriod.week => '7 days',
  StatsPeriod.month => '30 days',
  StatsPeriod.halfYear => '6 months',
  StatsPeriod.year => '12 months',
};

/// "2,418" from 2,418 minutes.
String _minutesNumber(Duration d) {
  final s = formatMinutes(d);
  return s.substring(0, s.length - ' min'.length);
}

String _plays(int n) => n == 1 ? '1 play' : '$n plays';

/// A profile's stats from the period picker down: the picker (hidden
/// without [onPeriod], as for an old friend's summary), an optional muted
/// [note], the period's minutes with the change and a chart, then the top
/// 10 artists and songs with pictures. [wide] is the PC layout: minutes
/// beside the chart, the lists side by side. [mine] makes the rows your
/// own (library songs play and keep their menu and star, cached artist
/// photos); otherwise a friend's (YouTube songs play through YouTube).
///
/// A summary without totals (an old friend's) shows only the names.
class ProfileStats extends ConsumerWidget {
  const ProfileStats({
    required this.stats,
    required this.period,
    required this.onPeriod,
    required this.wide,
    required this.mine,
    this.note,
    this.noteKey,
    super.key,
  });

  final PeriodStats? stats;
  final StatsPeriod period;
  final ValueChanged<StatsPeriod>? onPeriod;
  final bool wide;
  final bool mine;
  final String? note;

  /// The [note]'s key.
  final Key? noteKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stats;
    final pick = onPeriod;
    final picker = pick == null
        ? null
        : _PeriodPicker(selected: period, onSelected: pick, wide: wide);
    final noteLine = note == null ? null : _Note(note!, textKey: noteKey);
    final side = wide ? 24.0 : 16.0;

    if (s == null) {
      // Yours are still loading; a friend's summary lacks this period.
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: side),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [?picker, ?noteLine, if (!mine) const _Empty()],
        ),
      );
    }

    final numbers = s.total > Duration.zero;
    final lists = s.topArtists.isNotEmpty || s.topSongs.isNotEmpty;
    final artists = s.topArtists.isEmpty
        ? null
        : _TopList(
            key: ValueKey('artists.${s.period.name}'),
            title: 'Top 10 artists',
            moreKey: const Key('profile.artists.more'),
            count: s.topArtists.length,
            wide: wide,
            row: (i) => _ArtistRow(
              rank: i,
              artist: s.topArtists[i],
              mine: mine,
              wide: wide,
              numbers: numbers,
            ),
          );
    final songs = s.topSongs.isEmpty
        ? null
        : _TopList(
            key: ValueKey('songs.${s.period.name}'),
            title: 'Top 10 songs',
            moreKey: const Key('profile.songs.more'),
            count: s.topSongs.length,
            wide: wide,
            row: (i) => _SongRow(
              rank: i,
              song: s.topSongs[i],
              mine: mine,
              wide: wide,
              numbers: numbers,
            ),
          );

    final Widget top;
    if (!numbers) {
      top = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?picker, ?noteLine, if (!lists) const _Empty()],
      );
    } else if (wide) {
      top = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?picker,
                ?noteLine,
                const SizedBox(height: 24),
                _WideTotal(s),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 240,
              child: StatsChart(
                key: const Key('profile.chart'),
                buckets: s.buckets,
              ),
            ),
          ),
        ],
      );
    } else {
      top = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?picker,
          ?noteLine,
          const SizedBox(height: 12),
          _TotalCard(s),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          if (lists && wide)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: artists ?? const SizedBox.shrink()),
                  const SizedBox(width: 48),
                  Expanded(child: songs ?? const SizedBox.shrink()),
                ],
              ),
            )
          else if (lists) ...[
            if (artists != null)
              Padding(padding: const EdgeInsets.only(top: 28), child: artists),
            if (songs != null)
              Padding(padding: const EdgeInsets.only(top: 28), child: songs),
          ],
        ],
      ),
    );
  }
}

/// "Nothing played in this period yet".
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 24),
    child: _Muted(
      'Nothing played in this period yet',
      key: Key('profile.empty'),
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: colors.mutedText, fontSize: 14),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.textKey});

  final String text;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        key: textKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.mutedText, fontSize: 12),
      ),
    );
  }
}

/// 7d · 30d · 6m · 12m: a segmented row on the phone, chips when wide.
class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({
    required this.selected,
    required this.onSelected,
    required this.wide,
  });

  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onSelected;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;

    Widget option(StatsPeriod p, {required double width}) {
      final on = p == selected;
      final radius = BorderRadius.circular(20);
      return Semantics(
        button: true,
        selected: on,
        label: 'Last ${_span(p)}',
        excludeSemantics: true,
        child: Material(
          color: on ? colors.text : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: wide && !on
                ? BorderSide(color: colors.mutedText.withValues(alpha: 0.4))
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('profile.period.${p.name}'),
            onTap: () => onSelected(p),
            child: SizedBox(
              height: 40,
              width: width,
              child: Center(
                child: Text(
                  _short(p),
                  maxLines: 1,
                  style: TextStyle(
                    color: on ? readableOn(colors.text) : colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (wide) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final p in StatsPeriod.values) option(p, width: 64)],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final p in StatsPeriod.values)
              Expanded(child: option(p, width: double.infinity)),
          ],
        ),
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change(this.stats);

  final PeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final change = statsChangeText(stats);
    if (change == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        change,
        key: const Key('profile.change'),
        style: TextStyle(color: colors.mutedText, fontSize: 13),
      ),
    );
  }
}

/// The phone's card: "Minutes listened", the number, the change, the chart.
class _TotalCard extends StatelessWidget {
  const _TotalCard(this.stats);

  final PeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Minutes listened',
              style: TextStyle(color: colors.mutedText, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _minutesNumber(stats.total),
                      key: const Key('profile.total'),
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'min',
                  style: TextStyle(color: colors.mutedText, fontSize: 16),
                ),
              ],
            ),
            _Change(stats),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: StatsChart(
                key: const Key('profile.chart'),
                buckets: stats.buckets,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The PC's huge number with "minutes listened in the last 30 days".
class _WideTotal extends StatelessWidget {
  const _WideTotal(this.stats);

  final PeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _minutesNumber(stats.total),
            key: const Key('profile.total'),
            style: TextStyle(
              color: colors.text,
              fontSize: 96,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'minutes listened in the last ${_span(stats.period)}',
          style: TextStyle(color: colors.mutedText, fontSize: 18),
        ),
        _Change(stats),
      ],
    );
  }
}

/// A list's heading, five rows, then the rest after Show more (a
/// full-width outlined button under the list on the phone, a text button
/// in the heading when wide).
class _TopList extends StatefulWidget {
  const _TopList({
    required this.title,
    required this.moreKey,
    required this.count,
    required this.wide,
    required this.row,
    super.key,
  });

  final String title;
  final Key moreKey;
  final int count;
  final bool wide;
  final Widget Function(int i) row;

  @override
  State<_TopList> createState() => _TopListState();
}

class _TopListState extends State<_TopList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final shown = _all ? widget.count : widget.count.clamp(0, _shownTop);
    final more = shown < widget.count;
    void showAll() => setState(() => _all = true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (more && widget.wide)
                TextButton(
                  key: widget.moreKey,
                  onPressed: showAll,
                  style: TextButton.styleFrom(foregroundColor: colors.text),
                  child: const Text('Show more'),
                ),
            ],
          ),
        ),
        for (var i = 0; i < shown; i++) widget.row(i),
        if (more && !widget.wide)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              key: widget.moreKey,
              onPressed: showAll,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.text,
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(
                  color: colors.mutedText.withValues(alpha: 0.4),
                ),
              ),
              child: const Text('Show more'),
            ),
          ),
      ],
    );
  }
}

/// A picture from [url] (a photo or YouTube cover), else the local cover
/// [artworkRef], else the seeded placeholder; the placeholder also shows
/// while the image loads and when it fails.
class ProfileArt extends StatelessWidget {
  const ProfileArt({
    this.url,
    this.artworkRef,
    required this.seed,
    required this.size,
    this.radius,
    super.key,
  });

  final String? url;
  final String? artworkRef;
  final String seed;
  final double size;

  /// Corner radius; defaults to the theme's.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final link = url;
    final local = Artwork(artworkRef, size: size, radius: radius, seed: seed);
    if (link == null) return local;
    final placeholder = Artwork(null, size: size, radius: radius, seed: seed);
    final corner =
        radius ?? Theme.of(context).extension<SongiesColors>()!.radius;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(corner),
        child: Image.network(
          link,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          frameBuilder: (_, child, frame, sync) =>
              frame == null && !sync ? placeholder : child,
          errorBuilder: (_, _, _) => placeholder,
        ),
      ),
    );
  }
}

/// One ranked row: the rank on the left on the phone, a large muted number
/// on the right when wide.
class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.rowKey,
    required this.rank,
    required this.wide,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.onLongPress,
    this.onSecondaryTapUp,
  });

  final Key rowKey;
  final int rank;
  final bool wide;
  final Widget art;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final sub = subtitle;
    return Pressable(
      key: rowKey,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapUp: onSecondaryTapUp,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            if (!wide) ...[
              SizedBox(
                width: 24,
                child: Text(
                  '${rank + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.mutedText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            art,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.mutedText, fontSize: 13),
                    ),
                ],
              ),
            ),
            ?trailing,
            if (wide)
              SizedBox(
                width: 48,
                child: Text(
                  '${rank + 1}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: colors.mutedText.withValues(alpha: 0.6),
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A top artist: round photo, name, minutes. A tap opens their YouTube
/// Music page when known (for your own, also found through their
/// most-played song), else Search with their name.
class _ArtistRow extends ConsumerWidget {
  const _ArtistRow({
    required this.rank,
    required this.artist,
    required this.mine,
    required this.wide,
    required this.numbers,
  });

  final int rank;
  final ArtistStat artist;
  final bool mine;
  final bool wide;
  final bool numbers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var photoUrl = artist.photoUrl;
    var browseId = artist.browseId;
    if (mine) {
      ref.watch(artistPhotosChangesProvider);
      final cached = ref.watch(artistPhotosProvider).of(artist.name);
      photoUrl ??= cached?.photoUrl;
      browseId ??= cached?.browseId;
    }
    return _RankedRow(
      rowKey: Key('profile.artist.$rank'),
      rank: rank,
      wide: wide,
      art: ProfileArt(
        url: photoUrl,
        artworkRef: mine ? artist.artworkRef : null,
        seed: artist.name,
        size: 56,
        radius: 28,
      ),
      title: artist.name,
      subtitle: numbers ? formatMinutes(artist.heard) : null,
      onTap: () => _open(context, ref, browseId),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String? browseId,
  ) async {
    final trackId = artist.sampleTrackId;
    final track = !mine || browseId != null || trackId == null
        ? null
        : await ref.read(libraryRepositoryProvider).trackById(trackId);
    if (!context.mounted) return;
    await openArtist(
      context,
      ref,
      browseId: browseId,
      track: track,
      name: artist.name,
    );
  }
}

/// A top song: square cover, title, artist, plays. Your own plays from the
/// library and keeps its menu and star while there; a friend's plays
/// through YouTube when it is a YouTube song, else it is shown only.
class _SongRow extends ConsumerWidget {
  const _SongRow({
    required this.rank,
    required this.song,
    required this.mine,
    required this.wide,
    required this.numbers,
  });

  final int rank;
  final SongStat song;
  final bool mine;
  final bool wide;
  final bool numbers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final plays = numbers
        ? Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              _plays(song.plays),
              style: TextStyle(color: colors.mutedText, fontSize: 13),
            ),
          )
        : null;
    final art = ProfileArt(
      url: mine && song.artworkRef != null ? null : song.coverUrl,
      artworkRef: mine ? song.artworkRef : null,
      seed: song.trackId,
      size: 56,
    );

    if (!mine) {
      final videoId = song.videoId;
      return _RankedRow(
        rowKey: Key('profile.song.$rank'),
        rank: rank,
        wide: wide,
        art: art,
        title: song.title,
        subtitle: song.displayArtist,
        onTap: videoId == null
            ? null
            : () => _playFriend(context, ref, videoId),
        trailing: plays,
      );
    }

    final track = ref.watch(libraryTrackProvider(song.trackId)).value;
    final menu = track == null
        ? null
        : songMenuOpeners(context, ref, MenuSong.track(track));
    return _RankedRow(
      rowKey: Key('profile.song.$rank'),
      rank: rank,
      wide: wide,
      art: art,
      title: song.title,
      subtitle: song.displayArtist,
      onTap: track == null
          ? null
          : () => ref.read(playerInputsProvider).playQueue([track]),
      onLongPress: menu?.onLongPress,
      onSecondaryTapUp: menu?.onSecondaryTapUp,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?plays,
          if (track != null) ...[
            FavoriteStar(song: MenuSong.track(track)),
            SongMenuButton(
              key: Key('profile.song.menu.$rank'),
              song: MenuSong.track(track),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _playFriend(
    BuildContext context,
    WidgetRef ref,
    String videoId,
  ) async {
    final islands = Islands.of(context);
    final player = ref.read(playerInputsProvider);
    try {
      final tracks = await ref.read(ytTrackStoreProvider).upsertAll([
        YtmSong(
          videoId: videoId,
          title: song.title,
          artists: [YtmArtistRef(name: song.displayArtist)],
          thumbnailUrl: song.coverUrl,
        ),
      ]);
      if (tracks.isEmpty) throw StateError('the song was not stored');
      await player.playQueue(tracks);
    } catch (e) {
      AppLog.w("Couldn't play a friend's song $videoId: $e");
      islands.show("Couldn't play this song", kind: IslandKind.failure);
    }
  }
}
