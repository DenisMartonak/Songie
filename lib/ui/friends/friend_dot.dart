import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';

/// Whether friend requests are waiting for the signed-in user.
final friendRequestsWaitingProvider = Provider<bool>(
  (ref) => ref.watch(
    friendsStateProvider.select((s) => s.value?.incoming.isNotEmpty ?? false),
  ),
);

/// A small accent dot while friend requests are waiting; nothing otherwise.
class FriendDot extends ConsumerWidget {
  const FriendDot({super.key});

  static const double size = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(friendRequestsWaitingProvider)) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Semantics(
      label: 'Friend requests waiting',
      child: Container(
        key: const Key('friends.dot'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.accent,
          shape: BoxShape.circle,
          border: Border.all(color: colors.background, width: 1.5),
        ),
      ),
    );
  }
}
