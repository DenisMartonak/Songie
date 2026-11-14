import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/account_service.dart';
import '../../friends/friends_backend.dart';
import '../../friends/friends_service.dart';
import '../../providers.dart';
import '../../stats/stats_models.dart';
import '../../theme/app_theme.dart';
import '../account/avatar.dart';
import '../friends/friend_dot.dart';
import '../room/join_room_dialog.dart' show joinRoomAsking;
import 'profile_header.dart';
import 'profile_stats.dart';

/// Whose profile a [ProfileView] shows.
sealed class ProfileSource {
  const ProfileSource();
}

/// The signed-in account's own profile.
class MyProfile extends ProfileSource {
  const MyProfile();
}

/// A friend's profile.
class FriendProfile extends ProfileSource {
  const FriendProfile(this.userId);

  final String userId;
}

/// "Updated 2 weeks ago" for a friend's summary worked out on day [at]
/// (local), as of [now]; null while it is from today.
String? profileUpdatedText(DateTime at, DateTime now) {
  // Calendar days, in UTC so a clock change doesn't shift them.
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
  if (days < 1) return null;
  String n(int count, String unit) =>
      count == 1 ? '1 $unit ago' : '$count ${unit}s ago';
  final ago = switch (days) {
    1 => 'yesterday',
    < 7 => n(days, 'day'),
    < 30 => n(days ~/ 7, 'week'),
    _ => n(days ~/ 30, 'month'),
  };
  return 'Updated $ago';
}

