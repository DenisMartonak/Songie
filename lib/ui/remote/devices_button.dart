import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../providers.dart';
import '../../remote/remote_protocol.dart';
import '../../theme/app_theme.dart';
import '../shell/adaptive_shell.dart' show phoneBreakpoint;

/// The button that opens the device picker; absent signed out. Accent while
/// another device is being controlled.
class DevicesButton extends ConsumerWidget {
  const DevicesButton({this.iconSize = 20, this.color, super.key});

  final double iconSize;

  /// The idle colour; the muted text colour when null.
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(accountStateProvider).value is SignedIn;
    if (!signedIn) return const SizedBox.shrink();
    // Watched so the picker opens with the devices already known.
    ref.watch(remoteDevicesProvider);
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final linked = ref.watch(remoteLinkProvider.select((l) => l.value != null));
    return IconButton(
      key: const Key('devices.button'),
      tooltip: 'Devices',
      iconSize: iconSize,
      color: linked ? colors.accent : (color ?? colors.mutedText),
      icon: const Icon(Icons.devices_rounded),
      onPressed: () => showDevicesPicker(context, ref),
    );
  }
}

/// What the picker returns for This device (a cancelled picker returns null).
const Object _thisDevice = Object();

/// Opens the picker over [context]'s widget: a popup menu on desktop, a
/// bottom sheet on a phone. Picking a device controls it; This device goes
/// back to this one.
Future<void> showDevicesPicker(BuildContext context, WidgetRef ref) async {
  // The widget that opened the picker can go while it is open (the strip
  // when the link ends): use the container, which outlives it.
  final container = ProviderScope.containerOf(context);
  final controller = container.read(remoteControllerProvider);
  if (controller == null) return;
  final devices = container.read(remoteDevicesProvider).value ?? const [];
  final link = container.read(remoteLinkProvider).value;
  // In a room (hosting or guesting) this device controls no other one.
  final inRoom = container.read(inRoomProvider);
  final choice = MediaQuery.sizeOf(context).width < phoneBreakpoint
      ? await _sheet(context, devices, link?.device.deviceId, inRoom)
      : await _popup(context, devices, link?.device.deviceId, inRoom);
  if (choice == null) return;
  // Another account (or none) since the picker opened: do nothing.
  if (container.read(remoteControllerProvider) != controller) return;
  if (choice == _thisDevice) {
    controller.deselect();
  } else if (choice is RemotePresence && !container.read(inRoomProvider)) {
    await selectRemote(
      container.read(playerServiceProvider),
      controller,
      choice,
    );
  }
}

const _updateHint = 'Update Songies to control this device';
const _inRoomHint = 'In a Listen together room';
const _leaveRoomHint = 'Leave the room to control another device';

/// A device in a room takes no remote control, and this device in a room
/// controls none.
bool _available(RemotePresence d, bool inRoom) =>
    !inRoom && d.compatible && !d.inRoom;

String? _subtitle(RemotePresence d, bool inRoom) => inRoom
    ? _leaveRoomHint
    : !d.compatible
    ? _updateHint
    : d.inRoom
    ? _inRoomHint
    : (d.playing ? d.title : null);

Future<Object?> _sheet(
  BuildContext context,
  List<RemotePresence> devices,
  String? linked,
  bool inRoom,
) {
  return showModalBottomSheet<Object>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) {
      final colors = Theme.of(sheet).extension<SongiesColors>()!;
      return SingleChildScrollView(
        key: const Key('devices.sheet'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('devices.thisDevice'),
              leading: Icon(Icons.computer_rounded, color: colors.text),
              title: Text('This device', style: TextStyle(color: colors.text)),
              trailing: linked == null
                  ? Icon(
                      Icons.check_rounded,
                      key: const Key('devices.thisDevice.check'),
                      color: colors.accent,
                    )
                  : null,
              onTap: () => Navigator.of(sheet).pop(_thisDevice),
            ),
            if (devices.isEmpty)
              ListTile(
                title: Text(
                  'No other devices online',
                  style: TextStyle(color: colors.mutedText),
                ),
              ),
            for (final d in devices)
              ListTile(
                key: Key('devices.device.${d.deviceId}'),
                enabled: _available(d, inRoom),
                leading: Icon(Icons.devices_rounded, color: colors.text),
                title: Text(
                  d.name,
                  style: TextStyle(
                    color: _available(d, inRoom)
                        ? colors.text
                        : colors.mutedText,
                  ),
                ),
                subtitle: _subtitle(d, inRoom) == null
                    ? null
                    : Text(_subtitle(d, inRoom)!),
                trailing: linked == d.deviceId
                    ? Icon(Icons.check_rounded, color: colors.accent)
                    : null,
                onTap: () => Navigator.of(sheet).pop(d),
              ),
          ],
        ),
      );
    },
  );
}

Future<Object?> _popup(
  BuildContext context,
  List<RemotePresence> devices,
  String? linked,
  bool inRoom,
) {
  final colors = Theme.of(context).extension<SongiesColors>()!;
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(
            context,
            rootNavigator: true,
          ).overlay!.context.findRenderObject()!
          as RenderBox;
  final anchor = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );

  PopupMenuItem<Object> row({
    required Key key,
    required Object value,
    required String title,
    String? subtitle,
    bool enabled = true,
    bool checked = false,
    Key? checkKey,
  }) => PopupMenuItem<Object>(
    key: key,
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? colors.text : colors.mutedText,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
            ],
          ),
        ),
        if (checked) ...[
          const SizedBox(width: 12),
          Icon(
            Icons.check_rounded,
            key: checkKey,
            size: 20,
            color: colors.accent,
          ),
        ],
      ],
    ),
  );

  return showMenu<Object>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    color: colors.surface,
    items: [
      row(
        key: const Key('devices.thisDevice'),
        value: _thisDevice,
        title: 'This device',
        checked: linked == null,
        checkKey: const Key('devices.thisDevice.check'),
      ),
      if (devices.isEmpty)
        PopupMenuItem<Object>(
          enabled: false,
          child: Text(
            'No other devices online',
            style: TextStyle(color: colors.mutedText),
          ),
        ),
      for (final d in devices)
        row(
          key: Key('devices.device.${d.deviceId}'),
          value: d,
          title: d.name,
          subtitle: _subtitle(d, inRoom),
          enabled: _available(d, inRoom),
          checked: linked == d.deviceId,
        ),
    ],
  );
}
