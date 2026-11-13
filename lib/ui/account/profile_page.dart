import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_service.dart';
import '../../core/log.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../settings/settings_page.dart' show SettingsSectionTitle;
import '../stats/stats_page.dart' show StatsBody;
import 'account_dialogs.dart';
import 'account_section.dart';
import 'auth_screens.dart';
import 'avatar.dart';
import 'inline_username.dart';
import 'picture_viewer.dart';

/// Your profile: the picture, username and email, your listening stats,
/// then the account's sync status and actions. Signed out, Sign up and Log
/// in (what a "Sign in" link lands on).
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  static const double _maxContentWidth = 720;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
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
    } catch (e) {
      error = accountActionError(e);
    }
    if (error == null) islands.show(done, kind: IslandKind.success);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
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
    final bottom = MediaQuery.paddingOf(context).bottom;
    final error = _error;
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ProfilePage._maxContentWidth,
          ),
          child: SingleChildScrollView(
            key: const Key('profile.page'),
            padding: EdgeInsets.only(bottom: bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(colors: colors),
                if (state is SignedIn)
                  ..._signedIn(context, colors, state.profile)
                else
                  ..._signedOut(context, colors),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      error,
                      key: const Key('account.error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _signedOut(BuildContext context, SongiesColors colors) => [
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
  ];

  List<Widget> _signedIn(
    BuildContext context,
    SongiesColors colors,
    Profile profile,
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Tooltip(
              message: 'Your picture',
              child: InkResponse(
                key: const Key('profile.avatar'),
                radius: 54,
                onTap: off ? null : () => showPictureViewer(context),
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
            if (off)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
      const StatsBody(),
      const SettingsSectionTitle('Account'),
      const SyncStatusLine(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          children: [
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

/// Back (when there is somewhere to go back to) and the page's title.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.colors});

  final SongiesColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Row(
        children: [
          if (context.canPop())
            IconButton(
              tooltip: 'Back',
              color: colors.text,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            )
          else
            const SizedBox(width: 8),
          Text(
            'Profile',
            style: TextStyle(
              color: colors.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
