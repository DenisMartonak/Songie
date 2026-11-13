import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../friends/activity_backend.dart';
import '../../friends/friends_backend.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import 'settings_page.dart';

/// Settings → Privacy: whether friends see what you're listening to and
/// your top 10. Kept with the account on the server, so every device
/// agrees; shown once the server says.
class PrivacySettingsSection extends ConsumerStatefulWidget {
  const PrivacySettingsSection({super.key});

  @override
  ConsumerState<PrivacySettingsSection> createState() =>
      _PrivacySettingsSectionState();
}

class _PrivacySettingsSectionState
    extends ConsumerState<PrivacySettingsSection> {
  Sharing? _sharing;
  bool _busy = false;
  String? _loadedFor;

  Future<void> _load(String userId) async {
    _loadedFor = userId;
    try {
      final s = await ref.read(activityBackendProvider).mySharing();
      if (mounted && _loadedFor == userId) setState(() => _sharing = s);
    } on FriendsException {
      // Unknown: the switches stay hidden until it loads.
    }
  }

  /// Saves one switch ([listening] or [top]), never the other's value as
  /// this screen last saw it.
  Future<void> _set({bool? listening, bool? top}) async {
    final before = _sharing;
    if (before == null) return;
    final islands = Islands.of(context);
    setState(() {
      _sharing = Sharing(
        listening: listening ?? before.listening,
        top: top ?? before.top,
      );
      _busy = true;
    });
    try {
      await ref
          .read(activityPublisherProvider)
          .setSharing(listening: listening, top: top);
    } catch (e) {
      islands.show(
        e is FriendsException && e.error == FriendsError.offline
            ? "You're offline"
            : "Couldn't save that",
        kind: IslandKind.failure,
      );
      if (mounted) setState(() => _sharing = before);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(accountStateProvider).value;
    if (state is! SignedIn) {
      _loadedFor = null;
      _sharing = null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionTitle('Privacy'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Log in to share with friends',
              style: TextStyle(color: colors.mutedText),
            ),
          ),
        ],
      );
    }
    if (_loadedFor != state.profile.id) {
      _sharing = null;
      _load(state.profile.id);
    }
    final sharing = _sharing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Privacy'),
        if (sharing != null) ...[
          SwitchListTile(
            key: const Key('privacy.listening'),
            value: sharing.listening,
            onChanged: _busy ? null : (v) => _set(listening: v),
            title: Text(
              "Share what I'm listening to",
              style: TextStyle(color: colors.text),
            ),
            subtitle: Text(
              'Friends see the song you play, and can join your room',
              style: TextStyle(color: colors.mutedText),
            ),
          ),
          SwitchListTile(
            key: const Key('privacy.top'),
            value: sharing.top,
            onChanged: _busy ? null : (v) => _set(top: v),
            title: Text(
              'Share my top 10 with friends',
              style: TextStyle(color: colors.text),
            ),
            subtitle: Text(
              'Your top artists and songs of the last 30 days, no minutes',
              style: TextStyle(color: colors.mutedText),
            ),
          ),
        ],
      ],
    );
  }
}
