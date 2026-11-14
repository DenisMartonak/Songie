import 'package:flutter/material.dart';

import 'crash_reports_settings.dart';
import 'discord_settings.dart';
import 'downloads_settings.dart';
import 'playback_settings.dart';
import 'privacy_settings.dart';
import 'settings_page.dart';
import 'youtube_settings.dart';

/// The groups Settings is split into, in the order they're listed. Each has
/// its own page at `/settings/<slug>`.
enum SettingsCategory {
  library('Library', 'Music folders, storage', Icons.library_music_outlined),
  playback('Playback', 'Equalizer, downloads', Icons.play_circle_outline),
  youtube(
    'YouTube',
    'Sign-in, yt-dlp, recommendations',
    Icons.smart_display_outlined,
  ),
  appearance('Appearance', 'Themes, animations', Icons.palette_outlined),
  privacy('Privacy', 'Sharing, crash reports', Icons.lock_outline_rounded),
  discord('Discord', "Show what you're playing", Icons.headset_mic_outlined),
  about(
    'About',
    'Version, updates, bug reports, log',
    Icons.info_outline_rounded,
  );

  const SettingsCategory(this.title, this.line, this.icon);

  final String title;

  /// What's inside, under the title in the list.
  final String line;
  final IconData icon;

  /// The part of the address after `/settings/`.
  String get slug => name;

  /// The sections on this category's page, top to bottom.
  List<Widget> get sections => switch (this) {
    library => const [FoldersSection(), StorageSection()],
    playback => const [PlaybackSettingsSection(), DownloadsSettingsSection()],
    youtube => const [YouTubeSettingsSection()],
    appearance => const [AppearanceSection()],
    privacy => const [PrivacySettingsSection(), CrashReportsSettingsSection()],
    discord => const [DiscordSettingsSection()],
    about => const [AboutSection(), LogsSection()],
  };
}

/// The category at [slug]; Library when there's none or it's unknown.
SettingsCategory settingsCategoryFromSlug(String? slug) =>
    SettingsCategory.values.where((c) => c.slug == slug).firstOrNull ??
    SettingsCategory.library;

/// The categories to list: Discord only where Discord status works.
List<SettingsCategory> visibleSettingsCategories({
  required bool discordSupported,
}) => [
  for (final c in SettingsCategory.values)
    if (discordSupported || c != SettingsCategory.discord) c,
];
