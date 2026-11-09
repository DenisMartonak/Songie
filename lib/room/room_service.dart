import 'dart:async';

import '../core/log.dart';
import '../data/database.dart';
import '../player/player_service.dart';
import 'room_backend.dart';
import 'room_channel.dart';
import 'room_guest.dart';
import 'room_host.dart';
import 'room_links.dart';
import 'room_protocol.dart';

/// Where this device stands in Listen together.
sealed class RoomStatus {
  const RoomStatus();
}

class RoomIdle extends RoomStatus {
  const RoomIdle();
}

class RoomHosting extends RoomStatus {
  const RoomHosting({
    required this.code,
    required this.link,
    required this.people,
    required this.roles,
  });

  /// The 8 characters, without the dash.
  final String code;
  final String link;

  /// Everyone present, this device included.
  final List<RoomPresence> people;

  /// Each guest device's role, by device id.
  final Map<String, RoomRole> roles;
}

class RoomGuesting extends RoomStatus {
  const RoomGuesting({
    required this.host,
    required this.role,
    required this.people,
    required this.roles,
  });

  final RoomPresence host;

  /// This device's role.
  final RoomRole role;
  final List<RoomPresence> people;

  /// What this device knows of the roles: its own, by device id.
  final Map<String, RoomRole> roles;
}

/// Something to tell the user (shown as an island).
sealed class RoomNotice {
  const RoomNotice();
}

class RoomNoticeText extends RoomNotice {
  const RoomNoticeText(this.text, {this.signIn = false});
  final String text;

  /// Whether the notice offers to sign in.
  final bool signIn;
}

/// This device's one room: hosts it or follows another device's, and tells
/// the app how it stands. Everything is keyed on device ids, so two devices
/// of one account can be in the same room.
class RoomService {
  RoomService({
    required this._backend,
    required this._channelFor,
    required this._player,
    required this._tracksFor,
    required this._deviceId,
    required this._platform,
  });

  final RoomBackend _backend;
  final RoomChannel Function(String roomId) _channelFor;
  final PlayerService _player;
  final Future<List<Track?>> Function(List<RoomSong>) _tracksFor;
  final String _deviceId;
  final String _platform;

  final _statuses = StreamController<RoomStatus>.broadcast();
  final _notices = StreamController<RoomNotice>.broadcast();

  RoomStatus _status = const RoomIdle();

  /// An open or join is under way.
  bool _starting = false;

  String? _roomId;
  RoomHost? _host;
  RoomGuest? _guest;
  RoomGuestView? _view;
  final _subs = <StreamSubscription<Object?>>[];

  RoomStatus get status => _status;
  Stream<RoomStatus> get statuses => _statuses.stream;
  Stream<RoomNotice> get notices => _notices.stream;

  /// The player view while this device is a guest; null otherwise.
  RoomGuestView? get guestView => _view;

  void _set(RoomStatus s) {
    _status = s;
    if (!_statuses.isClosed) _statuses.add(s);
  }

  void _say(String text, {bool signIn = false}) {
    if (!_notices.isClosed) _notices.add(RoomNoticeText(text, signIn: signIn));
  }

  void _listen<T>(Stream<T> s, void Function(T) f) {
    _subs.add(s.listen(f));
  }

  void _guardStart() {
    if (_status is! RoomIdle || _starting) {
      throw StateError('Already in a room');
    }
  }

  RoomPresence _presence(String userId, String name, {required bool host}) =>
      RoomPresence(
        userId: userId,
        deviceId: _deviceId,
        name: name,
        platform: _platform,
        host: host,
      );

  /// Opens a room hosted by this device; with [play], the room starts with
  /// that queue.
  Future<void> open({
    required String userId,
    required String name,
    List<Track>? play,
  }) async {
    _guardStart();
    if (userId.isEmpty) {
      _say('You need a Songies account to join a room', signIn: true);
      return;
    }
    _starting = true;
    try {
      final OpenedRoom opened;
      try {
        opened = await _backend.open();
      } on Object catch (e, s) {
        AppLog.w('room: opening failed', e, s);
        _say("Couldn't reach the room");
        return;
      }
      final roomId = opened.roomId;
      final me = _presence(userId, name, host: true);
      final host = RoomHost(
        channel: _channelFor(roomId),
        player: _player,
        me: me,
        tracksFor: _tracksFor,
        removeMember: (user) => _backend.remove(roomId, user),
      );
      _roomId = roomId;
      _host = host;
      _listen(host.events, _onHostEvent);
      _listen(host.people, (list) {
        final s = _status;
        if (s is RoomHosting && identical(_host, host)) {
          _set(
            RoomHosting(
              code: s.code,
              link: s.link,
              people: list,
              roles: host.roles,
            ),
          );
        }
      });
      _set(
        RoomHosting(
          code: opened.code,
          link: roomLink(opened.code),
          people: [me],
          roles: const {},
        ),
      );
      await host.start();
      if (play != null && play.isNotEmpty && identical(_host, host)) {
        await _player.playQueue(play);
      }
    } finally {
      _starting = false;
    }
  }

  void _onHostEvent(RoomHostEvent e) {
    switch (e) {
      case GuestJoined(:final name):
        _say('$name joined');
      case GuestLeft(:final name):
        _say('$name left');
      case GuestAdded(:final name, :final title):
        _say('$name added $title');
    }
  }

