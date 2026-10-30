import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/log.dart';
import '../data/database.dart';
import '../data/sync_stamp.dart';
import '../downloads/download_repository.dart';
import 'device_identity.dart';
import 'discovery.dart';
import 'file_transfer.dart';
import 'merger.dart';
import 'pairing_code.dart';
import 'pairing_service.dart';
import 'peer_repository.dart';
import 'sync_auth.dart';
import 'sync_progress.dart';
import 'sync_responder.dart';
import 'sync_runner.dart';
import 'sync_server.dart';

/// How [SyncHost.pairByCode] ended.
enum FindOutcome {
  paired,

  /// No device showing a code answered.
  noneFound,

  /// Devices showing a code answered, but none matched.
  wrongCode,
}

/// A paired device and, when it is on the network now, where.
class SyncDeviceView {
  const SyncDeviceView(this.peer, this.online);

  final PeerRow peer;
  final FoundDevice? online;
}

/// A sync the host started itself: the first one after pairing here.
class HostRun {
  const HostRun(this.peerId, this.progress, this.cancel);

  final String peerId;

  /// Every event of the run from its start (late listeners get them all).
  final Stream<SyncProgress> progress;
  final SyncCancel cancel;
}

/// Everything Sync devices runs while it is open: the HTTPS server with the
/// pairing and responder routes, the mDNS advertisement and browsing, and
/// this device's own sync runs.
///
/// One sync at a time per device: a local run is refused while a peer has a
/// session open here, and a peer is refused (`busy`) while a local run is in
/// progress. With [stopWhenPaused] (Android) the host stops while the app is
/// paused and starts again on resume; a run in progress then finishes first.
class SyncHost {
  SyncHost({
    required this._db,
    required this._stamp,
    required this._peers,
    required this._identity,
    required this._downloads,
    required this._myName,
    required Discovery Function() discovery,
    this._files,
    this._preferredPort = 47823,
    this._bindAddress,
    this._findTimeout = findTimeout,
    bool stopWhenPaused = false,
  }) : _newDiscovery = discovery {
    _runner = SyncRunner(
      db: _db,
      stamp: _stamp,
      peers: _peers,
      myDeviceId: _myId,
      downloads: _downloads,
      files: _files == null
          ? null
          : (c, cancel) => _files.exchange(c, cancel: cancel),
    );
    _peerSub = _peers.watch().listen((rows) {
      _peerRows = rows;
      _publishDevices();
    }, onError: (Object e) => AppLog.w('Watching paired devices failed', e));
    if (stopWhenPaused) {
      _lifecycle = AppLifecycleListener(
        onStateChange: (s) => unawaited(onLifecycle(s)),
      );
    }
  }

  /// How long [pairByCode] looks for the device showing the code.
  static const findTimeout = Duration(seconds: 10);

  final AppDatabase _db;
  final SyncStamp _stamp;
  final PeerRepository _peers;
  final DeviceIdentity _identity;
  final DownloadRepository _downloads;
  final String Function() _myName;
  final Discovery Function() _newDiscovery;
  final FileTransfer? _files;
  final int _preferredPort;
  final InternetAddress? _bindAddress;
  final Duration _findTimeout;

  late final SyncRunner _runner;
  late final StreamSubscription<List<PeerRow>> _peerSub;
  AppLifecycleListener? _lifecycle;

  // While started.
  SyncServer? _server;
  PairingService? _pairing;
  SyncResponder? _responder;
  Discovery? _discovery;
  final _subs = <StreamSubscription<Object?>>[];
  bool _codeShowing = false;
  Timer? _codeExpiry;

  /// Serialises start and stop.
  Future<void> _lifecycleQueue = Future.value();

  /// Serialises advertisements, so the last one wins.
  Future<void> _adQueue = Future.value();

  /// Started by [start] and not stopped by [stop] (a pause keeps it).
  bool _wanted = false;
  bool _paused = false;
  bool _disposed = false;
  final _disposedSignal = Completer<void>();

  /// Cancels the runs the host started itself ([runs]).
  final _ownRuns = <SyncCancel>{};
  int _localRuns = 0;

  var _peerRows = const <PeerRow>[];
  var _found = const <FoundDevice>[];
  Completer<void> _foundChanged = Completer();
  List<SyncDeviceView>? _lastDevices;
  ResponderState _lastResponder = const Idle();
  final _devicesOut = StreamController<List<SyncDeviceView>>.broadcast();
  final _responderOut = StreamController<ResponderState>.broadcast();
  // Sync: a run is announced before pairByCode or pairByAddress returns.
  final _runsOut = StreamController<HostRun>.broadcast(sync: true);

