import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../friends/friends_service.dart';
import '../../providers.dart';
import '../../room/room_service.dart';
import '../../theme/app_theme.dart';
import '../account/avatar.dart';
import 'right_pane_state.dart';

/// What the desktop right pane shrinks to while closed: a slim strip with
/// the people icon (the room's head count while in one) and a face for each
/// friend, a green dot on those listening. One target: a click opens the
/// pane on Friends.
class RightPaneStrip extends ConsumerWidget {
  const RightPaneStrip({super.key});

  static const double width = 40;
  static const double _face = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final signedIn = ref.watch(accountStateProvider).value is SignedIn;
    final state = ref.watch(friendsStateProvider).value ?? FriendsState.empty;
    final now = ref.read(nowProvider)();
    final count = switch (ref.watch(roomStatusProvider).value) {
      RoomHosting(:final people) ||
      RoomGuesting(:final people) => people.length,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(colors.radius + 4),
          child: ColoredBox(
            color: colors.background,
            // Like the rest of the chrome, it must not take focus, or Space
            // would re-press it.
            child: ExcludeFocus(
              child: Tooltip(
                message: 'Show friends',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: const Key('rightPane.strip'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref.read(rightPaneProvider).showFriends(),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Badge(
                            isLabelVisible: count != null,
                            label: Text('${count ?? 0}'),
                            backgroundColor: colors.accent,
                            textColor: colors.background,
                            child: Icon(
                              Icons.group_rounded,
                              size: 20,
                              color: count != null
                                  ? colors.accent
                                  : colors.mutedText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (signedIn)
                            for (final u in state.friends)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Tooltip(
                                  message: u.username,
                                  child: SizedBox(
                                    key: Key('rightPane.strip.${u.id}'),
                                    width: _face,
                                    height: _face,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        PersonAvatar(
                                          name: u.username,
                                          url: u.avatarUrl,
                                          size: _face,
                                        ),
                                        if (state.listening(u.id, now))
                                          Positioned(
                                            right: -2,
                                            bottom: -2,
                                            child: Container(
                                              key: const Key(
                                                'rightPane.strip.dot',
                                              ),
                                              width: 9,
                                              height: 9,
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: colors.background,
                                                  width: 1.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
