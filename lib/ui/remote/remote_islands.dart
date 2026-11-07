import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../remote/remote_controller.dart';
import '../../remote/remote_protocol.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';

/// Shows an island when a remote link ends without the user asking: the
/// device didn't answer, or was lost. Mount it once, high in the app shell.
class RemoteEndedIslands extends ConsumerStatefulWidget {
  const RemoteEndedIslands({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RemoteEndedIslands> createState() => _RemoteEndedIslandsState();
}

class _RemoteEndedIslandsState extends ConsumerState<RemoteEndedIslands> {
  StreamSubscription<(RemotePresence, RemoteEndReason)>? _sub;

  @override
  void initState() {
    super.initState();
    // The provider rebuilds with each controller (sign-out, sign-in, another
    // account): follow its newest stream.
    ref.listenManual(remoteEndedProvider, (_, ended) {
      _sub?.cancel();
      _sub = ended.listen(_onEnded);
    }, fireImmediately: true);
  }

  void _onEnded((RemotePresence, RemoteEndReason) end) {
    if (!mounted) return;
    final (device, reason) = end;
    final text = switch (reason) {
      RemoteEndReason.noAnswer => "${device.name} didn't answer",
      RemoteEndReason.lost => 'Lost connection to ${device.name}',
      RemoteEndReason.deselected || RemoteEndReason.signedOut => null,
    };
    if (text == null) return;
    Islands.of(context).show(text, kind: IslandKind.failure);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
