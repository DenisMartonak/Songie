import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'theme/theme_service.dart';
import 'ui/motion/motion.dart';

class SongiesApp extends ConsumerWidget {
  const SongiesApp({required this.router, super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(songiesThemeProvider);
    return MaterialApp.router(
      title: 'Songies',
      debugShowCheckedModeBanner: false,
      theme: theme,
      // The builder's AnimatedTheme below does the animating, where
      // MediaQuery (for reduced motion) is available.
      themeAnimationStyle: AnimationStyle.noAnimation,
      routerConfig: router,
      builder: (context, child) => MotionScope(
        child: _ThemeScope(theme: theme, child: child!),
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
