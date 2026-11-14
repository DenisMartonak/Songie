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
import '../profile/profile_view.dart';
import 'account_dialogs.dart';
import 'account_section.dart';
import 'auth_screens.dart';
import 'edit_profile_sheet.dart';
import 'sync_warning.dart';

/// Your profile: the [ProfileView] with Edit profile and a ⋯ menu (Log
/// out, Delete account). Signed out, Sign up and Log in (what a "Sign in"
/// link lands on).
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

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
    final state = ref.watch(accountStateProvider).value;
    return KeyedSubtree(
      key: const Key('profile.page'),
      child: SafeArea(
        bottom: false,
        child: state is SignedIn ? _signedIn(context) : _signedOutPage(context),
      ),
    );
  }

  /// The failed action's message, if any.
  Widget? _errorText(BuildContext context, {bool center = false}) {
    final error = _error;
    if (error == null) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        error,
        key: const Key('account.error'),
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _signedIn(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final Widget menu = _busy
        ? const SizedBox.square(
            dimension: 48,
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        : PopupMenuButton<_Action>(
            key: const Key('profile.menu'),
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (a) => switch (a) {
              _Action.logOut => _logOut(),
              _Action.delete => _delete(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                key: Key('account.logOut'),
                value: _Action.logOut,
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Log out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: const Key('account.delete'),
                value: _Action.delete,
                child: ListTile(
                  iconColor: error,
                  textColor: error,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Delete account'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          );
    return ProfileView(
      source: const MyProfile(),
      actions: [
        FilledButton(
          key: const Key('profile.edit'),
          onPressed: _busy ? null : () => showEditProfile(context),
          child: const Text('Edit profile'),
        ),
      ],
      menu: menu,
      notice: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const SyncWarning(), ?_errorText(context, center: true)],
      ),
    );
  }

  Widget _signedOutPage(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ProfileView.phoneMaxWidth),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(colors: colors),
              ..._signedOut(context, colors),
              ?_errorText(context),
            ],
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
}

/// The ⋯ menu's items.
enum _Action { logOut, delete }

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
