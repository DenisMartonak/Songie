import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'desktop_shell.dart';
import 'phone_shell.dart';

/// Below this width the phone layout is used, otherwise the desktop one.
const double phoneBreakpoint = 720;

/// Hosts the Home / Search / Library branches in the layout for the window
/// size: bottom nav + mini-player on phones, title bar + sidebar + player bar
/// on desktop.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell(this.shell, {super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width < phoneBreakpoint ? PhoneShell(shell) : DesktopShell(shell);
  }
}
