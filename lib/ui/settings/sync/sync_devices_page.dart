import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/log.dart';
import '../../../data/settings_repository.dart';
import '../../../providers.dart';
import '../../../sync/merger.dart';
import '../../../sync/sync_host.dart';
import '../../../sync/sync_progress.dart';
import '../../../sync/sync_responder.dart';
import '../../../theme/app_theme.dart';
import '../../motion/motion.dart';
import '../../widgets/name_dialog.dart';
import '../../island/island_controller.dart';
import '../../island/island_host.dart';
import '../settings_page.dart';
import 'clash_dialog.dart';
import 'pair_sheets.dart';
import 'sync_progress_card.dart';

/// A sync this device runs (tapped here, or started by the host right after
/// pairing) and the last thing it reported.
class _LocalRun {
  _LocalRun(this.peerId, this.cancel);

  final String peerId;
  final SyncCancel cancel;
  SyncProgress? last;
  bool finished = false;
  StreamSubscription<SyncProgress>? sub;
}

/// Settings → Sync devices: this device's name, the paired devices (tap to
/// sync, Unpair in the ⋯ menu), pairing by code, the firewall help, and the
/// state of the current sync. The sync host serves, advertises and browses
/// only while this page is open.
class SyncDevicesPage extends ConsumerStatefulWidget {
  const SyncDevicesPage({super.key});

  @override
  ConsumerState<SyncDevicesPage> createState() => _SyncDevicesPageState();
}

class _SyncDevicesPageState extends ConsumerState<SyncDevicesPage> {
  SyncHost? _host;
  final _subs = <StreamSubscription<Object?>>[];
  bool _started = false;
  bool _startFailed = false;
  List<SyncDeviceView> _devices = const [];

  /// What the status card shows: a [_LocalRun] or a [ResponderState].
  Object? _shown;
  _LocalRun? _run;

  /// Completes when the page goes away: an open clash question ends (null).
  final _left = Completer<void>();

  /// Dialogs the page opened that are still open, removed when it leaves.
  final _dialogs = <Route<Object?>>{};

  /// Whether the page is on screen ([TickerMode]: off in a background tab
  /// and under a covering route).
  bool _visible = true;

  /// Whether the host was asked to serve (it is stopped otherwise).
  bool _serving = false;

  /// A peer has a session open here (this device is the responder).
  bool _responderBusy = false;

  /// Pairing sheets open; their exchange needs the host serving.
  int _pairingOpen = 0;

  @override
  void initState() {
    super.initState();
    // Keeps the auto-disposed host alive while the page is open.
    ref.listenManual<SyncHost>(
      syncHostProvider,
      (_, host) => _attach(host),
      fireImmediately: true,
    );
  }

  void _attach(SyncHost host) {
    if (identical(host, _host)) return;
    _detach();
    _host = host;
    host.choose = (clashes) => _ask(clashes, _run?.peerId);
    _subs
      ..add(
        host.devices.listen((d) {
          if (mounted) setState(() => _devices = d);
        }),
      )
      ..add(host.responder.listen(_onResponder))
      ..add(host.runs.listen((r) => _follow(r.peerId, r.progress, r.cancel)));
    _serving = false;
    // Not before the first didChangeDependencies: visibility is known then.
    if (_visibilityKnown) _updateServing();
  }

