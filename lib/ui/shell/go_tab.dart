import 'package:go_router/go_router.dart';

/// Switches to the Home / Search / Library tab [index] and always lands on its
/// root page. A plain `goBranch` would reopen whatever the branch last showed
/// (for example the playlist opened from the sidebar).
void goTab(StatefulNavigationShell shell, int index) =>
    shell.goBranch(index, initialLocation: true);
