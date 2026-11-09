import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../stats/stats_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/contrast.dart';
import '../shell/go_tab.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';
import '../ytm/ytm_nav.dart';
import '../ytm/ytm_page_parts.dart' show YtmSectionTitle;
import '../ytm/ytm_result_tiles.dart' show YtmTile;
import '../widgets/favorite_star.dart';
import 'stats_chart.dart';

/// Rows shown before Show top 10.
const int _shownTop = 5;

/// The Search tab's branch index (see `router.dart`).
const int _searchTab = 1;

/// The YouTube Music artist page for a top artist, from its most-played
/// song's id: that song (if still in the library) by the song menu's Go to
/// artist rule ([MenuSong.artistId]); null when no page is known. Looked up
/// at tap time.
final statsArtistPageProvider =
    Provider<Future<String?> Function(String trackId)>((ref) {
      final library = ref.watch(libraryRepositoryProvider);
      return (trackId) async {
        final track = await library.trackById(trackId);
        return track == null ? null : MenuSong.track(track).artistId;
      };
    });

/// Listening stats: the period picker, total minutes and the change from
/// the period before, a chart of minutes, then top artists and top songs.
/// An empty period says so instead. While another period loads, the stats
/// shown last stay on screen, dimmed.
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  static const double _maxContentWidth = 720;

  /// The stats last shown, kept until the selected period's arrive.
  PeriodStats? _shown;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(statsPeriodProvider);
    final value = ref.watch(periodStatsProvider(period));
    final bottom = MediaQuery.paddingOf(context).bottom;
    final fresh = value.value;
    if (fresh != null && fresh.period == period) {
      _shown = fresh;
    } else if (value.hasError) {
      _shown = null;
    }
    final stats = _shown;
    final stale = stats != null && stats.period != period;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          // At most a few dozen rows: built at once, so a list's Show top
          // 10 survives scrolling it out of view.
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                _PeriodPicker(
                  selected: period,
                  onSelected: ref.read(statsPeriodProvider.notifier).select,
                ),
                if (stats != null)
                  // A static dim while the new period loads.
                  Opacity(
                    opacity: stale ? 0.5 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _content(stats),
                    ),
                  )
                else if (value.hasError)
                  const _Message("Couldn't load your listening stats"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(PeriodStats stats) {
    if (stats.isEmpty) {
      return const [
        _Message('Nothing played in this period yet', key: Key('stats.empty')),
      ];
    }
    return [
      _Total(stats),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: SizedBox(
          height: 160,
          child: StatsChart(
            key: const Key('stats.chart'),
            buckets: stats.buckets,
          ),
        ),
      ),
      if (stats.topArtists.isNotEmpty)
        _TopList(
          key: ValueKey('artists.${stats.period.name}'),
          title: 'Top artists',
          moreKey: const Key('stats.artists.more'),
          count: stats.topArtists.length,
          row: (i) => _ArtistRow(rank: i, artist: stats.topArtists[i]),
        ),
      if (stats.topSongs.isNotEmpty)
        _TopList(
          key: ValueKey('songs.${stats.period.name}'),
          title: 'Top songs',
          moreKey: const Key('stats.songs.more'),
          count: stats.topSongs.length,
          row: (i) => _SongRow(rank: i, song: stats.topSongs[i]),
        ),
    ];
  }
}

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
    StatsPeriod.month => 'the previous month',
    StatsPeriod.halfYear => 'the previous 6 months',
    StatsPeriod.year => 'the previous 12 months',
  };
  if (pct == 0) return 'Same as $than';
  final sign = pct > 0 ? '+' : '−';
  return '$sign${pct.abs()}% vs $than';
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
      child: Row(
        children: [
          if (context.canPop())
            IconButton(
              tooltip: 'Back',
              color: colors.text,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            )
          else
            const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Your listening',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 7 days · 1 month · 6 months · 12 months, as one segmented row.
class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.selected, required this.onSelected});

  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final accent = ensureAccentContrast(colors.accent, colors.background);
    final radius = BorderRadius.circular(20);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: colors.mutedText.withValues(alpha: 0.4)),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Row(
            children: [
              for (final p in StatsPeriod.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: p == selected,
                    child: Material(
                      color: p == selected ? accent : Colors.transparent,
                      child: InkWell(
                        key: Key('stats.period.${p.name}'),
                        onTap: () => onSelected(p),
                        child: SizedBox(
                          height: 40,
                          child: Center(
                            child: Text(
                              p.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p == selected
                                    ? readableOn(accent)
                                    : colors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The period's minutes, large, and the change from the period before.
class _Total extends StatelessWidget {
  const _Total(this.stats);

  final PeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final change = statsChangeText(stats);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatMinutes(stats.total),
            key: const Key('stats.total'),
            style: TextStyle(
              color: colors.text,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (change != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                change,
                key: const Key('stats.change'),
                style: TextStyle(color: colors.mutedText, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.mutedText, fontSize: 15),
      ),
    );
  }
}

/// A titled top list: the first five rows, and Show top 10 for the rest.
class _TopList extends StatefulWidget {
  const _TopList({
    required this.title,
    required this.moreKey,
    required this.count,
    required this.row,
    super.key,
  });

  final String title;
  final Key moreKey;
  final int count;
  final Widget Function(int index) row;

  @override
  State<_TopList> createState() => _TopListState();
}

class _TopListState extends State<_TopList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final shown = _all ? widget.count : widget.count.clamp(0, _shownTop);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        YtmSectionTitle(widget.title),
        for (var i = 0; i < shown; i++) widget.row(i),
        if (shown < widget.count)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton(
              key: widget.moreKey,
              onPressed: () => setState(() => _all = true),
              child: const Text('Show top 10'),
            ),
          ),
      ],
    );
  }
}

String _plays(int n) => n == 1 ? '1 play' : '$n plays';

/// The rank number and a cover, as one leading block.
class _RankedArt extends StatelessWidget {
  const _RankedArt({required this.rank, required this.art});

  final int rank;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '${rank + 1}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        art,
      ],
    );
  }
}

