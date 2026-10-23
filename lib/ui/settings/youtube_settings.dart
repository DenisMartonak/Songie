import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result.dart';
import '../../data/settings_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../youtube/yt_models.dart';
import '../widgets/page_snack_bar.dart';
import 'settings_page.dart';

/// Settings → YouTube: the yt-dlp version with Install / Update, Wi-Fi only
/// streaming and (Linux) the system yt-dlp switch.
class YouTubeSettingsSection extends ConsumerStatefulWidget {
  const YouTubeSettingsSection({super.key});

  @override
  ConsumerState<YouTubeSettingsSection> createState() =>
      _YouTubeSettingsSectionState();
}

class _YouTubeSettingsSectionState
    extends ConsumerState<YouTubeSettingsSection> {
  bool _updating = false;

  Future<void> _update() async {
    if (_updating) return;
    final snacks = PageSnackBars.of(context);
    final runner = ref.read(ytDlpRunnerProvider);
    setState(() => _updating = true);
    try {
      final result = await runner.update();
      if (!mounted) return;
      switch (result) {
        case Ok():
          ref.invalidate(ytDlpVersionProvider);
          final version = await ref.read(ytDlpVersionProvider.future);
          snacks.show(
            content: Text(
              version == null ? 'yt-dlp updated' : 'yt-dlp updated to $version',
            ),
          );
        case Err(:final failure):
          snacks.show(content: Text(ytErrorUserMessage(failure)));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final isAndroid = ref.watch(isAndroidProvider);
    final isLinux = ref.watch(isLinuxProvider);
    final version = ref.watch(ytDlpVersionProvider);
    final installed = version.value;
    final install = !isAndroid && version.hasValue && installed == null;
    final wifiOnly =
        ref.watch(wifiOnlySettingProvider).value ??
        wifiOnlyDefault(isAndroid: isAndroid);
    final useSystem = ref.watch(useSystemYtDlpProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('YouTube'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            version.isLoading
                ? 'yt-dlp version: …'
                : 'yt-dlp version: ${installed ?? 'not installed'}',
            style: TextStyle(color: colors.text),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            key: const Key('settings.ytdlpUpdate'),
            onPressed: _updating || version.isLoading ? null : _update,
            icon: _updating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(install ? Icons.download_rounded : Icons.update_rounded),
            label: Text(install ? 'Install yt-dlp' : 'Update yt-dlp'),
          ),
        ),
        SwitchListTile(
          title: Text(
            'Wi-Fi only streaming',
            style: TextStyle(color: colors.text),
          ),
          value: wifiOnly,
          onChanged: (v) =>
              ref.read(settingsRepositoryProvider).setBool(kWifiOnly, v),
        ),
        if (isLinux)
          SwitchListTile(
            title: Text(
              'Use system yt-dlp',
              style: TextStyle(color: colors.text),
            ),
            subtitle: Text(
              'Takes effect after restart',
              style: TextStyle(color: colors.mutedText, fontSize: 12),
            ),
            value: useSystem,
            onChanged: (v) => ref
                .read(settingsRepositoryProvider)
                .setBool(kYtdlpUseSystem, v),
          ),
      ],
    );
  }
}
