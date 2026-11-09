import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../room/room_protocol.dart';
import '../../room/room_service.dart';
import '../../theme/app_theme.dart';
import 'room_panel.dart';

/// "Listening with `host`", plus what [role] allows.
String roomGuestText(RoomPresence host, RoomRole role) =>
    'Listening with ${host.name}${switch (role) {
      RoomRole.listener => '',
      RoomRole.queue => ' · can add songs',
      RoomRole.full => ' · full control',
    }}';

/// "Your room · `n` listening": the guests, this device not counted.
String roomHostText(List<RoomPresence> people) =>
    'Your room · ${people.where((p) => !p.host).length} listening';

/// Says which room this device is in, above the player bar (and the phone's
/// mini player): a guest's has Leave, a host's Manage. Nothing outside a
/// room. Tapping it opens the room panel.
class RoomStrip extends ConsumerWidget {
  const RoomStrip({super.key});

  static const double height = 28;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(roomStatusProvider).value;
    final (text, action) = switch (status) {
      RoomGuesting(:final host, :final role) => (
        roomGuestText(host, role),
        'Leave',
      ),
      RoomHosting(:final people) => (roomHostText(people), 'Manage'),
      _ => (null, null),
    };
    if (text == null) return const SizedBox.shrink();
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Material(
      color: colors.accent.withAlpha(36),
      child: InkWell(
        key: const Key('room.strip'),
        onTap: () => showRoomPanel(context, ref),
        child: Container(
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.headphones_rounded, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.accent,
                  minimumSize: const Size(0, 24),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => status is RoomGuesting
                    ? unawaited(ref.read(roomServiceProvider).leave())
                    : showRoomPanel(context, ref),
                child: Text(action!),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The room at the top of the full-screen player, where "Playing on…" goes
/// for remote control: "Listening with `host`" for a guest, the host's
/// strip text for a host. Tapping it opens the room panel.
class RoomChip extends ConsumerWidget {
  const RoomChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = switch (ref.watch(roomStatusProvider).value) {
      RoomGuesting(:final host) => 'Listening with ${host.name}',
      RoomHosting(:final people) => roomHostText(people),
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: colors.accent.withAlpha(36),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('room.chip'),
          onTap: () => showRoomPanel(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.headphones_rounded, size: 14, color: colors.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
