import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_service.dart';
import '../../core/log.dart';
import '../../providers.dart';
import '../../room/room_service.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';

const String kRoomSignInText = 'You need a Songies account to join a room';

/// Shows [text] on the island, with a Sign in action (to Settings) when
/// [signIn] is set.
void showRoomIsland(BuildContext context, String text, {bool signIn = false}) {
  final router = signIn ? GoRouter.maybeOf(context) : null;
  Islands.of(context).show(
    text,
    action: router == null
        ? null
        : IslandAction(
            label: 'Sign in',
            onPressed: () => router.go('/settings'),
          ),
  );
}

/// Asks a yes/no question; true when the user chose [confirm].
Future<bool> confirmRoomStep(
  BuildContext context, {
  required String title,
  String? body,
  required String confirm,
}) async {
  final yes = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// Joins the room [code] (8 characters, no dash): signed out, the island
/// asks to sign in; in a room, or controlling another device, the user is
/// asked to leave that first. Uses [container] rather than a `ref`: the
/// widget that asked can go while the dialogs are up.
Future<void> joinRoomAsking(
  BuildContext context,
  ProviderContainer container,
  String code,
) async {
  final profile = switch (container.read(accountStateProvider).value) {
    SignedIn(:final profile) => profile,
    _ => null,
  };
  if (profile == null) {
    showRoomIsland(context, kRoomSignInText, signIn: true);
    return;
  }
  final service = container.read(roomServiceProvider);
  final status = service.status;
  if (status is! RoomIdle) {
    final leave = await confirmRoomStep(
      context,
      title: 'Leave the current room?',
      body: status is RoomHosting
          ? 'Your room ends for everyone in it.'
          : null,
      confirm: 'Leave',
    );
    if (!leave) return;
    await service.leave();
  }
  final controller = container.read(remoteControllerProvider);
  final link = controller?.link;
  if (link != null) {
    if (!context.mounted) return;
    final stop = await confirmRoomStep(
      context,
      title: 'Stop controlling ${link.device.name}?',
      confirm: 'Stop',
    );
    if (!stop) return;
    controller!.deselect();
  }
  try {
    await service.join(code, userId: profile.id, name: profile.username);
  } on StateError catch (e, s) {
    // Another join or a room started meanwhile.
    AppLog.w('room: join skipped', e, s);
  }
}