  bool _visibilityKnown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _visibilityKnown = true;
    _updateServing();
  }

  /// Serves while the page is visible, or while a sync, a responder session
  /// or a pairing sheet still needs it; stops otherwise (no idle work in a
  /// background tab).
  void _updateServing() {
    final host = _host;
    if (host == null) return;
    final want = _visible || _running || _responderBusy || _pairingOpen > 0;
    if (want == _serving) return;
    _serving = want;
    if (!want) {
      _started = false;
      unawaited(
        host.stop().catchError(
          (Object e) => AppLog.w('Sync devices could not stop', e),
        ),
      );
      return;
    }
    _startFailed = false;
    host.start().then(
      (_) {
        if (mounted && identical(host, _host) && _serving) {
          setState(() => _started = true);
        }
      },
      onError: (Object e) {
        AppLog.w('Sync devices could not start', e);
        if (mounted && identical(host, _host) && _serving) {
          setState(() => _startFailed = true);
        }
      },
    );
  }

  /// Rebuilds, then stops the host if it is no longer needed.
  void _changed(VoidCallback change) {
    setState(change);
    _updateServing();
  }

  void _detach() {
    final host = _host;
    if (host == null) return;
    host.choose = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _host = null;
    _started = false;
    _serving = false;
  }

  @override
  void dispose() {
    _left.complete();
    for (final dialog in [..._dialogs]) {
      if (!dialog.isActive) continue;
      // Not while the tree is being torn down.
      final nav = dialog.navigator;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog.isActive) nav?.removeRoute(dialog);
      });
    }
    _dialogs.clear();
    final run = _run;
    if (run != null && !run.finished) run.cancel.cancel();
    unawaited(run?.sub?.cancel());
    _detach();
    super.dispose();
  }

  bool get _running => _run != null && !_run!.finished;

  String _nameOf(String? peerId) {
    for (final d in _devices) {
      if (d.peer.deviceId == peerId) return d.peer.name;
    }
    return 'the other device';
  }

  void _onResponder(ResponderState s) {
    if (!mounted) return;
    _changed(() {
      _responderBusy = s is WaitingFor || s is Receiving;
      if (s is! Idle && !_running) _shown = s;
    });
  }

  void _sync(String peerId) {
    final host = _host;
    if (host == null || _running) return;
    final cancel = SyncCancel();
    _follow(
      peerId,
      host.sync(
        peerId,
        choose: (clashes) => _ask(clashes, peerId),
        cancel: cancel,
      ),
      cancel,
    );
  }

  void _follow(
    String peerId,
    Stream<SyncProgress> progress,
    SyncCancel cancel,
  ) {
    if (!mounted) return;
    unawaited(_run?.sub?.cancel());
    final run = _LocalRun(peerId, cancel);
    run.sub = progress.listen(
      (e) {
        if (!mounted) return;
        _changed(() {
          run.last = e;
          // The last event: a new sync may start before the stream closes.
          if (e is SyncDone || e is SyncFailed) run.finished = true;
        });
      },
      onDone: () {
        if (mounted) _changed(() => run.finished = true);
      },
    );
    _changed(() => _shown = _run = run);
  }

  /// Asks about each clash in turn; null as soon as one is dismissed or the
  /// page goes away.
  Future<Map<String, Resolution>?> _ask(
    List<PlaylistClash> clashes,
    String? peerId,
  ) async {
    final choices = <String, Resolution>{};
    for (final clash in clashes) {
      if (!mounted || _left.isCompleted) return null;
      final choice = await _open(
        clashDialogRoute(context, clash, _nameOf(peerId)),
      );
      if (choice == null) return null;
      choices[clash.playlistId] = choice;
    }
    return choices;
  }

  /// Shows [route] as a dialog; null when dismissed or the page leaves
  /// (which also removes it).
  Future<T?> _open<T>(Route<T> route) async {
    _dialogs.add(route);
    try {
      return await Future.any<T?>([
        Navigator.of(context, rootNavigator: true).push(route),
        _left.future.then((_) => null),
      ]);
    } finally {
      _dialogs.remove(route);
    }
  }

  /// Keeps the host serving while a pairing sheet is open.
  Future<void> _pairing(Future<void> Function(SyncHost host) sheet) async {
    final host = _host;
    if (host == null) return;
    _pairingOpen++;
    try {
      await sheet(host);
    } finally {
      _pairingOpen--;
      if (mounted) _updateServing();
    }
  }

  Future<void> _editName(String current) async {
    final name = await _open(
      playlistNameDialogRoute(context, title: 'Device name', initial: current),
    );
    if (name == null || !mounted) return;
    await ref.read(settingsRepositoryProvider).setString(kDeviceName, name);
  }

  Future<void> _unpair(SyncDeviceView device) async {
    final islands = Islands.of(context);
    final name = device.peer.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unpair $name?'),
        content: Text(
          '$name and this device stop syncing. To sync them again, pair '
          'with a new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('sync.unpair.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    final host = _host;
    if (!(confirmed ?? false) || host == null) return;
    try {
      await host.unpair(device.peer.deviceId);
    } catch (e) {
      AppLog.w('Unpairing failed', e);
      islands.show("Couldn't unpair $name", kind: IslandKind.failure);
    }
  }

  Widget? _statusCard() {
    final shown = _shown;
    switch (shown) {
      case _LocalRun(:final last, :final peerId, :final cancel):
        final cancelButton = shown.finished || cancel.isCancelled
            ? null
            : () => setState(cancel.cancel);
        return switch (last) {
          null => SyncProgressCard(
            text: syncStageLabel(SyncStage.hello),
            progress: 0,
            onCancel: cancelButton,
          ),
          SyncStep(:final stage, :final done, :final total) => SyncProgressCard(
            text: syncStageLabel(stage, done: done, total: total),
            progress: syncStageFraction(stage, done: done, total: total),
            onCancel: cancelButton,
          ),
          SyncDone(:final summary) => SyncProgressCard(
            text: syncSummaryText(summary),
          ),
          SyncFailed(:final failure) => SyncProgressCard(
            text: syncFailureText(failure, _nameOf(peerId)),
            onRetry: syncFailureRetries(failure) ? () => _sync(peerId) : null,
          ),
        };
      case WaitingFor(:final peerName):
        return SyncProgressCard(text: 'Waiting for $peerName…');
      case Receiving(:final stage, :final done, :final total):
        return SyncProgressCard(
          text: syncStageLabel(stage, done: done, total: total),
          progress: syncStageFraction(stage, done: done, total: total),
        );
      case ResponderDone(:final summary):
        return SyncProgressCard(text: syncSummaryText(summary));
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final host = _host;
    final card = _statusCard();
    // Not while a sync runs here: the first sync after pairing would
    // replace it.
    final pairable = _started && host != null && !_running;
    final muted = TextStyle(color: colors.mutedText, fontSize: 12);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(bottom: bottom + 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
            child: Row(
              children: [
                if (context.canPop())
                  IconButton(
                    tooltip: 'Back',
                    color: colors.text,
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.pop(),
                  )
                else
                  const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Sync devices',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context).standard,
            curve: Motion.standardCurve,
            alignment: Alignment.topCenter,
            child: card ?? const SizedBox(width: double.infinity),
          ),
          if (_startFailed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                "Sync devices couldn't start on this device.",
                style: TextStyle(color: colors.text),
              ),
            ),
          const SettingsSectionTitle('This device'),
          _DeviceNameRow(onEdit: _editName),
          const SettingsSectionTitle('Your devices'),
          if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'No paired devices yet',
                style: TextStyle(color: colors.mutedText),
              ),
            ),
          for (final d in _devices)
            _DeviceRow(
              device: d,
              onSync: _running ? null : () => _sync(d.peer.deviceId),
              onUnpair: () => _unpair(d),
            ),
          const SettingsSectionTitle('Pair a new device'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('sync.showCode'),
                  onPressed: pairable
                      ? () => _pairing((h) => showCodeSheet(context, h))
                      : null,
                  icon: const Icon(Icons.pin_outlined),
                  label: const Text('Show a code'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('sync.enterCode'),
                  onPressed: pairable
                      ? () => _pairing((h) => enterCodeSheet(context, h))
                      : null,
                  icon: const Icon(Icons.dialpad_rounded),
                  label: const Text('Enter a code'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'The other device needs Sync devices open too.',
              style: muted,
            ),
          ),
          _FirewallHelp(port: host?.port ?? defaultSyncPort),
        ],
      ),
    );
  }
}