class _PlayCount extends StatelessWidget {
  const _PlayCount(this.plays);

  final int plays;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Text(
        _plays(plays),
        style: TextStyle(color: colors.mutedText, fontSize: 12),
      ),
    );
  }
}

/// A top artist: opens their YouTube Music page when one is known
/// ([statsArtistPageProvider]), otherwise Search with their name.
class _ArtistRow extends ConsumerWidget {
  const _ArtistRow({required this.rank, required this.artist});

  final int rank;
  final ArtistStat artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return YtmTile(
      rowKey: Key('stats.artist.$rank'),
      art: _RankedArt(
        rank: rank,
        art: Artwork(
          artist.artworkRef,
          size: 48,
          radius: 24,
          seed: artist.name,
        ),
      ),
      title: artist.name,
      subtitle: '',
      onTap: () => _open(context, ref),
      trailing: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: _PlayCount(artist.plays),
      ),
    );
  }

  /// Opens the artist's YouTube Music page when one is known, otherwise
  /// Search for their name.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final shell = StatefulNavigationShell.maybeOf(context);
    final router = GoRouter.of(context);
    final query = ref.read(searchQueryProvider.notifier);
    final pageFor = ref.read(statsArtistPageProvider);
    final trackId = artist.sampleTrackId;
    final page = trackId == null ? null : await pageFor(trackId);
    if (!context.mounted) return;
    if (page != null) {
      context.goYtmArtist(page);
      return;
    }
    query.set(artist.name);
    if (shell != null) {
      goTab(shell.widget, _searchTab);
    } else {
      router.go('/search');
    }
  }
}

/// A top song, with its recorded title and artist. While it is in the
/// library a tap plays it and it has the song menu; once removed it is
/// shown only.
class _SongRow extends ConsumerWidget {
  const _SongRow({required this.rank, required this.song});

  final int rank;
  final SongStat song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(libraryTrackProvider(song.trackId)).value;
    final menu = track == null
        ? null
        : songMenuOpeners(context, ref, MenuSong.track(track));
    return YtmTile(
      rowKey: Key('stats.song.$rank'),
      art: _RankedArt(
        rank: rank,
        art: Artwork(song.artworkRef, size: 48, seed: song.trackId),
      ),
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
          _PlayCount(song.plays),
          if (track != null) ...[
            FavoriteStar(song: MenuSong.track(track)),
            SongMenuButton(
              key: Key('stats.song.menu.$rank'),
              song: MenuSong.track(track),
            ),
          ] else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
