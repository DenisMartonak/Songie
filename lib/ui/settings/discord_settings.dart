import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';
import '../../discord/discord_presence.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'settings_page.dart' show SettingsSectionTitle;

/// Discord status needs the Discord app on the same computer: desktop only.
final discordSupportedProvider = Provider<bool>(
  (ref) => Platform.isWindows || Platform.isLinux,
);

/// The Discord application id; empty when this build has none.
final discordClientIdProvider = Provider<String>((ref) => kDiscordClientId);

final discordPresenceEnabledProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(kDiscordPresence, fallback: false),
);

/// Settings → Discord: one switch to show the playing song on Discord.
/// Hidden where Discord status can't work (Android).
class DiscordSettingsSection extends ConsumerWidget {
  const DiscordSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(discordSupportedProvider)) return const SizedBox.shrink();
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final ready = ref.watch(discordClientIdProvider).isNotEmpty;
    final on = ref.watch(discordPresenceEnabledProvider).value ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Discord'),
        SwitchListTile(
          key: const Key('settings.discord'),
          title: Text(
            'Show what I\'m listening to',
            style: TextStyle(color: colors.text),
          ),
          subtitle: Text(
            ready
                ? 'The song and artist show on your Discord profile while '
                      'the Discord app is open on this computer'
                : 'Not set up in this version of Songies yet',
            style: TextStyle(color: colors.mutedText, fontSize: 12),
          ),
          value: ready && on,
          onChanged: ready
              ? (v) => ref
                    .read(settingsRepositoryProvider)
                    .setBool(kDiscordPresence, v)
              : null,
        ),
      ],
    );
  }
}
