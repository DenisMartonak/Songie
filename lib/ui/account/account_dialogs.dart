import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../account/username.dart';
import '../../core/log.dart';
import '../../providers.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import 'auth_screens.dart' show UsernameField;

/// Asks for a new username and saves it; "Username changed" on success.
Future<void> showChangeUsernameDialog(BuildContext context, String current) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChangeUsernameDialog(current: current),
    );

class _ChangeUsernameDialog extends ConsumerStatefulWidget {
  const _ChangeUsernameDialog({required this.current});

  final String current;

  @override
  ConsumerState<_ChangeUsernameDialog> createState() =>
      _ChangeUsernameDialogState();
}

class _ChangeUsernameDialogState extends ConsumerState<_ChangeUsernameDialog> {
  late final _name = TextEditingController(text: widget.current);
  bool _busy = false;
  bool _taken = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave {
    final name = normalizeUsername(_name.text);
    return !_busy &&
        !_taken &&
        name != widget.current &&
        usernameProblem(name) == null;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final service = ref.read(accountServiceProvider);
    final islands = Islands.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await service.changeUsername(_name.text);
    } on AccountException catch (e) {
      error = e.error.message;
    } catch (e) {
      AppLog.w('Changing the username failed: ${e.runtimeType}');
      error = AccountError.unknown.message;
    }
    if (error == null) {
      islands.show('Username changed', kind: IslandKind.success);
      if (route != null && route.isCurrent) {
        navigator.pop();
      } else if (route != null && route.isActive) {
        navigator.removeRoute(route);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Change username'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UsernameField(
                fieldKey: const Key('account.newUsername'),
                controller: _name,
                current: widget.current,
                enabled: !_busy,
                autofocus: true,
                onChanged: () => setState(() => _error = null),
                onTaken: (taken) => setState(() => _taken = taken),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('account.dialogError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('account.saveUsername'),
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Asks before deleting the account; true to go ahead.
Future<bool> confirmDeleteAccount(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete account'),
      content: const Text(
        'Delete your account? Your username and picture are removed. '
        'Your music on this device stays.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('account.confirmDelete'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// Asks before logging out with changes the account hasn't got yet; true to
/// log out anyway.
Future<bool> confirmLogOutWithUnsent(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Log out'),
      content: const Text(
        "Some changes on this device haven't been uploaded yet. Log out "
        'anyway?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('account.confirmLogOut'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// Cloud sync's question on signing in as another account than last time:
/// true to merge this device's library into it, false to start empty.
///
/// Asked on [navigator] (the app's root navigator) once it is up: before the
/// first frame, or while the app is in the background and draws nothing, it
/// waits. Only a tap on "Start empty" answers false; the dialog can't be
/// dismissed, and if it is taken away unanswered it is asked again.
Future<bool> askMergeOrStartEmpty(GlobalKey<NavigatorState> navigator) async {
  while (true) {
    final context = navigator.currentContext;
    if (context != null && context.mounted) {
      final merge = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _MergeDialog(),
      );
      if (merge != null) return merge;
    }
    await WidgetsBinding.instance.endOfFrame;
  }
}

class _MergeDialog extends StatelessWidget {
  const _MergeDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Another account'),
        content: const Text(
          'This device has a library from another account. Merge it into '
          'this account, or start empty?',
        ),
        actions: [
          TextButton(
            key: const Key('account.startEmpty'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Start empty'),
          ),
          FilledButton(
            key: const Key('account.merge'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }
}
