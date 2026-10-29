import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result.dart';
import '../../core/log.dart';
import '../../data/settings_repository.dart';
import '../../innertube/yt_session_store.dart';
import '../../innertube/yt_sign_in.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../youtube/yt_models.dart';
import '../motion/motion.dart';
import '../widgets/page_snack_bar.dart';
import 'settings_page.dart';

/// Updates (or installs) yt-dlp and says how it went; true when it worked.
/// Settings → YouTube and the "Downloads failing" banner both use it.
Future<bool> updateYtDlp(
  WidgetRef ref,
  PageSnackBars snacks, {
  required bool Function() mounted,
}) async {
  final runner = ref.read(ytDlpRunnerProvider);
  final result = await runner.update();
  switch (result) {
    case Ok():
      if (mounted()) ref.invalidate(ytDlpVersionProvider);
      final version = await runner.version();
      snacks.show(
        content: Text(
          version == null ? 'yt-dlp updated' : 'yt-dlp updated to $version',
        ),
      );
      return true;
    case Err(:final failure):
      snacks.show(content: Text(ytErrorUserMessage(failure)));
      return false;
  }
}

/// Settings → YouTube: the YouTube sign-in, the yt-dlp version with
/// Install / Update, (Linux) the system yt-dlp switch, and Reset YouTube
/// recommendations.
class YouTubeSettingsSection extends ConsumerStatefulWidget {
  const YouTubeSettingsSection({super.key});

  @override
  ConsumerState<YouTubeSettingsSection> createState() =>
      _YouTubeSettingsSectionState();
}

