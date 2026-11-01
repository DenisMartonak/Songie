import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/eq_presets.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'settings_page.dart';

/// Settings → Playback: the equalizer preset.
class PlaybackSettingsSection extends ConsumerWidget {
  const PlaybackSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final preset = ref.watch(eqPresetProvider);
    final missing =
        ref.watch(isWindowsProvider) &&
        ref.watch(equalizerProvider).knownAvailable == false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Playback'),
        ListTile(
          key: const Key('settings.equalizer'),
          enabled: !missing,
          leading: const Icon(Icons.equalizer_rounded),
          title: Text('Equalizer', style: TextStyle(color: colors.text)),
          subtitle: Text(
            missing ? 'Not available on Windows yet' : preset.label,
            style: TextStyle(color: colors.mutedText),
          ),
          onTap: () => _pick(context, ref, preset),
        ),
      ],
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    EqPreset current,
  ) async {
    final picked = await showDialog<EqPreset>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Equalizer'),
        children: [
          RadioGroup<EqPreset>(
            groupValue: current,
            onChanged: (p) => Navigator.of(context).pop(p),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in EqPreset.values)
                  RadioListTile<EqPreset>(value: p, title: Text(p.label)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(eqPresetProvider.notifier).select(picked);
    }
  }
}
