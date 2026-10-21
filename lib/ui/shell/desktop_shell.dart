import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'player_bar.dart';
import 'sidebar.dart';
import 'title_bar.dart';

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

class _NextIntent extends Intent {
  const _NextIntent();
}

class _PreviousIntent extends Intent {
  const _PreviousIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// Runs [onInvoke] unless [blockedWhileTyping] and a text field has focus, in
/// which case the key goes on to the text field.
class _ShellAction<T extends Intent> extends Action<T> {
  _ShellAction(this.onInvoke, {this.blockedWhileTyping = true});

  final VoidCallback onInvoke;
  final bool blockedWhileTyping;

  @override
  bool isEnabled(T intent) => !(blockedWhileTyping && _isTyping());

  @override
  Object? invoke(T intent) {
    onInvoke();
    return null;
  }
}

/// Whether a text field (an [EditableText]) currently has the keyboard focus.
bool _isTyping() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  // EditableText attaches its focus node to its own context.
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Desktop layout: title bar on top, sidebar and the current page in the
/// middle, the player bar below. Hosts the global keyboard shortcuts.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell(this.shell, {super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  static const _searchBranch = 1;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'shell search');

  /// Holds focus when no text field does, so shortcuts always have a target.
  final _rootFocus = FocusNode(debugLabel: 'shell root');

  bool _sidebarCollapsed = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    ref.read(searchQueryProvider.notifier).set(query);
    if (widget.shell.currentIndex != _searchBranch) {
      widget.shell.goBranch(_searchBranch);
    }
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final player = ref.read(playerServiceProvider);
    // Keep the field in step when something else sets the query.
    ref.listen(searchQueryProvider, (_, query) {
      if (_searchController.text != query) _searchController.text = query;
    });
    final chrome = Color.alphaBlend(
      Colors.black.withAlpha(90),
      colors.background,
    );

    return Scaffold(
      backgroundColor: chrome,
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): _TogglePlayIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
              _NextIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
              _PreviousIntent(),
          SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _FocusSearchIntent(),
        },
        child: Actions(
          actions: {
            _TogglePlayIntent: _ShellAction<_TogglePlayIntent>(
              player.togglePlay,
            ),
            _NextIntent: _ShellAction<_NextIntent>(player.next),
            _PreviousIntent: _ShellAction<_PreviousIntent>(player.previous),
            // Works from inside text fields too.
            _FocusSearchIntent: _ShellAction<_FocusSearchIntent>(
              _focusSearch,
              blockedWhileTyping: false,
            ),
          },
          child: Focus(
            focusNode: _rootFocus,
            autofocus: true,
            child: Column(
              children: [
                TitleBar(
                  searchController: _searchController,
                  searchFocus: _searchFocus,
                  onQueryChanged: _onQueryChanged,
                  onSubmitted: _onQueryChanged,
                  onTapOutsideSearch: _rootFocus.requestFocus,
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Buttons in the chrome must not take focus, or Space
                      // would re-press the last one clicked.
                      ExcludeFocus(
                        child: Sidebar(
                          shell: widget.shell,
                          collapsed: _sidebarCollapsed,
                          onToggle: () => setState(
                            () => _sidebarCollapsed = !_sidebarCollapsed,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              colors.radius + 4,
                            ),
                            child: ColoredBox(
                              color: colors.background,
                              child: widget.shell,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const ExcludeFocus(child: PlayerBar()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
