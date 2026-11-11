import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/log.dart';
import 'providers.dart';
import 'theme/theme_service.dart';
import 'ui/island/island_host.dart';
import 'ui/motion/motion.dart';
import 'ui/update/update_dialog.dart';
import 'update/update_controller.dart';

class SongiesApp extends ConsumerStatefulWidget {
  const SongiesApp({
    required this.router,
    this.checkForUpdates = false,
    super.key,
  });

  final GoRouter router;

  /// Runs the once-per-run update check 3 s after the first frame (`main()`
  /// turns it on; tests leave it off so nothing reaches the network).
  final bool checkForUpdates;

  @override
  ConsumerState<SongiesApp> createState() => _SongiesAppState();
}

class _SongiesAppState extends ConsumerState<SongiesApp> {
  static const _startupDelay = Duration(seconds: 3);
  Timer? _startupTimer;

  @override
  void initState() {
    super.initState();
    if (widget.checkForUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startupTimer = Timer(_startupDelay, _startupCheck);
      });
    }
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _notificationTaps?.cancel();
    super.dispose();
  }

  StreamSubscription<void>? _notificationTaps;

  /// Silent unless an update is available; never throws. Opened from the
  /// update notification, it checks right away (past the 12 h limit).
  Future<void> _startupCheck() async {
    try {
      final controller = ref.read(updateControllerProvider.notifier);
      final notifications = ref.read(updateNotificationsProvider);
      _notificationTaps ??= notifications?.openRequests.listen(
        (_) => _checkFromNotification(),
      );
      if (notifications != null && await notifications.takeOpenRequest()) {
        await controller.checkNow();
      } else {
        await controller.startup();
      }
      // Android 13+: without it the update notification can't show.
      await notifications?.askPermissionOnce();
      if (!mounted) return;
      if (ref.read(updateControllerProvider) case Available() || ManualOnly()) {
        _showUpdateDialog();
      }
    } on Object catch (e, s) {
      AppLog.e('update: startup check failed', e, s);
    }
  }

  /// The update notification was tapped while Songies runs.
  Future<void> _checkFromNotification() async {
    try {
      await ref.read(updateControllerProvider.notifier).checkNow();
      if (!mounted) return;
      if (ref.read(updateControllerProvider) case Available() || ManualOnly()) {
        _showUpdateDialog();
      }
    } on Object catch (e, s) {
      AppLog.e('update: check from the notification failed', e, s);
    }
  }

  void _showUpdateDialog() {
    final context = widget.router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    showUpdateDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    // A download the user hid: ask to install once it is ready.
    ref.listen(updateControllerProvider, (prev, next) {
      if (next is ReadyToInstall && prev is! ReadyToInstall) {
        if (!updateDialogOpen) _showUpdateDialog();
      }
    });
    final theme = ref.watch(songiesThemeProvider);
    return MaterialApp.router(
      title: 'Songies',
      debugShowCheckedModeBanner: false,
      theme: theme,
      // The builder's AnimatedTheme below does the animating, where
      // MediaQuery (for reduced motion) is available.
      themeAnimationStyle: AnimationStyle.noAnimation,
      routerConfig: widget.router,
      builder: (context, child) => MotionScope(
        child: _ThemeScope(
          theme: theme,
          child: IslandHost(child: child!),
        ),
      ),
    );
  }
}

/// Tweens every colour together over [Motion.colour] when the theme changes
/// (instantly with reduced motion), and applies the theme's `fontScale` on
/// top of the system text scaling. Nothing animates while the theme is
/// unchanged.
class _ThemeScope extends ConsumerWidget {
  const _ThemeScope({required this.theme, required this.child});

  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(themeSpecProvider.select((s) => s.fontScale));
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: scaleText(media.textScaler, fontScale)),
      child: AnimatedTheme(
        data: theme,
        duration: Motion.of(context).colour,
        curve: Curves.linear,
        child: child,
      ),
    );
  }
}