  /// Asked about playlist clashes in runs the host starts itself ([runs]).
  /// While null, such a run leaves at the first clash (cancelled).
  ChooseClashes? choose;

  String get _myId => _stamp.deviceId;

  /// The port served, or null while stopped.
  int? get port => _server?.port;

  /// Paired devices with their network presence, starting with the current
  /// list once known.
  Stream<List<SyncDeviceView>> get devices => Stream.multi((m) {
    final last = _lastDevices;
    if (last != null) m.add(last);
    final sub = _devicesOut.stream.listen(m.add, onDone: m.close);
    m.onCancel = sub.cancel;
  });

  /// What this device shows as a responder, starting with the current state.
  Stream<ResponderState> get responder => Stream.multi((m) {
    m.add(_lastResponder);
    final sub = _responderOut.stream.listen(m.add, onDone: m.close);
    m.onCancel = sub.cancel;
  });

  /// Syncs the host starts itself (after this device paired by code or
  /// address).
  Stream<HostRun> get runs => _runsOut.stream;

  bool get _busy =>
      _localRuns > 0 || _runner.running || (_responder?.inSession ?? false);

  // --- Start and stop -------------------------------------------------------

  /// Serves, advertises and browses. Calling it while started does nothing.
  Future<void> start() {
    _wanted = true;
    return _serial(_startServing);
  }

  /// Stops serving, advertising and browsing.
  Future<void> stop() {
    _wanted = false;
    return _serial(_stopServing);
  }

