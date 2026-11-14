import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../profile/profile_view.dart';
import 'avatar.dart';
import 'inline_username.dart';
import 'picture_viewer.dart';

/// Edit profile: your picture (a tap opens it large with Change and
/// Remove), your username (a tap edits it) and your email. A bottom sheet
/// on the phone, a dialog on wider windows.
Future<void> showEditProfile(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= ProfileView.wideBreakpoint;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: const _EditProfile(),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      // Above the keyboard while the username is typed.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: const _EditProfile(),
    ),
  );
}

class _EditProfile extends ConsumerWidget {
  const _EditProfile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(accountStateProvider).value;
    final profile = state is SignedIn ? state.profile : null;
    return SingleChildScrollView(
      key: const Key('profile.editSheet'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Edit profile',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                key: const Key('profile.editDone'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (profile != null)
            Row(
              children: [
                Tooltip(
                  message: 'Your picture',
                  child: InkResponse(
                    key: const Key('profile.avatar'),
                    radius: 54,
                    onTap: () => showPictureViewer(context),
                    child: const AccountAvatar(size: 96),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InlineUsername(username: profile.username),
                      Text(
                        profile.email,
                        key: const Key('account.email'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.mutedText, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Text(
            'Tap your picture or your name to change them.',
            style: TextStyle(color: colors.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
