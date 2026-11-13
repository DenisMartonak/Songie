import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/username.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import 'account_section.dart' show accountActionError;
import 'auth_screens.dart' show UsernameField;

/// Your username on the profile. A tap turns it into a field: Enter or the
/// check saves (the same rules as signing up), Esc or the cross puts the old
/// name back.
class InlineUsername extends ConsumerStatefulWidget {
  const InlineUsername({required this.username, super.key});

  final String username;

  @override
  ConsumerState<InlineUsername> createState() => _InlineUsernameState();
}

class _InlineUsernameState extends ConsumerState<InlineUsername> {
  TextEditingController? _name;
  bool _busy = false;
  bool _taken = false;
  String? _error;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  void _edit() => setState(() {
    _name = TextEditingController(text: widget.username);
    _taken = false;
    _error = null;
  });

  void _cancel() {
    if (_busy) return;
    final name = _name;
    setState(() {
      _name = null;
      _error = null;
    });
    // After the field is gone from the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => name?.dispose());
  }

  bool get _canSave {
    final controller = _name;
    if (controller == null) return false;
    final name = normalizeUsername(controller.text);
    return !_busy &&
        !_taken &&
        name != widget.username &&
        usernameProblem(name) == null;
  }

  Future<void> _save() async {
    final controller = _name;
    if (!_canSave || controller == null) return;
    final service = ref.read(accountServiceProvider);
    final islands = Islands.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await service.changeUsername(controller.text);
    } catch (e) {
      error = accountActionError(e);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    islands.show('Username changed', kind: IslandKind.success);
    _cancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final controller = _name;
    if (controller == null) {
      return Tooltip(
        message: 'Change username',
        child: InkWell(
          onTap: _edit,
          borderRadius: BorderRadius.circular(6),
          child: Text(
            widget.username,
            key: const Key('account.username'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }
    final error = _error;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: UsernameField(
                    fieldKey: const Key('account.newUsername'),
                    controller: controller,
                    current: widget.username,
                    enabled: !_busy,
                    autofocus: true,
                    onChanged: () => setState(() => _error = null),
                    onTaken: (taken) => setState(() => _taken = taken),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                IconButton(
                  key: const Key('profile.saveUsername'),
                  tooltip: 'Save',
                  color: colors.accent,
                  icon: const Icon(Icons.check_rounded),
                  onPressed: _canSave ? _save : null,
                ),
                IconButton(
                  key: const Key('profile.cancelUsername'),
                  tooltip: 'Cancel',
                  color: colors.text,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _busy ? null : _cancel,
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                key: const Key('account.dialogError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
