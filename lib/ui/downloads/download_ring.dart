import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';

/// A playlist card's download progress: a 14 px ring at done / total, a filled
/// check once complete, nothing while the download is off.
class DownloadRing extends ConsumerWidget {
  const DownloadRing({required this.playlistId, super.key});

  static const double size = 14;

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      downloadEnabledPlaylistsProvider.select(
        (a) => a.value?.contains(playlistId) ?? false,
      ),
    );
    // Only downloaded playlists watch their status.
    if (!enabled) return const SizedBox.shrink();
    return _Ring(playlistId: playlistId);
  }
}

class _Ring extends ConsumerWidget {
  const _Ring({required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final counts = ref.watch(
      playlistDownloadProvider(playlistId).select((a) {
        final s = a.value;
        return s == null ? null : (s.done, s.total);
      }),
    );
    final (done, total) = counts ?? (0, 0);
    if (total > 0 && done >= total) {
      return Icon(
        Icons.check_circle,
        size: DownloadRing.size,
        color: colors.accent,
      );
    }
    return SizedBox.square(
      dimension: DownloadRing.size,
      child: CircularProgressIndicator(
        value: total == 0 ? 0 : done / total,
        strokeWidth: 2,
        color: colors.accent,
        backgroundColor: colors.mutedText.withAlpha(80),
      ),
    );
  }
}
