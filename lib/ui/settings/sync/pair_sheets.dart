import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/log.dart';
import '../../../sync/pairing_code.dart';
import '../../../sync/pairing_service.dart';
import '../../../sync/sync_host.dart';
import '../../../theme/app_theme.dart';

/// The port Sync devices serves on unless it is taken.
const int defaultSyncPort = 47823;

const _noneFoundText =
    'No device showing that code was found. Check the code, and that both '
    'devices are on the same Wi-Fi.';

Future<void> _showSheet(BuildContext context, Widget sheet) {
  final colors = Theme.of(context).extension<SongiesColors>()!;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.background,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: sheet,
        ),
      ),
    ),
  );
}

/// Shows a fresh pairing code for 5 minutes, with this device's addresses
/// for Connect by address. Closes once a new device pairs; hides the code
/// when it closes.
Future<void> showCodeSheet(BuildContext context, SyncHost host) =>
    _showSheet(context, _ShowCodeSheet(host));

/// Asks for the code another device shows and pairs with it; offers
/// Connect by address when no device answers. Closes once paired (the
/// first sync then runs on the page).
Future<void> enterCodeSheet(BuildContext context, SyncHost host) =>
    _showSheet(context, _EnterCodeSheet(host));

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          color: colors.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ShowCodeSheet extends StatefulWidget {
  const _ShowCodeSheet(this.host);

  final SyncHost host;

  @override
  State<_ShowCodeSheet> createState() => _ShowCodeSheetState();
}

class _ShowCodeSheetState extends State<_ShowCodeSheet> {
  PairingCode? _code;
  late DateTime _shownAt;
  Duration _left = PairingCode.lifetime;
  bool _failed = false;
  Timer? _tick;
  Set<String>? _known;
  StreamSubscription<List<SyncDeviceView>>? _devicesSub;
  late final Future<List<String>> _addresses = widget.host
      .localAddresses()
      .catchError((Object _) => const <String>[]);

  @override
  void initState() {
    super.initState();
    _newCode();
    _devicesSub = widget.host.devices.listen(_onDevices);
  }

  void _newCode() {
    try {
      _code = widget.host.showCode();
      _failed = false;
    } on StateError {
      _code = null;
      _failed = true;
      return;
    }
    _shownAt = DateTime.now();
    _left = PairingCode.lifetime;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final left = PairingCode.lifetime - DateTime.now().difference(_shownAt);
    setState(() => _left = left.isNegative ? Duration.zero : left);
    if (_left == Duration.zero) _tick?.cancel();
  }

  /// A device that was not paired when the sheet opened has paired.
  void _onDevices(List<SyncDeviceView> devices) {
    final ids = {for (final d in devices) d.peer.deviceId};
    final known = _known;
    if (known == null) {
      _known = ids;
    } else if (!known.containsAll(ids) && mounted) {
      Navigator.of(context).pop();
    } else {
      _known = ids;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_devicesSub?.cancel());
    widget.host.hideCode();
    super.dispose();
  }

