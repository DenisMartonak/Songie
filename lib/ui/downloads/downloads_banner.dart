import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../settings/youtube_settings.dart' show updateYtDlp;
import '../widgets/page_snack_bar.dart';

/// Whether the user dismissed the "Downloads failing" banner; a new failure
/// shows it again.
class DownloadsBannerDismissed extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(downloadSnapshotProvider, (prev, next) {
      final s = next.value;
      if (s == null || !s.extractorFailing) return;
      final before = prev?.value;
      if (before == null ||
          !before.extractorFailing ||
          s.failedThisRun > before.failedThisRun) {
        state = false;
      }
    });
    return false;
  }

  void dismiss() => state = true;
}

final downloadsBannerDismissedProvider =
    NotifierProvider<DownloadsBannerDismissed, bool>(
      DownloadsBannerDismissed.new,
    );

/// Whether [DownloadsBanner] shows.
final downloadsBannerVisibleProvider = Provider<bool>(
  (ref) =>
      ref.watch(
        downloadSnapshotProvider.select(
          (a) => a.value?.extractorFailing ?? false,
        ),
      ) &&
      !ref.watch(downloadsBannerDismissedProvider),
);

/// "Downloads failing — update yt-dlp?", while downloads fail in a way that
/// suggests an outdated yt-dlp. Update runs the same update as Settings.
class DownloadsBanner extends ConsumerStatefulWidget {
  const DownloadsBanner({super.key});

  static const double height = 56;

  @override
  ConsumerState<DownloadsBanner> createState() => _DownloadsBannerState();
}

class _DownloadsBannerState extends ConsumerState<DownloadsBanner> {
  bool _updating = false;

  Future<void> _update() async {
    if (_updating) return;
    final dismissal = ref.read(downloadsBannerDismissedProvider.notifier);
    setState(() => _updating = true);
    try {
      final ok = await updateYtDlp(
        ref,
        PageSnackBars.of(context),
        mounted: () => mounted,
      );
      if (ok) dismissal.dismiss();
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(downloadsBannerVisibleProvider)) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Material(
      color: Color.alphaBlend(
        Theme.of(context).colorScheme.error.withAlpha(50),
        colors.background,
      ),
      child: SizedBox(
        height: DownloadsBanner.height,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: colors.text),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Downloads failing — update yt-dlp?',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.text, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: _updating ? null : _update,
                child: const Text('Update'),
              ),
              TextButton(
                onPressed: () => ref
                    .read(downloadsBannerDismissedProvider.notifier)
                    .dismiss(),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
