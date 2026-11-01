import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/log.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'window_controls.dart';

/// The desktop window's custom title bar: app name, the global search field
/// (Ctrl+K) and the window buttons. Dragging anywhere else moves the window.
class TitleBar extends ConsumerWidget {
  const TitleBar({
    required this.searchController,
    required this.searchFocus,
    required this.onQueryChanged,
    required this.onSubmitted,
    required this.onTapOutsideSearch,
    super.key,
  });

  static const double height = 46;

  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onTapOutsideSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return SizedBox(
      key: const Key('titleBar'),
      height: height,
      // The drag area sits behind the controls instead of around them: its
      // double-tap recognizer would otherwise hold back clicks on the field.
      child: Stack(
        children: [
          const Positioned.fill(
            child: DragToMoveArea(child: SizedBox.expand()),
          ),
          Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.circle, size: 10, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                'Songies',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ShellSearchField.maxWidth,
                    ),
                    child: ShellSearchField(
                      controller: searchController,
                      focusNode: searchFocus,
                      onChanged: onQueryChanged,
                      onSubmitted: onSubmitted,
                      onTapOutside: onTapOutsideSearch,
                      colors: colors,
                    ),
                  ),
                ),
              ),
              ExcludeFocus(
                child: _WindowButtons(
                  controls: ref.watch(windowControlsProvider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The global search field (key `shell.search`), shared by the title bar and
/// the main-pane search row used when there is no custom title bar.
class ShellSearchField extends StatelessWidget {
  const ShellSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onTapOutside,
    required this.colors,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onTapOutside;
  final SongiesColors colors;

  /// Widest the field grows in a wide window.
  static const double maxWidth = 520;
  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextField(
        key: const Key('shell.search'),
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTapOutside: (_) => onTapOutside(),
        textInputAction: TextInputAction.search,
        style: TextStyle(color: colors.text, fontSize: 14),
        cursorColor: colors.accent,
        cursorHeight: 18,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surface,
          hintText: 'Search  (Ctrl+K)',
          hintStyle: TextStyle(color: colors.mutedText, fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 20, color: colors.mutedText),
          prefixIconConstraints: const BoxConstraints(minWidth: 42),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(height / 2),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(height / 2),
            borderSide: BorderSide(color: colors.accent, width: 1),
          ),
        ),
      ),
    );
  }
}

class _WindowButtons extends StatefulWidget {
  const _WindowButtons({required this.controls});

  final WindowControls controls;

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> {
  bool _maximized = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.controls.maximizedChanges.listen((m) {
      if (mounted) setState(() => _maximized = m);
    });
    widget.controls
        .isMaximized()
        .then((m) {
          if (mounted) setState(() => _maximized = m);
        })
        .catchError((Object e, StackTrace st) {
          AppLog.w('Could not read the window state', e, st);
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Row(
      children: [
        _WindowButton(
          key: const Key('window.minimize'),
          icon: Icons.remove,
          tooltip: 'Minimize',
          color: colors.text,
          onPressed: widget.controls.minimize,
        ),
        _WindowButton(
          key: const Key('window.maximize'),
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          iconSize: _maximized ? 13 : 15,
          tooltip: _maximized ? 'Restore' : 'Maximize',
          color: colors.text,
          onPressed: widget.controls.maximizeOrRestore,
        ),
        _WindowButton(
          key: const Key('window.close'),
          icon: Icons.close,
          tooltip: 'Close',
          color: colors.text,
          hoverColor: const Color(0xFFE81123),
          onPressed: widget.controls.close,
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.iconSize = 16,
    this.hoverColor,
    super.key,
  });

  final IconData icon;
  final double iconSize;
  final String tooltip;
  final Color color;
  final Color? hoverColor;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        hoverColor:
            hoverColor ??
            (Theme.of(context).extension<SongiesColors>()?.text ?? Colors.white)
                .withAlpha(26),
        child: SizedBox(
          width: 46,
          height: TitleBar.height,
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }
}
