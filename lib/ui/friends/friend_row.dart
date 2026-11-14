import 'package:flutter/material.dart';

import '../../friends/activity_backend.dart';
import '../../friends/friends_backend.dart' hide FriendRow;
import '../../theme/app_theme.dart';
import '../account/avatar.dart' show PersonAvatar;

/// A person in a friends list: avatar, name, what they play now, actions.
class FriendRow extends StatelessWidget {
  const FriendRow({
    required this.user,
    this.actions = const [],
    this.listening,
    this.onTap,
    this.avatarSize = 44,
    this.chevron = true,
    super.key,
  });

  final FriendUser user;

  /// What they play now, shown under their name.
  final NowPlaying? listening;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final double avatarSize;

  /// Shows the chevron when the row is tappable.
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            PersonAvatar(
              name: user.username,
              url: user.avatarUrl,
              size: avatarSize,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (listening case final song?)
                    Text(
                      '♪ ${song.title} · ${song.artist}',
                      key: Key('friends.listening.${user.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.accent, fontSize: 12),
                    ),
                ],
              ),
            ),
            ...actions,
            if (onTap != null && chevron)
              Icon(Icons.chevron_right_rounded, color: colors.mutedText),
          ],
        ),
      ),
    );
  }
}
