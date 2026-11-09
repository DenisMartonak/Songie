import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../providers.dart';
import '../../room/room_service.dart';
import 'join_room_dialog.dart';

/// Shows the room's notices as islands, and takes up a room invite (a link
/// that opened the app): signed out it asks to sign in; else it joins,
/// asking first to leave a room or stop controlling a device. Mount it once,
/// high in the app shell, below the navigator (it shows dialogs).
class RoomIslands extends ConsumerStatefulWidget {
  const RoomIslands({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RoomIslands> createState() => _RoomIslandsState();
}

class _RoomIslandsState extends ConsumerState<RoomIslands> {
  StreamSubscription<RoomNotice>? _sub;

  @override
  void initState() {
    super.initState();
    ref.listenManual(roomNoticesProvider, (_, notices) {
      _sub?.cancel();
      _sub = notices.listen(_onNotice);
    }, fireImmediately: true);
    // An invite can arrive before the account has loaded (a link that
    // started the app): it waits for the account.
    ref.listenManual(
      roomInviteProvider,
      (_, _) => _later(),
      fireImmediately: true,
    );
    ref.listenManual(accountStateProvider, (_, _) => _later());
  }

  void _onNotice(RoomNotice notice) {
    if (!mounted) return;
    switch (notice) {
      case RoomNoticeText(:final text, :final signIn):
        showRoomIsland(context, text, signIn: signIn);
    }
  }

  /// Out of the listener: it can be called while building.
  void _later() => scheduleMicrotask(_takeInvite);

  void _takeInvite() {
    if (!mounted) return;
    final code = ref.read(roomInviteProvider);
    if (code == null) return;
    final account = ref.read(accountStateProvider);
    if (account.isLoading && !account.hasValue) return;
    ref.read(roomInviteProvider.notifier).clear();
    if (account.value is! SignedIn) {
      showRoomIsland(context, kRoomSignInText, signIn: true);
      return;
    }
    unawaited(
      joinRoomAsking(context, ProviderScope.containerOf(context), code),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
