import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../account/avatar_image.dart' show ImageTooBigException;
import '../../core/log.dart';
import '../../providers.dart';
import '../../sync/cloud/sync_status.dart';
import '../../theme/app_theme.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../playlist/yt_playlist_actions.dart' show relativeTimeText;
import '../settings/settings_page.dart' show SettingsSectionTitle;
import 'account_dialogs.dart';
import 'auth_screens.dart';
import 'avatar.dart';

/// A picked picture's size and bytes; [bytes] is null when the file is over
/// [maxAvatarSourceBytes]: it is not read.
typedef AvatarPick = ({int size, Uint8List? bytes});

/// The biggest image file accepted as a picture (before shrinking).
const int maxAvatarSourceBytes = 10 * 1024 * 1024;

/// Asks the user for an image; null when cancelled. A provider so tests can
/// replace the native dialog.
final avatarPickerProvider = Provider<Future<AvatarPick?> Function()>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a picture',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final path = file?.path;
    if (path == null) return null;
    final f = File(path);
    final size = await f.length();
    return (
      size: size,
      bytes: size > maxAvatarSourceBytes ? null : await f.readAsBytes(),
    );
  },
);

/// The sync status line's main text.
String syncPhaseText(SyncPhase phase) => switch (phase) {
  SyncPhase.idle => 'Synced',
  SyncPhase.syncing => 'Syncing…',
  SyncPhase.offline => 'Waiting for internet',
  SyncPhase.error => "Couldn't sync. Will try again.",
  SyncPhase.clockWrong => "Can't sync: this device's date and time are wrong.",
};

/// Settings → Account: Sign up and Log in when signed out; the picture,
/// username, email and the account's actions when signed in.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A session restored while offline shows up once the profile loads.
    unawaited(
      ref.read(accountServiceProvider).refresh().catchError((Object _) {}),
    );
  }

  /// Runs [action] with the buttons off; [done] goes on the island after,
  /// and a failure shows below the buttons.
  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    final islands = Islands.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await action();
    } on AccountException catch (e) {
      error = e.error.message;
    } on ImageTooBigException {
      error = 'That image is too big';
    } on FormatException {
      error = "Couldn't read that image";
    } catch (e) {
      AppLog.w('Account action failed: ${e.runtimeType}');
      error = AccountError.unknown.message;
    }
    if (error == null) islands.show(done, kind: IslandKind.success);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _changePicture() async {
    if (_busy) return;
    final service = ref.read(accountServiceProvider);
    final pick = await ref.read(avatarPickerProvider)();
    if (!mounted || pick == null) return;
    final bytes = pick.bytes;
    if (bytes == null || pick.size > maxAvatarSourceBytes) {
      setState(() => _error = 'That image is too big');
      return;
    }
    await _run(() => service.changeAvatar(bytes), 'Picture updated');
  }

  /// Logs out. Changes the account hasn't got yet are uploaded first; if
  /// that can't be done (offline), it asks before logging out anyway.
  Future<void> _logOut() async {
    if (_busy) return;
    final service = ref.read(accountServiceProvider);
    final sync = ref.read(cloudSyncProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    var unsent = false;
    try {
      if (await sync.hasUnsent()) {
        await sync.syncNow();
        unsent = await sync.hasUnsent();
      }
    } catch (e) {
      // Can't tell: ask, rather than lose changes silently.
      AppLog.w('Checking for unsent changes failed: ${e.runtimeType}');
      unsent = true;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (unsent && !await confirmLogOutWithUnsent(context)) return;
    if (!mounted) return;
    await _run(service.logOut, 'Signed out');
  }

  Future<void> _delete() async {
    final service = ref.read(accountServiceProvider);
    if (!await confirmDeleteAccount(context) || !mounted) return;
    await _run(service.deleteAccount, 'Account deleted');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(accountStateProvider).value;
    final service = ref.read(accountServiceProvider);
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Account'),
        if (state is SignedIn)
          ..._signedIn(context, colors, state.profile, service)
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Optional. Gives you a username and a picture.',
              style: TextStyle(color: colors.mutedText, fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilledButton(
                  key: const Key('account.signUp'),
                  onPressed: () => showAuthScreen(context, AuthStart.signUp),
                  child: const Text('Sign up'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('account.logIn'),
                  onPressed: () => showAuthScreen(context, AuthStart.logIn),
                  child: const Text('Log in'),
                ),
              ],
            ),
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              error,
              key: const Key('account.error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  List<Widget> _signedIn(
    BuildContext context,
    SongiesColors colors,
    Profile profile,
    AccountService service,
  ) {
    final off = _busy;
    Widget action(
      String key,
      IconData icon,
      String label,
      VoidCallback onPressed, {
      Color? color,
    }) => TextButton.icon(
      key: Key(key),
      style: color == null
          ? null
          : TextButton.styleFrom(foregroundColor: color),
      onPressed: off ? null : onPressed,
      icon: Icon(icon),
      label: Text(label),
    );

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            const AccountAvatar(size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.username,
                    key: const Key('account.username'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    profile.email,
                    key: const Key('account.email'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (off)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
      const _SyncStatusLine(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          children: [
            action(
              'account.changeUsername',
              Icons.edit_outlined,
              'Change username',
              () => showChangeUsernameDialog(context, profile.username),
            ),
            action(
              'account.changePicture',
              Icons.image_outlined,
              'Change picture',
              _changePicture,
            ),
            if (profile.avatarPath != null)
              action(
                'account.removePicture',
                Icons.hide_image_outlined,
                'Remove picture',
                () => _run(service.removeAvatar, 'Picture removed'),
              ),
            action('account.logOut', Icons.logout_rounded, 'Log out', _logOut),
            action(
              'account.delete',
              Icons.delete_outline_rounded,
              'Delete account',
              _delete,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
      ),
    ];
  }
}

/// Cloud sync's state ("Synced", "Syncing…", …), when it last synced, and
/// Sync now.
class _SyncStatusLine extends ConsumerWidget {
  const _SyncStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final status =
        ref.watch(cloudSyncStatusProvider).value ??
        ref.read(cloudSyncProvider).current;
    final syncing = status.phase == SyncPhase.syncing;
    final last = status.lastSynced;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  syncPhaseText(status.phase),
                  key: const Key('account.syncStatus'),
                  style: TextStyle(
                    color: switch (status.phase) {
                      SyncPhase.error || SyncPhase.clockWrong => Theme.of(
                        context,
                      ).colorScheme.error,
                      _ => colors.text,
                    },
                    fontSize: 13,
                  ),
                ),
                if (last != null && !syncing)
                  Text(
                    'Last synced ${relativeTimeText(last, ref.read(nowProvider)())}',
                    key: const Key('account.lastSynced'),
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
                  ),
              ],
            ),
          ),
          TextButton(
            key: const Key('account.syncNow'),
            onPressed: syncing
                ? null
                : () => unawaited(ref.read(cloudSyncProvider).syncNow()),
            child: const Text('Sync now'),
          ),
        ],
      ),
    );
  }
}