  /// Stops and releases everything; the host is not used again.
  /// Runs the host started itself are cancelled, and a clash question they
  /// are waiting on is left (as null).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    choose = null;
    for (final c in _ownRuns) {
      c.cancel();
    }
    _ownRuns.clear();
    _disposedSignal.complete();
    _lifecycle?.dispose();
    await stop();
    await _peerSub.cancel();
    await _devicesOut.close();
    await _responderOut.close();
    await _runsOut.close();
  }

  Future<void> _serial(Future<void> Function() step) {
    final next = _lifecycleQueue.then((_) => step());
    _lifecycleQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _startServing() async {
    if (_server != null || _disposed) return;
    final pairing = PairingService(
      identity: _identity,
      peers: _peers,
      myDeviceId: _myId,
      myName: _myName,
      onCodeSpent: _onCodeSpent,
    );
    final responder = SyncResponder(
      db: _db,
      stamp: _stamp,
      peers: _peers,
      myDeviceId: _myId,
      myName: _myName,
      downloads: _downloads,
      files: _files,
      runningLocally: () => _localRuns > 0 || _runner.running,
    );
    final server = SyncServer(_identity, RequestVerifier(_peers));
    pairing.register(server);
    responder.register(server);
    try {
      await server.start(preferredPort: _preferredPort, address: _bindAddress);
    } catch (_) {
      await responder.dispose();
      await pairing.dispose();
      rethrow;
    }
    _server = server;
    _pairing = pairing;
    _responder = responder;
    _subs
      ..add(responder.state.listen(_onResponder))
      ..add(pairing.paired.listen(_onPaired));
    AppLog.i('Sync server on port ${server.port}');

    // Connect by address still works without mDNS, so a failure here only
    // logs.
    try {
      final discovery = _discovery = _newDiscovery();
      _subs.add(discovery.found.listen(_onFound));
      await _advertise();
      await discovery.startBrowsing();
    } catch (e) {
      AppLog.w('mDNS browsing unavailable', e);
    }
  }

  Future<void> _stopServing() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    _hideCode();
    final subs = [..._subs];
    _subs.clear();
    final discovery = _discovery;
    _discovery = null;
    final responder = _responder;
    final pairing = _pairing;
    _responder = null;
    _pairing = null;
    // Each step runs whatever the others do: the server must always stop.
    for (final s in subs) {
      await _quietly('Cancelling a sync subscription', s.cancel);
    }
    if (discovery != null) {
      await _quietly(
        'Stopping the mDNS advertisement',
        discovery.stopAdvertising,
      );
      await _quietly('Stopping mDNS browsing', discovery.dispose);
    }
    await _quietly('Stopping the sync server', server.stop);
    if (responder != null) {
      await _quietly('Closing the sync responder', responder.dispose);
    }
    if (pairing != null) {
      await _quietly('Closing pairing', pairing.dispose);
    }
    _setFound(const []);
    _setResponder(const Idle());
    AppLog.i('Sync server stopped');
  }

  static Future<void> _quietly(
    String what,
    Future<void> Function() step,
  ) async {
    try {
      await step();
    } catch (e) {
      AppLog.w('$what failed', e);
    }
  }

  /// Stops on `paused` and starts again on `resumed` (Android). A run in
  /// progress finishes first; the host then stops.
  @visibleForTesting
  Future<void> onLifecycle(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
        _paused = true;
        if (!_busy) await _serial(_stopServing);
      case AppLifecycleState.resumed:
        _paused = false;
        if (_wanted) await _serial(_startServing);
      default:
        break;
    }
  }

  void _stopIfPausedAndIdle() {
    if (_paused && !_busy && _server != null) {
      unawaited(_serial(_stopServing));
    }
  }

  // --- Discovery ------------------------------------------------------------

  Future<void> _advertise() {
    final next = _adQueue.then((_) async {
      final d = _discovery;
      final port = _server?.port;
      if (d == null || port == null) return;
      try {
        await d.advertise(
          id: _myId,
          name: _myName(),
          port: port,
          pairing: _codeShowing,
        );
      } catch (e) {
        AppLog.w('mDNS advertisement failed', e);
      }
    });
    _adQueue = next;
    return next;
  }

  /// Keeps one entry per device id (the last one wins), not this device.
  void _onFound(List<FoundDevice> devices) {
    final byId = <String, FoundDevice>{};
    for (final d in devices) {
      if (d.id == _myId) continue;
      byId.remove(d.id);
      byId[d.id] = d;
    }
    _setFound([...byId.values]);
  }

  void _setFound(List<FoundDevice> devices) {
    _found = List.unmodifiable(devices);
    final changed = _foundChanged;
    _foundChanged = Completer();
    changed.complete();
    _publishDevices();
  }

  FoundDevice? _foundById(String id) {
    for (final d in _found) {
      if (d.id == id) return d;
    }
    return null;
  }

  void _publishDevices() {
    final views = [
      for (final p in _peerRows) SyncDeviceView(p, _foundById(p.deviceId)),
    ];
    _lastDevices = views;
    if (!_devicesOut.isClosed) _devicesOut.add(views);
    _storeAddresses(views);
  }

  /// Remembers where paired devices were found (a peer paired here as the
  /// responder has no address until then; a peer's address can change).
  void _storeAddresses(List<SyncDeviceView> views) {
    for (final v in views) {
      final f = v.online;
      if (f == null || (v.peer.host == f.host && v.peer.port == f.port)) {
        continue;
      }
      unawaited(
        _peers
            .setAddress(v.peer.deviceId, f.host, f.port)
            .catchError(
              (Object e) => AppLog.w('Saving a peer address failed', e),
            ),
      );
    }
  }

  // --- Responder ------------------------------------------------------------

  void _onResponder(ResponderState s) {
    _setResponder(s);
    if (s is Idle || s is ResponderDone) _stopIfPausedAndIdle();
  }

  void _setResponder(ResponderState s) {
    _lastResponder = s;
    if (!_responderOut.isClosed) _responderOut.add(s);
  }

  // --- Pairing --------------------------------------------------------------

  /// Shows a fresh pairing code and advertises `pairing=1` while it lasts.
  PairingCode showCode() {
    final pairing = _pairing;
    if (pairing == null) throw StateError('SyncHost is not started');
    final code = pairing.showCode();
    _codeShowing = true;
    _codeExpiry?.cancel();
    _codeExpiry = Timer(PairingCode.lifetime, () {
      if (_codeShowing) hideCode();
    });
    unawaited(_advertise());
    return code;
  }

  void hideCode() {
    final was = _codeShowing;
    _hideCode();
    if (was) unawaited(_advertise());
  }

  void _hideCode() {
    _pairing?.hideCode();
    _codeShowing = false;
    _codeExpiry?.cancel();
    _codeExpiry = null;
  }

  /// The code took its last attempt: stop advertising `pairing=1`. The code
  /// itself stays, so an exchange started on that attempt can still finish.
  void _onCodeSpent() {
    if (!_codeShowing) return;
    _codeShowing = false;
    unawaited(_advertise());
  }

  void _onPaired(PeerRow peer) {
    // The code pairs once: when it was ours, stop advertising pairing.
    if (_codeShowing && !(_pairing?.codeShowing ?? false)) hideCode();
  }

  /// Tries [code] on every device found showing a code, in turn, until one
  /// pairs, for at most [findTimeout] in all (waiting for discovery
  /// included). On success the first sync starts at once ([runs]).
  Future<FindOutcome> pairByCode(String code) async {
    final deadline = Completer<void>();
    final timer = Timer(_findTimeout, deadline.complete);
    final tried = <String>{};
    var answered = false;
    try {
      while (!deadline.isCompleted) {
        final pairing = _pairing;
        if (pairing == null) break;
        FoundDevice? next;
        for (final d in _found) {
          if (d.pairing && !tried.contains(d.id)) {
            next = d;
            break;
          }
        }
        if (next == null) {
          await Future.any([deadline.future, _foundChanged.future]);
          continue;
        }
        tried.add(next.id);
        final result = await Future.any<(PairOutcome, PeerRow?)?>([
          pairing.pair(next.host, next.port, code),
          deadline.future.then((_) => null),
        ]);
        switch (result?.$1) {
          case PairOutcome.paired:
            _syncAfterPairing(result!.$2!.deviceId);
            return FindOutcome.paired;
          case PairOutcome.wrongCode:
            answered = true;
          case PairOutcome.noCodeShowing || PairOutcome.unreachable || null:
            break;
        }
      }
      return answered ? FindOutcome.wrongCode : FindOutcome.noneFound;
    } finally {
      timer.cancel();
    }
  }

  /// Pairs with the device at [host]:[port] showing [code] (Connect by
  /// address). On success the first sync starts at once ([runs]).
  Future<PairOutcome> pairByAddress(String host, int port, String code) async {
    final pairing = _pairing;
    if (pairing == null) return PairOutcome.unreachable;
    final (outcome, peer) = await pairing.pair(host, port, code);
    if (peer != null) _syncAfterPairing(peer.deviceId);
    return outcome;
  }

  /// Starts the first sync with [peerId], just paired here. Nothing starts
  /// once the host is disposed.
  void _syncAfterPairing(String peerId) {
    if (_disposed) return;
    final cancel = SyncCancel();
    _ownRuns.add(cancel);
    final events = <SyncProgress>[];
    final live = StreamController<SyncProgress>.broadcast();
    var done = false;
    final progress = Stream<SyncProgress>.multi((m) {
      events.forEach(m.add);
      if (done) {
        m.close();
        return;
      }
      final sub = live.stream.listen(m.add, onDone: m.close);
      m.onCancel = sub.cancel;
    });
    _runsOut.add(HostRun(peerId, progress, cancel));
    sync(peerId, choose: _askOrLeave, cancel: cancel).listen(
      (e) {
        events.add(e);
        live.add(e);
      },
      onDone: () {
        _ownRuns.remove(cancel);
        done = true;
        live.close();
      },
    );
  }

  /// Asks [choose]; leaves (null) when there is none or the host is disposed
  /// while it waits.
  Future<Map<String, Resolution>?> _askOrLeave(List<PlaylistClash> c) {
    final ask = choose;
    if (ask == null || _disposed) return Future.value();
    return Future.any([ask(c), _disposedSignal.future.then((_) => null)]);
  }

  // --- Sync -----------------------------------------------------------------

  /// Syncs with the paired device [peerId]: at the address discovery found it
  /// (which is then stored), else at its stored address. Ends with
  /// [SyncFailed] `notFound` when it has neither, and `busy` while another
  /// sync runs on this device either way.
  Stream<SyncProgress> sync(
    String peerId, {
    required ChooseClashes choose,
    SyncCancel? cancel,
  }) async* {
    if (_busy) {
      yield const SyncFailed(SyncFailure.busy);
      return;
    }
    _localRuns++;
    try {
      final PeerRow? peer;
      final String? host;
      final int? port;
      try {
        peer = await _peers.byId(peerId);
        final online = _foundById(peerId);
        host = online?.host ?? peer?.host;
        port = online?.port ?? peer?.port;
        if (peer != null &&
            online != null &&
            (peer.host != host || peer.port != port)) {
          await _peers.setAddress(peerId, host!, port!);
        }
      } catch (e) {
        AppLog.w('Preparing a sync failed', e);
        yield const SyncFailed(SyncFailure.network);
        return;
      }
      if (peer == null || host == null || port == null) {
        yield const SyncFailed(SyncFailure.notFound);
        return;
      }
      yield* _runner.run(
        peer,
        host: host,
        port: port,
        choose: choose,
        cancel: cancel,
      );
    } finally {
      _localRuns--;
      _stopIfPausedAndIdle();
    }
  }

  /// Asks [peerId] to forget this device (best effort), then forgets it here.
  Future<void> unpair(String peerId) async {
    final peer = await _peers.byId(peerId);
    if (peer == null) return;
    final online = _foundById(peerId);
    final host = online?.host ?? peer.host;
    final port = online?.port ?? peer.port;
    if (host != null && port != null) {
      await _runner.unpair(peer, host: host, port: port);
    }
    await _peers.remove(peerId);
  }

  /// This device's non-loopback IPv4 addresses (shown for Connect by
  /// address).
  Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback && a.type == InternetAddressType.IPv4) a.address,
    ];
  }
}
