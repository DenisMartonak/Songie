import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../providers.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import 'account_section.dart';
import 'avatar.dart';

/// Your picture, large, with Change picture and (when you have one) Remove
/// picture. It closes once a change is done; a failure shows in it.
Future<void> showPictureViewer(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _PictureViewer());

class _PictureViewer extends ConsumerStatefulWidget {
  const _PictureViewer();

  static const double size = 240;

  @override
  ConsumerState<_PictureViewer> createState() => _PictureViewerState();
}

class _PictureViewerState extends ConsumerState<_PictureViewer> {
  bool _busy = false;
  String? _error;

  /// Runs [action]; on success shows [done] and closes, else says why.
  Future<void> _run(Future<void> Function() action, String done) async {
    final islands = Islands.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      final error = accountActionError(e);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
      return;
    }
    islands.show(done, kind: IslandKind.success);
    if (mounted) navigator.pop();
  }

  Future<void> _change() async {
    if (_busy) return;
    final service = ref.read(accountServiceProvider);
    final pick = await ref.read(avatarPickerProvider)();
    if (!mounted || pick == null) return;
    final bytes = pick.bytes;
    if (bytes == null || pick.size > maxAvatarSourceBytes) {
      setState(() => _error = 'That image is too big');
      return;
    }
    await _run(() => service.changeAvatar(bytes), 'Picture updated');
  }

  Future<void> _remove() async {
    if (_busy) return;
    final service = ref.read(accountServiceProvider);
    await _run(service.removeAvatar, 'Picture removed');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountStateProvider).value;
    final hasPicture = state is SignedIn && state.profile.avatarPath != null;
    final error = _error;
    return Dialog(
      key: const Key('profile.pictureViewer'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              key: Key('profile.pictureLarge'),
              dimension: _PictureViewer.size,
              child: AccountAvatar(size: _PictureViewer.size),
            ),
            const SizedBox(height: 20),
            if (error != null) ...[
              Text(
                error,
                key: const Key('profile.pictureError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('profile.changePicture'),
                  onPressed: _busy ? null : _change,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Change picture'),
                ),
                if (hasPicture)
                  TextButton.icon(
                    key: const Key('profile.removePicture'),
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.hide_image_outlined),
                    label: const Text('Remove picture'),
                  ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
