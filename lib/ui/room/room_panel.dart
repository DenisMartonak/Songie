import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_service.dart';
import '../../core/log.dart';
import '../../providers.dart';
import '../../room/room_links.dart';
import '../../room/room_protocol.dart';
import '../../room/room_service.dart';
import '../../theme/app_theme.dart';
import '../../youtube/share_intents.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../shell/adaptive_shell.dart' show phoneBreakpoint;
import 'join_room_dialog.dart';

/// Opens the room panel: a popup dialog on desktop, a sheet that slides up
/// on a phone.
Future<void> showRoomPanel(BuildContext context, WidgetRef ref) {
  if (MediaQuery.sizeOf(context).width < phoneBreakpoint) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheet) => Padding(
        // Clear of the keyboard while a code is typed.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: const RoomPanel(key: Key('room.sheet')),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: const RoomPanel(key: Key('room.popup')),
      ),
    ),
  );
}

/// The label of [role] in the panel.
String roomRoleLabel(RoomRole role) => switch (role) {
  RoomRole.listener => 'Listener',
  RoomRole.queue => 'Queue',
  RoomRole.full => 'Full control',
};

bool _isPhone(RoomPresence p) => p.platform == 'android' || p.platform == 'ios';

/// Listen together: start or join a room; while hosting, the link, the
/// people and their roles, and End room; while a guest, everyone's role and
/// Leave.
class RoomPanel extends ConsumerStatefulWidget {
  const RoomPanel({super.key});

  @override
  ConsumerState<RoomPanel> createState() => _RoomPanelState();
}

class _RoomPanelState extends ConsumerState<RoomPanel> {
  final _code = TextEditingController();
  String? _codeError;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(SignedIn account) => _run(() async {
    try {
      await ref
          .read(roomServiceProvider)
          .open(
            userId: account.profile.id,
            name: account.profile.username,
            avatarUrl: account.profile.avatarUrl,
          );
    } on StateError catch (e, s) {
      AppLog.w('room: open skipped', e, s);
    }
  });

  Future<void> _join() async {
    final code = parseRoomCode(_code.text);
    if (code == null) {
      setState(() => _codeError = 'Not a room code or link');
      return;
    }
    setState(() => _codeError = null);
    final container = ProviderScope.containerOf(context);
    await _run(() => joinRoomAsking(context, container, code));
  }