  /// Joins the room [code] as a guest. A failure leaves the service idle and
  /// says why.
  Future<void> join(
    String code, {
    required String userId,
    required String name,
  }) async {
    _guardStart();
    if (userId.isEmpty) {
      _say('You need a Songies account to join a room', signIn: true);
      return;
    }
    _starting = true;
    try {
      final String roomId;
      try {
        roomId = await _backend.join(code);
      } on RoomJoinException catch (e) {
        _say(switch (e.kind) {
          RoomJoinError.full => 'This room is full',
          RoomJoinError.notFound => 'Room not found',
          RoomJoinError.ended => 'This room has ended',
          RoomJoinError.offline ||
          RoomJoinError.other => "Couldn't reach the room",
        });
        return;
      } on Object catch (e, s) {
        AppLog.w('room: joining failed', e, s);
        _say("Couldn't reach the room");
        return;
      }
      final guest = RoomGuest(
        channel: _channelFor(roomId),
        player: _player,
        me: _presence(userId, name, host: false),
        tracksFor: _tracksFor,
      );
      final view = RoomGuestView(guest);
      _roomId = roomId;
      _guest = guest;
      _view = view;

      // The status is guesting once the host is known (or the guest ended).
      final ready = Completer<void>();
      RoomPresence? hostSeen;
      var people = const <RoomPresence>[];
      void publish() {
        final h = hostSeen;
        if (h == null || !identical(_guest, guest)) return;
        _set(
          RoomGuesting(
            host: h,
            role: guest.role,
            people: people,
            roles: {_deviceId: guest.role},
          ),
        );
      }

      _listen(guest.people, (list) {
        people = list;
        hostSeen = guest.host ?? hostSeen;
        if (hostSeen != null && !ready.isCompleted) ready.complete();
        publish();
      });
      _listen(guest.roles, (role) {
        _say(switch (role) {
          RoomRole.queue => 'You can now add songs',
          RoomRole.full => 'You now have full control',
          RoomRole.listener => 'You can listen only',
        });
        publish();
      });
      _listen(guest.cantPlay, (title) {
        _say("Can't play $title here, joining in at the next song");
      });
      _listen(view.notices, _say);
      _listen(guest.ended, (reason) {
        if (!ready.isCompleted) ready.complete();
        unawaited(_guestEnded(guest, reason));
      });
      await guest.start();
      hostSeen ??= guest.host;
      if (hostSeen == null) await ready.future;
      publish();
    } finally {
      _starting = false;
    }
  }

  Future<void> _guestEnded(RoomGuest guest, RoomLeaveReason reason) async {
    if (!identical(_guest, guest)) return;
    final roomId = _roomId;
    _clear();
    _set(const RoomIdle());
    switch (reason) {
      case RoomLeaveReason.left:
        break;
      case RoomLeaveReason.ended || RoomLeaveReason.hostGone:
        _say('The room ended');
      case RoomLeaveReason.removed:
        _say('You were removed from the room');
      case RoomLeaveReason.unreachable:
        _say("Couldn't reach the room");
      case RoomLeaveReason.outdated:
        _say('Update Songies to join this room');
    }
    // Ended and removed: the server has already let this account go.
    if (roomId != null &&
        reason != RoomLeaveReason.ended &&
        reason != RoomLeaveReason.removed) {
      await _backendLeave(roomId);
    }
  }

  Future<void> _backendLeave(String roomId) async {
    try {
      await _backend.leave(roomId);
    } on Object catch (e, s) {
      AppLog.w('room: leave_room failed', e, s);
    }
  }

  void _clear() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _host = null;
    _guest = null;
    _view = null;
    _roomId = null;
  }

  /// Leaves the room: a guest goes, a host ends the room.
  Future<void> leave() async {
    if (_host != null) return end();
    final guest = _guest;
    if (guest == null) return;
    // Through the guest, so its player is given back as it was.
    await guest.leave();
    await _guestEnded(guest, RoomLeaveReason.left);
  }

  /// Ends the room for everyone when hosting; leaves it as a guest.
  Future<void> end() async {
    final host = _host;
    if (host == null) return leave();
    final roomId = _roomId;
    _clear();
    _set(const RoomIdle());
    await host.stop();
    if (roomId == null) return;
    try {
      await _backend.end(roomId);
    } on Object catch (e, s) {
      AppLog.w('room: end_room failed', e, s);
    }
  }

  /// Host only: sets what the guest device [deviceId] may do.
  Future<void> setRole(String deviceId, RoomRole role) async {
    final host = _host;
    if (host == null) return;
    await host.setRole(deviceId, role);
    _roles(host);
  }

  /// Host only: removes [guest] from the room.
  Future<void> remove(RoomPresence guest) async {
    final host = _host;
    if (host == null) return;
    await host.removeGuest(guest);
    _roles(host);
  }

  void _roles(RoomHost host) {
    final s = _status;
    if (s is RoomHosting && identical(_host, host)) {
      _set(
        RoomHosting(
          code: s.code,
          link: s.link,
          people: s.people,
          roles: host.roles,
        ),
      );
    }
  }

  /// The account went (signed out or changed): the session stops.
  Future<void> signedOut() => _host != null ? end() : leave();

  /// Stops quietly when the app's providers go: no server calls.
  void dispose() {
    final host = _host;
    final guest = _guest;
    _clear();
    if (host != null) unawaited(host.stop(end: false));
    if (guest != null) unawaited(guest.leave());
    unawaited(_statuses.close());
    unawaited(_notices.close());
  }
}