class _DeviceNameRow extends ConsumerWidget {
  const _DeviceNameRow({required this.onEdit});

  final void Function(String current) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final name = ref.watch(deviceNameProvider).value ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'The name other devices see',
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('sync.deviceName.edit'),
            tooltip: 'Rename',
            color: colors.text,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => onEdit(name),
          ),
        ],
      ),
    );
  }
}

/// "2026-10-21 09:05" in local time.
String _dateTimeText(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)} '
      '${two(l.hour)}:${two(l.minute)}';
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.onSync,
    required this.onUnpair,
  });

  final SyncDeviceView device;
  final VoidCallback? onSync;
  final VoidCallback onUnpair;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final peer = device.peer;
    final online = device.online != null;
    final synced = peer.lastSyncAt;
    return ListTile(
      key: Key('sync.device.${peer.deviceId}'),
      onTap: onSync,
      leading: Semantics(
        label: online ? 'On the network' : 'Not on the network',
        child: Container(
          key: Key(
            'sync.device.${peer.deviceId}.${online ? 'online' : 'offline'}',
          ),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? colors.accent : null,
            border: Border.all(
              color: online ? colors.accent : colors.mutedText,
              width: 2,
            ),
          ),
        ),
      ),
      title: Text(
        peer.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        synced == null
            ? 'Never synced'
            : 'Last synced ${_dateTimeText(synced)}',
        style: TextStyle(color: colors.mutedText, fontSize: 12),
      ),
      trailing: PopupMenuButton<void>(
        key: Key('sync.device.${peer.deviceId}.menu'),
        tooltip: 'More',
        icon: Icon(Icons.more_horiz_rounded, color: colors.text),
        itemBuilder: (_) => [
          PopupMenuItem<void>(onTap: onUnpair, child: const Text('Unpair')),
        ],
      ),
    );
  }
}

/// How to let the other device in: the firewalld commands on Linux, a note
/// on Windows, nothing elsewhere.
class _FirewallHelp extends ConsumerWidget {
  const _FirewallHelp({required this.port});

  final int port;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final linux = ref.watch(isLinuxProvider);
    final windows = ref.watch(isWindowsProvider);
    if (!linux && !windows) return const SizedBox.shrink();
    final commands =
        'sudo firewall-cmd --permanent --add-port=$port/tcp\n'
        'sudo firewall-cmd --permanent --add-service=mdns\n'
        'sudo firewall-cmd --reload';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('Firewall'),
        if (windows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Windows may ask to allow Songies on private networks. '
              'Allow it.',
              style: TextStyle(color: colors.text),
            ),
          ),
        if (linux) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "If the devices can't find each other, open the port and mDNS "
              'in the firewall:',
              style: TextStyle(color: colors.text),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    commands,
                    style: TextStyle(
                      color: colors.text,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('sync.firewall.copy'),
                  tooltip: 'Copy',
                  color: colors.text,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () async {
                    final islands = Islands.of(context);
                    await Clipboard.setData(ClipboardData(text: commands));
                    islands.show('Copied', kind: IslandKind.success);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