class _YouTubeSettingsSectionState
    extends ConsumerState<YouTubeSettingsSection> {
  bool _updating = false;
  bool _signingIn = false;

  /// The sign-in routes this device can use; null while finding out.
  List<YtSignInRoute>? _routes;

  /// The device-local "signed in" marker, so Sign out stays reachable when
  /// the keyring is not.
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    // R5: the keyring is probed here, when the row is built, never at
    // startup. After this frame: a store that fails at once would otherwise
    // change the auth state while the tree builds.
    Future.microtask(() {
      if (mounted) ref.read(ytAuthProvider.notifier).checkAvailable();
    });
    _findRoutes();
    _readMarker();
  }

  Future<void> _readMarker() async {
    bool marked;
    try {
      marked = await ref
          .read(settingsRepositoryProvider)
          .getBool(kYtSignedIn, fallback: false);
    } catch (_) {
      marked = false;
    }
    if (mounted) setState(() => _marked = marked);
  }

  /// Asks every route to forget its web data; best effort, never blocks or
  /// fails the sign-out.
  void _forgetRouteData() {
    for (final r in ref.read(ytSignInRoutesProvider)) {
      unawaited(() async {
        try {
          await r.forget();
        } catch (e) {
          AppLog.w('yt sign-out: route could not forget (${e.runtimeType})');
        }
      }());
    }
  }

  Future<void> _findRoutes() async {
    final usable = <YtSignInRoute>[];
    for (final r in ref.read(ytSignInRoutesProvider)) {
      try {
        if (await r.supported()) usable.add(r);
      } catch (_) {}
    }
    if (mounted) setState(() => _routes = usable);
  }

  /// Runs [route] and keeps what it brings back. Closing Google's page is
  /// not an error: nothing changes.
  Future<void> _signIn(YtSignInRoute route) async {
    if (_signingIn) return;
    final snacks = PageSnackBars.of(context);
    final auth = ref.read(ytAuthProvider.notifier);
    setState(() => _signingIn = true);
    try {
      await auth.checkAvailable();
      if (!mounted || ref.read(ytAuthProvider) is YtAuthUnavailable) return;
      final result = await route.signIn(context);
      if (result == null || !mounted) return;
      try {
        await auth.signIn(result.session, name: result.name);
        if (mounted) setState(() => _marked = true);
      } catch (e) {
        // Never the error text: it is not ours to show and must not carry
        // the session.
        AppLog.w('yt sign-in: could not store the session (${e.runtimeType})');
        await auth.checkAvailable();
        snacks.show(content: const Text("Couldn't save the YouTube sign-in"));
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  /// Forgets the YouTube sign-in on this device (after asking); Home
  /// reloads with the regular feed.
  Future<void> _signOut() async {
    final snacks = PageSnackBars.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of YouTube?'),
        content: const Text(
          'Songies forgets the YouTube sign-in on this device and Home shows '
          'the regular feed. Your library and history stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('settings.ytSignOut.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    final auth = ref.read(ytAuthProvider.notifier);
    final wasUnavailable = ref.read(ytAuthProvider) is YtAuthUnavailable;
    _forgetRouteData();
    try {
      await auth.signOut();
    } catch (e) {
      AppLog.w('yt sign-out: could not clear the keyring (${e.runtimeType})');
      snacks.show(
        content: const Text("Signed out, but the keyring couldn't be cleared"),
      );
    }
    if (!mounted) return;
    ref.invalidate(ytmHomeProvider);
    setState(() => _marked = false);
    // Signing out cleared the auth state; the keyring is still missing.
    if (wasUnavailable) unawaited(auth.checkAvailable());
  }

  Widget _signInRows(SongiesColors colors) {
    final auth = ref.watch(ytAuthProvider);
    final routes = _routes ?? const <YtSignInRoute>[];
    Widget line(String text, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(text, style: TextStyle(color: colors.text)),
    );
    Widget button({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
    final signOut = button(
      key: const Key('settings.ytSignOut'),
      icon: Icons.logout_rounded,
      label: 'Sign out',
      onPressed: _signOut,
    );

    final List<Widget> rows;
    final String key;
    switch (auth) {
      case YtAuthUnavailable():
        key = 'unavailable';
        rows = [
          line(
            'Sign-in needs a keyring (KWallet or GNOME Keyring), '
            "which isn't available",
          ),
          // Still marked signed in: let the user clear the markers and the
          // web data.
          if (_marked) signOut,
        ];
      case YtSignedIn(:final name):
        key = 'in';
        rows = [
          line(name == null ? 'Signed in' : 'Signed in as $name'),
          signOut,
        ];
      case YtExpired(:final name):
        key = 'expired';
        rows = [
          if (name != null) line('Signed in as $name'),
          // Every route: the first is "Sign in again", the others keep
          // their own label (Linux: the browser's sign-in).
          for (final (i, r) in routes.indexed)
            button(
              key: Key(
                i == 0 ? 'settings.ytSignInAgain' : 'settings.ytSignInAgain.$i',
              ),
              icon: Icons.login_rounded,
              label: i == 0 ? 'Sign in again' : r.label,
              onPressed: _signingIn ? null : () => _signIn(r),
            ),
          signOut,
        ];
      case YtSignedOut():
        key = 'out';
        rows = [
          for (final (i, r) in routes.indexed)
            button(
              key: Key('settings.ytSignIn.$i'),
              icon: Icons.login_rounded,
              label: r.label,
              onPressed: _signingIn ? null : () => _signIn(r),
            ),
        ];
    }
    return AnimatedSize(
      duration: Motion.of(context).standard,
      curve: Motion.standardCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: Motion.of(context).quick,
        child: Column(
          key: ValueKey(key),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }

  Future<void> _update() async {
    if (_updating) return;
    final snacks = PageSnackBars.of(context);
    setState(() => _updating = true);
    try {
      await updateYtDlp(ref, snacks, mounted: () => mounted);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  /// Forgets YouTube's anonymous visitor id (after asking), so the feed
  /// starts fresh, and reloads the feed.
  Future<void> _resetRecommendations() async {
    final snacks = PageSnackBars.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset YouTube recommendations?'),
        content: const Text(
          'Songies forgets the anonymous id YouTube uses to tailor your Home '
          'feed on this device, and the feed starts fresh. Your library and '
          'history stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('settings.ytReset.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    await ref.read(innertubeClientProvider).resetVisitor();
    if (!mounted) return;
    ref.invalidate(ytmHomeProvider);
    snacks.show(content: const Text('YouTube recommendations reset'));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final isAndroid = ref.watch(isAndroidProvider);
    final isLinux = ref.watch(isLinuxProvider);
    final version = ref.watch(ytDlpVersionProvider);
    final installed = version.value;
    final install = !isAndroid && version.hasValue && installed == null;
    final useSystem = ref.watch(useSystemYtDlpProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('YouTube'),
        _signInRows(colors),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            version.isLoading
                ? 'yt-dlp version: …'
                : 'yt-dlp version: ${installed ?? 'not installed'}',
            style: TextStyle(color: colors.text),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            key: const Key('settings.ytdlpUpdate'),
            onPressed: _updating || version.isLoading ? null : _update,
            icon: _updating
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(install ? Icons.download_rounded : Icons.update_rounded),
            label: Text(install ? 'Install yt-dlp' : 'Update yt-dlp'),
          ),
        ),
        if (isLinux)
          SwitchListTile(
            title: Text(
              'Use system yt-dlp',
              style: TextStyle(color: colors.text),
            ),
            subtitle: Text(
              'Takes effect after restart',
              style: TextStyle(color: colors.mutedText, fontSize: 12),
            ),
            value: useSystem,
            onChanged: (v) => ref
                .read(settingsRepositoryProvider)
                .setBool(kYtdlpUseSystem, v),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            key: const Key('settings.ytReset'),
            onPressed: _resetRecommendations,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset YouTube recommendations'),
          ),
        ),
      ],
    );
  }
}