  static String _clock(Duration d) {
    final seconds = (d.inMilliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final code = _code;
    final expired = _left == Duration.zero;
    final muted = TextStyle(color: colors.mutedText);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetTitle('Show a code'),
        if (_failed || code == null)
          Text("Sync devices hasn't started yet. Try again.", style: muted)
        else ...[
          Text(
            'On the other device, open Sync devices, tap Enter a code and '
            'type this code.',
            style: TextStyle(color: colors.text),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              code.code,
              key: const Key('sync.code.shown'),
              style: TextStyle(
                color: expired ? colors.mutedText : colors.text,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
                fontFeatures: const [FontFeature.tabularFigures()],
                decoration: expired ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: expired
                ? TextButton(
                    key: const Key('sync.code.again'),
                    onPressed: () => setState(_newCode),
                    child: const Text('Expired. Show a new code'),
                  )
                : Text('Expires in ${_clock(_left)}', style: muted),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Or connect by address on the other device:',
          style: TextStyle(color: colors.text),
        ),
        FutureBuilder<List<String>>(
          future: _addresses,
          builder: (context, snap) {
            final port = widget.host.port ?? defaultSyncPort;
            final list = snap.data;
            if (list == null) return Text('…', style: muted);
            if (list.isEmpty) {
              return Text('No network address found', style: muted);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final a in list)
                  SelectableText(
                    '$a:$port',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EnterCodeSheet extends StatefulWidget {
  const _EnterCodeSheet(this.host);

  final SyncHost host;

  @override
  State<_EnterCodeSheet> createState() => _EnterCodeSheetState();
}

class _EnterCodeSheetState extends State<_EnterCodeSheet> {
  final _code = TextEditingController();
  final _address = TextEditingController();
  final _port = TextEditingController(text: '$defaultSyncPort');
  bool _byAddress = false;
  bool _working = false;
  String? _message;
  bool _offerAddress = false;

  @override
  void dispose() {
    _code.dispose();
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  bool get _codeValid => RegExp(r'^\d{6}$').hasMatch(_code.text);

  Future<void> _pairByCode() async {
    if (!_codeValid || _working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    FindOutcome outcome;
    try {
      outcome = await widget.host.pairByCode(_code.text);
    } catch (e) {
      AppLog.w('Pairing by code failed', e);
      outcome = FindOutcome.noneFound;
    }
    if (!mounted) return;
    if (outcome == FindOutcome.paired) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _working = false;
      _message = _noneFoundText;
      _offerAddress = true;
    });
  }

  Future<void> _pairByAddress() async {
    final host = _address.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null || !_codeValid || _working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    PairOutcome outcome;
    try {
      outcome = await widget.host.pairByAddress(host, port, _code.text);
    } catch (e) {
      AppLog.w('Pairing by address failed', e);
      outcome = PairOutcome.unreachable;
    }
    if (!mounted) return;
    if (outcome == PairOutcome.paired) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _working = false;
      _message = switch (outcome) {
        PairOutcome.wrongCode =>
          "That code didn't match. Check it, or show a new code there.",
        PairOutcome.noCodeShowing =>
          '$host:$port is not showing a code. Tap Show a code there first.',
        _ =>
          "Couldn't reach $host:$port. Check the address, and that both "
              'devices are on the same Wi-Fi.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final message = _message;
    final codeField = TextField(
      key: const Key('sync.code.field'),
      controller: _code,
      autofocus: !_byAddress,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
      style: TextStyle(color: colors.text, fontSize: 24, letterSpacing: 6),
      decoration: const InputDecoration(labelText: 'Code'),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _byAddress ? _pairByAddress() : _pairByCode(),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle(_byAddress ? 'Connect by address' : 'Enter a code'),
        if (_byAddress) ...[
          Text(
            'The other device shows its address under its code.',
            style: TextStyle(color: colors.text),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const Key('sync.address.host'),
                  controller: _address,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  style: TextStyle(color: colors.text),
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: '192.168.1.20',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('sync.address.port'),
                  controller: _port,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(color: colors.text),
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ] else
          Text(
            'Type the code the other device shows.',
            style: TextStyle(color: colors.text),
          ),
        codeField,
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              message,
              key: const Key('sync.pair.message'),
              style: TextStyle(color: colors.text),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            if (_working)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (_offerAddress && !_byAddress)
              TextButton(
                key: const Key('sync.connectByAddress'),
                onPressed: _working
                    ? null
                    : () => setState(() {
                        _byAddress = true;
                        _message = null;
                      }),
                child: const Text('Connect by address'),
              ),
            FilledButton(
              key: Key(_byAddress ? 'sync.address.pair' : 'sync.code.pair'),
              onPressed: _working || !_codeValid
                  ? null
                  : (_byAddress ? _pairByAddress : _pairByCode),
              child: const Text('Pair'),
            ),
          ],
        ),
      ],
    );
  }
}
