import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../downloads/download_service.dart';
import '../downloads/download_status_line.dart'
    show canResumeDownloads, resumeDownloads;
import 'settings_page.dart';
import 'storage_usage.dart';

/// Settings → Downloads: Wi-Fi only, the space downloads take (in all and
/// per playlist) and Pause / Resume.
class DownloadsSettingsSection extends ConsumerWidget {
  const DownloadsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final isAndroid = ref.watch(isAndroidProvider);
    final wifiOnly =
        ref.watch(wifiOnlySettingProvider).value ??
        wifiOnlyDefault(isAndroid: isAndroid);
    final total = ref.watch(downloadTotalBytesProvider).value;
    final perPlaylist =
        ref.watch(downloadBytesPerPlaylistProvider).value ?? const [];
    final names = {
      for (final p in ref.watch(playlistsProvider).value ?? const [])
        p.id: p.name,
    };
    // Selected, so progress ticks don't rebuild the section.
    final (paused, canResume) = ref.watch(
      downloadSnapshotProvider.select((a) {
        final s = a.value ?? const DownloadSnapshot();
        return (s.userPaused, canResumeDownloads(s));
      }),
    );

    Widget line(String text, {double size = 14, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color ?? colors.text, fontSize: size),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Downloads'),
        SwitchListTile(
          title: Text('Wi-Fi only', style: TextStyle(color: colors.text)),
          value: wifiOnly,
          onChanged: (v) =>
              ref.read(settingsRepositoryProvider).setBool(kWifiOnly, v),
        ),
        line('Downloaded songs · ${total == null ? '…' : formatBytes(total)}'),
        for (final (id, bytes) in perPlaylist)
          if (names[id] case final name?)
            line(
              '$name · ${formatBytes(bytes)}',
              size: 12,
              color: colors.mutedText,
            ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            children: [
              if (!paused)
                TextButton.icon(
                  key: const Key('settings.downloads.pause'),
                  onPressed: () =>
                      ref.read(downloadServiceProvider).pauseByUser(),
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('Pause downloads'),
                ),
              if (canResume)
                TextButton.icon(
                  key: const Key('settings.downloads.resume'),
                  onPressed: () => unawaited(
                    resumeDownloads(ref.read(downloadServiceProvider)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Resume downloads'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
