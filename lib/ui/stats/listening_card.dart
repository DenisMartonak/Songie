import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../stats/stats_models.dart';
import '../../theme/app_theme.dart';
import '../motion/pressable.dart';
import 'stats_chart.dart';

/// Home's "Your listening" card: the last 7 days' minutes, a tiny 7-bar chart
/// and the most played artist. Tapping it opens the stats page on 7 days.
/// With no listening it says so, at the same compact height.
class ListeningCard extends ConsumerWidget {
  const ListeningCard({super.key});

  /// Compact: Home's playlists must stay in the first viewport on a phone.
  static const double height = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    // Keeps showing the last stats while a refreshed value loads.
    final stats = ref.watch(periodStatsProvider(StatsPeriod.week)).value;
    final top = stats?.topArtists.firstOrNull;
    final empty = stats?.isEmpty ?? true;

    final label = StringBuffer('Your listening: ');
    if (stats == null || empty) {
      label.write('your listening stats will show up here');
    } else {
      label.write('${formatMinutes(stats.total)} in the last 7 days');
      if (top != null) label.write(', most played ${top.name}');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Semantics(
        button: true,
        label: label.toString(),
        excludeSemantics: true,
        child: Material(
          key: const Key('home.listening'),
          color: colors.text.withAlpha(23),
          borderRadius: BorderRadius.circular(colors.radius),
          clipBehavior: Clip.antiAlias,
          child: Pressable(
            onTap: () {
              ref.read(statsPeriodProvider.notifier).select(StatsPeriod.week);
              context.push('/home/stats');
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Your listening',
                            style: TextStyle(
                              color: colors.mutedText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (stats != null && !empty) ...[
                            Text(
                              formatMinutes(stats.total),
                              key: const Key('home.listening.minutes'),
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (top != null)
                              Text(
                                'Most played: ${top.name} · '
                                '${top.plays == 1 ? '1 play' : '${top.plays} plays'}',
                                key: const Key('home.listening.top'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.mutedText,
                                  fontSize: 12.5,
                                ),
                              ),
                          ] else if (stats != null)
                            Text(
                              'Your listening stats will show up here',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (stats != null && !empty) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 112,
                        height: StatsChart.compactHeight,
                        child: ExcludeSemantics(
                          child: StatsChart(
                            buckets: stats.buckets,
                            compact: true,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