/// A profile, yours or a friend's: a header (picture, name, friend count,
/// the page's [actions], what they listen to now) over their stats. The
/// wide layout is used from [wideBreakpoint] of its own width. It scrolls
/// over the whole width (the scrollbar at the window edge) with the
/// content centered.
class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({required this.source, required this.actions, super.key});

  static const double wideBreakpoint = 840;

  /// Content widths.
  static const double phoneMaxWidth = 720;
  static const double wideMaxWidth = 1200;

  final ProfileSource source;

  /// The header's buttons (Edit profile, ⋯), supplied by the page.
  final List<Widget> actions;

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  /// A friend's chosen period; yours is [statsPeriodProvider].
  StatsPeriod _friendPeriod = StatsPeriod.month;

  /// The friend last found, kept while they leave the list (as the page
  /// pops after Remove friend).
  FriendUser? _friend;

  FriendsService? _service;
  Object? _watch;

  @override
  void initState() {
    super.initState();
    switch (widget.source) {
      case MyProfile():
        unawaited(_fillPhotos());
      case FriendProfile():
        // Keeps their listening fresh while the view is open.
        final service = ref.read(friendsServiceProvider);
        _service = service;
        _watch = service.watchClosely();
        unawaited(service.refresh().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    if (_watch case final watch?) _service?.stopWatching(watch);
    super.dispose();
  }

  /// Reads the kept artist photos, then looks up the missing ones for the
  /// stats first shown (at most once an hour, see [ArtistPhotos.fill]).
  Future<void> _fillPhotos() async {
    final photos = ref.read(artistPhotosProvider);
    await photos.load();
    if (!mounted) return;
    // The rows read the kept photos when they build.
    setState(() {});
    final period = ref.read(statsPeriodProvider);
    final done = Completer<PeriodStats>();
    final sub = ref.listenManual(periodStatsProvider(period), (_, next) {
      if (next.value case final s? when !done.isCompleted) done.complete(s);
    }, fireImmediately: true);
    try {
      final stats = await done.future;
      await photos.fill(stats.topArtists);
    } catch (_) {
      // Photos are a nicety.
    } finally {
      sub.close();
    }
  }

  Future<void> _join(String code) async {
    final container = ProviderScope.containerOf(context);
    await joinRoomAsking(context, container, code);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= ProfileView.wideBreakpoint;
        final content = switch (widget.source) {
          MyProfile() => _mine(wide),
          FriendProfile(:final userId) => _friendOf(userId, wide),
        };
        final maxWidth = wide
            ? ProfileView.wideMaxWidth
            : ProfileView.phoneMaxWidth;
        Widget centered(Widget child) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Glow(
                wide: wide,
                // Where the picture's center falls across the window.
                avatarX: wide
                    ? (width - math.min(width, maxWidth)) / 2 +
                          24 +
                          ProfileHeader.wideAvatar / 2
                    : width / 2,
                width: width,
                child: centered(content.header),
              ),
              centered(content.body),
            ],
          ),
        );
      },
    );
  }

  /// Your own profile.
  ({Widget header, Widget body}) _mine(bool wide) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final account = ref.watch(accountStateProvider).value;
    final name = account is SignedIn ? account.profile.username : '';
    final friends = ref.watch(friendsStateProvider).value;
    final player = ref.watch(
      playerStateProvider.select((s) {
        final v = s.value;
        final t = v?.current;
        return v != null && v.playing && t != null
            ? (title: t.title, artist: t.artist)
            : null;
      }),
    );
    final period = ref.watch(statsPeriodProvider);
    final stats = ref.watch(periodStatsProvider(period)).value;

    Widget? count;
    if (friends != null && friends.loaded) {
      count = InkWell(
        onTap: () => context.push('/profile/friends'),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CountText(friends.friends.length, colors: colors),
              const SizedBox(width: 6),
              const FriendDot(),
            ],
          ),
        ),
      );
    }

    return (
      header: ProfileHeader(
        avatar: (size) => AccountAvatar(size: size),
        name: name,
        friendCount: count,
        actions: widget.actions,
        listening: player == null
            ? null
            : ProfileListening(song: player, wide: wide),
        wide: wide,
      ),
      body: ProfileStats(
        stats: stats,
        period: period,
        onPeriod: ref.read(statsPeriodProvider.notifier).select,
        wide: wide,
        mine: true,
      ),
    );
  }

  /// A friend's profile.
  ({Widget header, Widget body}) _friendOf(String userId, bool wide) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final state = ref.watch(friendsStateProvider).value ?? FriendsState.empty;
    for (final u in state.friends) {
      if (u.id == userId) _friend = u;
    }
    final user = _friend;
    if (user == null) {
      return (
        header: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            state.loaded ? 'Not in your friends' : '',
            key: const Key('profile.notFriend'),
            style: TextStyle(color: colors.mutedText),
          ),
        ),
        body: const SizedBox.shrink(),
      );
    }

    final count = ref.watch(friendCountProvider(userId)).value;
    final activity = state.activity[userId];
    final now = ref.read(nowProvider)();
    final listening = state.listening(userId, now) ? activity : null;
    final song = listening?.nowPlaying;
    final code = listening?.roomCode;

    final side = wide ? 24.0 : 16.0;
    Widget message(String key, String text) => Padding(
      padding: EdgeInsets.symmetric(horizontal: side, vertical: 8),
      child: Text(
        text,
        key: Key(key),
        textAlign: wide ? TextAlign.start : TextAlign.center,
        style: TextStyle(color: colors.mutedText, fontSize: 15),
      ),
    );

    final summary = activity?.stats;
    final Widget body;
    if (activity != null && !activity.sharesStats) {
      body = message(
        'profile.noShare',
        "${user.username} doesn't share their stats",
      );
    } else if (summary == null || summary.periods.isEmpty) {
      body = message('profile.noStats', 'No stats from ${user.username} yet');
    } else {
      final period = summary.legacy ? StatsPeriod.month : _friendPeriod;
      body = ProfileStats(
        stats: summary.periods[period],
        period: period,
        onPeriod: summary.legacy
            ? null
            : (p) => setState(() => _friendPeriod = p),
        wide: wide,
        mine: false,
        note: profileUpdatedText(summary.at, now),
        noteKey: const Key('profile.updated'),
      );
    }

    return (
      header: ProfileHeader(
        avatar: (size) =>
            PersonAvatar(name: user.username, url: user.avatarUrl, size: size),
        name: user.username,
        friendCount: count == null ? null : _CountText(count, colors: colors),
        actions: widget.actions,
        listening: song == null
            ? null
            : ProfileListening(
                song: (title: song.title, artist: song.artist),
                wide: wide,
                onJoin: code == null ? null : () => _join(code),
              ),
        wide: wide,
      ),
      body: body,
    );
  }
}

/// "**86** friends".
class _CountText extends StatelessWidget {
  const _CountText(this.count, {required this.colors});

  final int count;
  final SongiesColors colors;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      key: const Key('profile.friendCount'),
      TextSpan(
        children: [
          TextSpan(
            text: '$count',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: count == 1 ? ' friend' : ' friends'),
        ],
      ),
      style: TextStyle(color: colors.mutedText, fontSize: 16),
    );
  }
}

/// The accent's soft glow behind the header, centered on the picture.
class _Glow extends StatelessWidget {
  const _Glow({
    required this.wide,
    required this.avatarX,
    required this.width,
    required this.child,
  });

  final bool wide;

  /// The picture's center from the left edge, in pixels.
  final double avatarX;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final x = width <= 0 ? 0.0 : avatarX / (width / 2) - 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(x, wide ? -0.1 : -0.45),
          radius: wide ? 1.4 : 0.9,
          colors: [
            primary.withValues(alpha: 0.18),
            primary.withValues(alpha: 0),
          ],
        ),
      ),
      child: child,
    );
  }
}
