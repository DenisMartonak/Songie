import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'settings_page.dart' show SettingsSectionTitle;

final crashReportsEnabledProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(kCrashReports, fallback: true),
);

/// Settings → Crash reports: one switch for anonymous crash reports.
class CrashReportsSettingsSection extends ConsumerWidget {
  const CrashReportsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final on = ref.watch(crashReportsEnabledProvider).value ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Crash reports'),
        SwitchListTile(
          key: const Key('settings.crashReports'),
          title: Text(
            'Send crash reports',
            style: TextStyle(color: colors.text),
          ),
          subtitle: Text(
            'Anonymous: no songs, names or files.',
            style: TextStyle(color: colors.mutedText, fontSize: 12),
          ),
          value: on,
          onChanged: (v) =>
              ref.read(settingsRepositoryProvider).setBool(kCrashReports, v),
        ),
      ],
    );
  }
}