  void _signIn() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/profile');
  }

  Future<void> _copy(String link) async {
    final islands = Islands.of(context);
    await Clipboard.setData(ClipboardData(text: link));
    islands.show('Link copied', kind: IslandKind.success);
  }

  Future<void> _share(String link) async {
    try {
      await shareText(link);
    } on Object catch (e, s) {
      AppLog.w('room: sharing the link failed', e, s);
    }
  }

  Future<void> _remove(RoomPresence p) async {
    final yes = await confirmRoomStep(
      context,
      title: 'Remove ${p.name}?',
      body: '${p.name} stops listening with the room.',
      confirm: 'Remove',
    );
    if (yes) await ref.read(roomServiceProvider).remove(p);
  }

  Future<void> _end() async {
    final yes = await confirmRoomStep(
      context,
      title: 'End the room?',
      body: 'Everyone in it stops listening together.',
      confirm: 'End room',
    );
    if (yes) await ref.read(roomServiceProvider).end();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final status =
        ref.watch(roomStatusProvider).value ??
        ref.read(roomServiceProvider).status;
    final account = ref.watch(accountStateProvider).value;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.group_rounded, color: colors.accent),
              const SizedBox(width: 10),
              Text(
                'Listen together',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...switch (status) {
            RoomHosting() => _hosting(status, colors),
            RoomGuesting() => _guesting(status, colors),
            RoomIdle() =>
              account is SignedIn ? _idle(account, colors) : _signedOut(colors),
          },
        ],
      ),
    );
  }

  List<Widget> _signedOut(SongiesColors colors) => [
    Text(kRoomSignInText, style: TextStyle(color: colors.text)),
    const SizedBox(height: 16),
    Align(
      alignment: Alignment.centerLeft,
      child: FilledButton(onPressed: _signIn, child: const Text('Sign in')),
    ),
  ];

  List<Widget> _idle(SignedIn account, SongiesColors colors) => [
    Text(
      'Play the same music, in step, with friends on their own devices.',
      style: TextStyle(color: colors.mutedText),
    ),
    const SizedBox(height: 16),
    Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: _busy ? null : () => _start(account),
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('Start a room'),
      ),
    ),
    const SizedBox(height: 20),
    Divider(color: colors.text.withAlpha(30)),
    const SizedBox(height: 12),
    TextField(
      key: const Key('room.joinField'),
      controller: _code,
      enabled: !_busy,
      textInputAction: TextInputAction.go,
      onSubmitted: (_) => _join(),
      decoration: InputDecoration(
        hintText: 'Code or link',
        errorText: _codeError,
      ),
    ),
    const SizedBox(height: 12),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(
        onPressed: _busy ? null : _join,
        child: const Text('Join a room'),
      ),
    ),
  ];

  List<Widget> _hosting(RoomHosting s, SongiesColors colors) {
    final phone = ref.watch(isAndroidProvider);
    return [
      Text(
        s.link,
        style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
      ),
      Text(
        'Code ${formatRoomCode(s.code)}',
        style: TextStyle(color: colors.mutedText, fontSize: 13),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (phone)
            FilledButton.icon(
              onPressed: () => _share(s.link),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share link'),
            ),
          OutlinedButton.icon(
            onPressed: () => _copy(s.link),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      ..._people(s.people, s.roles, colors, manage: true),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(onPressed: _end, child: const Text('End room')),
      ),
    ];
  }

  List<Widget> _guesting(RoomGuesting s, SongiesColors colors) => [
    ..._people(
      // The host first, then everyone else as Presence lists them.
      [s.host, ...s.people.where((p) => p.deviceId != s.host.deviceId)],
      s.roles,
      colors,
      manage: false,
    ),
    const SizedBox(height: 16),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(
        onPressed: _busy
            ? null
            : () => _run(() => ref.read(roomServiceProvider).leave()),
        child: const Text('Leave'),
      ),
    ),
  ];

  List<Widget> _people(
    List<RoomPresence> people,
    Map<String, RoomRole> roles,
    SongiesColors colors, {
    required bool manage,
  }) => [
    Text(
      'People',
      style: TextStyle(
        color: colors.mutedText,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
    const SizedBox(height: 4),
    for (final p in people)
      _PersonRow(
        key: Key('room.person.${p.deviceId}'),
        person: p,
        trailing: p.host
            ? Text('Host', style: TextStyle(color: colors.mutedText))
            : manage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RoleMenu(
                    person: p,
                    role: roles[p.deviceId] ?? RoomRole.listener,
                  ),
                  IconButton(
                    key: Key('room.remove.${p.deviceId}'),
                    tooltip: 'Remove from the room',
                    iconSize: 20,
                    color: colors.mutedText,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _remove(p),
                  ),
                ],
              )
            : Text(
                roomRoleLabel(roles[p.deviceId] ?? RoomRole.listener),
                style: TextStyle(color: colors.mutedText),
              ),
      ),
  ];
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.trailing, super.key});

  final RoomPresence person;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final phone = _isPhone(person);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            phone ? Icons.smartphone_rounded : Icons.computer_rounded,
            size: 20,
            color: colors.mutedText,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  phone ? 'Phone' : 'Desktop',
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// The host's menu of a guest's role.
class _RoleMenu extends ConsumerWidget {
  const _RoleMenu({required this.person, required this.role});

  final RoomPresence person;
  final RoomRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    return PopupMenuButton<RoomRole>(
      key: Key('room.role.${person.deviceId}'),
      tooltip: 'Role',
      initialValue: role,
      color: colors.surface,
      onSelected: (r) =>
          unawaited(ref.read(roomServiceProvider).setRole(person.deviceId, r)),
      itemBuilder: (_) => [
        for (final r in RoomRole.values)
          PopupMenuItem(
            value: r,
            child: Text(roomRoleLabel(r), style: TextStyle(color: colors.text)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(roomRoleLabel(role), style: TextStyle(color: colors.text)),
            Icon(Icons.arrow_drop_down_rounded, color: colors.mutedText),
          ],
        ),
      ),
    );
  }
}
