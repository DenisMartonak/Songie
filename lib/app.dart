import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'theme/app_theme.dart';

class SongiesApp extends ConsumerWidget {
  const SongiesApp({required this.router, super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(themeSpecProvider);
    return MaterialApp.router(
      title: 'Songies',
      debugShowCheckedModeBanner: false,
      theme: buildThemeData(spec),
      routerConfig: router,
    );
  }
}
