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
  final controller = ref.read(remoteControllerProvider);
  if (controller == null) return;
  final devices = ref.read(remoteDevicesProvider).value ?? const [];
  final link = ref.read(remoteLinkProvider).value;
  final choice = MediaQuery.sizeOf(context).width < phoneBreakpoint
      ? await _sheet(context, devices, link?.device.deviceId)
      : await _popup(context, devices, link?.device.deviceId);
  if (choice == null) return;
  if (choice == _thisDevice) {
    controller.deselect();
  } else if (choice is RemotePresence) {
    await selectRemote(ref.read(playerServiceProvider), controller, choice);
  }
}

const _updateHint = 'Update Songies to control this device';

String? _subtitle(RemotePresence d) =>
    d.compatible ? (d.playing ? d.title : null) : _updateHint;

Future<Object?> _sheet(
  BuildContext context,
  List<RemotePresence> devices,
  String? linked,
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
                enabled: d.compatible,
                leading: Icon(Icons.devices_rounded, color: colors.text),
                title: Text(
                  d.name,
                  style: TextStyle(
                    color: d.compatible ? colors.text : colors.mutedText,
                  ),
                ),
                subtitle: _subtitle(d) == null ? null : Text(_subtitle(d)!),
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
          subtitle: _subtitle(d),
          enabled: d.compatible,
          checked: linked == d.deviceId,
        ),
    ],
  );
}
