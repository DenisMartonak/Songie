import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../room/room_protocol.dart';
import '../../room/room_service.dart';
import '../../theme/app_theme.dart';
import 'room_panel.dart';

/// This device's role while it is a guest in a room; null otherwise (no
/// room, or hosting one).
final roomGuestRoleProvider = Provider<RoomRole?>(
  (ref) => switch (ref.watch(roomStatusProvider).value) {
    RoomGuesting(:final role) => role,
    _ => null,
  },
);

/// Whether this device is a room guest holding quiet on its own; its play
/// button then rejoins the room, whatever its role.
final roomGuestHeldProvider = Provider<bool>(
  (ref) => switch (ref.watch(roomStatusProvider).value) {
    RoomGuesting(:final held) => held,
    _ => false,
  },
);

/// Who added the queue's songs while this device is in a room.
class RoomFaces {
  const RoomFaces(this.faces, {this.untagged});

  final Map<String, RoomFace> faces;

  /// Whose an untagged queue entry is: the host's own id while hosting,
  /// null as a guest (its songs come tagged, or from a host before tags).
  final String? untagged;

  /// The face for a queue entry tagged [addedBy]; null when unknown.
  RoomFace? of(String? addedBy) {
    final id = addedBy ?? untagged;
    return id == null ? null : faces[id];
  }
}

/// [RoomFaces] while this device hosts or follows a room; null otherwise.
final roomFacesProvider = Provider<RoomFaces?>(
  (ref) => switch (ref.watch(roomStatusProvider).value) {
    RoomHosting(:final faces, :final me) => RoomFaces(faces, untagged: me),
    RoomGuesting(:final faces) => RoomFaces(faces),
    _ => null,
  },
);

/// Whether the player UI may offer [op]: always outside a room and to a
/// host; to a guest, as its [role] allows.
bool roomLets(RoomRole? role, RoomOp op) =>
    role == null || roleAllows(role, op);

/// The people-icon button that opens the room panel. Accent, with the
/// number of people, while this device is in a room.
class RoomButton extends ConsumerWidget {
  const RoomButton({this.iconSize = 20, this.color, super.key});

  final double iconSize;

  /// The idle colour; the muted text colour when null.
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final count = switch (ref.watch(roomStatusProvider).value) {
      RoomHosting(:final people) ||
      RoomGuesting(:final people) => people.length,
      _ => null,
    };
    return IconButton(
      key: const Key('room.button'),
      tooltip: 'Listen together',
      iconSize: iconSize,
      color: count != null ? colors.accent : (color ?? colors.mutedText),
      icon: Badge(
        isLabelVisible: count != null,
        label: Text('${count ?? 0}'),
        backgroundColor: colors.accent,
        textColor: colors.background,
        child: const Icon(Icons.group_rounded),
      ),
      onPressed: () => showRoomPanel(context, ref),
    );
  }
}
