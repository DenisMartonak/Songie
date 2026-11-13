import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/avatar.dart';
import 'room_button.dart';

/// The picture of who put a queue entry tagged [addedBy] in the room's
/// queue; nothing outside a room or when that person is unknown. The name
/// is not shown, only given on hover and to screen readers.
class RoomFaceDot extends ConsumerWidget {
  const RoomFaceDot({required this.addedBy, required this.size, super.key});

  final String? addedBy;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faces = ref.watch(roomFacesProvider);
    final face = faces?.of(addedBy);
    if (faces == null || face == null) return const SizedBox.shrink();
    final id = faces.faces.containsKey(addedBy) ? addedBy : faces.untagged;
    return Tooltip(
      key: Key('room.face.$id'),
      message: face.name,
      child: Semantics(
        label: face.name,
        child: PersonAvatar(name: face.name, url: face.avatarUrl, size: size),
      ),
    );
  }
}
