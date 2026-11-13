import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_service.dart';
import '../../providers.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import 'shared_playlist_sheet.dart';

/// Opens shared playlist links ([playlistInviteProvider]) once the account
/// is known: signed in, the playlist's sheet; signed out, a Sign in island.
class PlaylistInvites extends ConsumerStatefulWidget {
  const PlaylistInvites({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PlaylistInvites> createState() => _PlaylistInvitesState();
}

class _PlaylistInvitesState extends ConsumerState<PlaylistInvites> {
  @override
  void initState() {
    super.initState();
    // A link can arrive before the account has loaded (it started the app).
    ref.listenManual(
      playlistInviteProvider,
      (_, _) => _later(),
      fireImmediately: true,
    );
    ref.listenManual(accountStateProvider, (_, _) => _later());
  }

  /// Out of the listener: it can be called while building.
  void _later() => scheduleMicrotask(_take);

  void _take() {
    if (!mounted) return;
    final code = ref.read(playlistInviteProvider);
    if (code == null) return;
    final account = ref.read(accountStateProvider);
    if (account.isLoading && !account.hasValue) return;
    ref.read(playlistInviteProvider.notifier).clear();
    if (account.value is! SignedIn) {
      final router = GoRouter.maybeOf(context);
      Islands.of(context).show(
        'Log in to open shared playlists',
        kind: IslandKind.info,
        action: router == null
            ? null
            : IslandAction(
                label: 'Sign in',
                onPressed: () => router.go('/profile'),
              ),
      );
      return;
    }
    unawaited(showSharedPlaylistSheet(context, code));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
