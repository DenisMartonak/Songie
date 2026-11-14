import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// What someone plays now, for the header's "Listening to …" line.
typedef ListeningTo = ({String title, String artist});

/// The top of a profile: the picture, the name, the friend count, the
/// page's [actions], its [menu] and what they listen to now.
///
/// Phone: a top bar with [leading] (Back) on the left and the [menu] on the
/// right, then everything centered in one column, listening last. Wide:
/// [leading] above, the picture on the left with listening under it, the
/// name and count beside it, the actions and the menu at the far right.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    required this.avatar,
    required this.name,
    required this.friendCount,
    required this.actions,
    required this.listening,
    required this.wide,
    this.menu,
    this.leading,
    super.key,
  });

  /// Picture sizes.
  static const double phoneAvatar = 120;
  static const double wideAvatar = 160;

  /// Builds the picture at a size.
  final Widget Function(double size) avatar;
  final String name;

  /// The "N friends" line; null until known.
  final Widget? friendCount;
  final List<Widget> actions;

  /// The ⋯ button: top right on the phone, after [actions] when wide.
  final Widget? menu;

  /// Back, when the page can go back.
  final Widget? leading;

  /// The "Listening to …" block; null when they aren't.
  final Widget? listening;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final title = Text(
      name,
      key: const Key('profile.name'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        color: colors.text,
        fontSize: wide ? 44 : 30,
        fontWeight: FontWeight.w800,
        height: 1.1,
      ),
    );
    final count = friendCount;
    final listen = listening;
    final menu = this.menu;
    final leading = this.leading;
    final buttons = [...actions, ?menu];

    if (wide) {
      final row = Padding(
        padding: EdgeInsets.fromLTRB(24, leading == null ? 40 : 8, 24, 32),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar(wideAvatar),
                  if (listen != null) ...[const SizedBox(height: 16), listen],
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: SizedBox(
                height: wideAvatar,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (count != null) ...[const SizedBox(height: 8), count],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: wideAvatar,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, a) in buttons.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    a,
                  ],
                ],
              ),
            ),
          ],
        ),
      );
      if (leading == null) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
            child: Align(alignment: Alignment.centerLeft, child: leading),
          ),
          row,
        ],
      );
    }

    final bar = leading != null || menu != null;
    final column = Padding(
      padding: EdgeInsets.fromLTRB(16, bar ? 4 : 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar(phoneAvatar),
          const SizedBox(height: 16),
          title,
          if (count != null) ...[const SizedBox(height: 6), count],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
          if (listen != null) ...[const SizedBox(height: 20), listen],
        ],
      ),
    );
    if (!bar) return column;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: SizedBox(
            height: 48,
            child: Row(children: [?leading, const Spacer(), ?menu]),
          ),
        ),
        column,
      ],
    );
  }
}

/// "Listening to `title` · `artist`", with Join while they host a room.
class ProfileListening extends StatelessWidget {
  const ProfileListening({
    required this.song,
    required this.wide,
    this.onJoin,
    super.key,
  });

  final ListeningTo song;
  final bool wide;

  /// Joins their room; null when they host none.
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>()!;
    final join = onJoin;
    return Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          key: const Key('profile.listening'),
          TextSpan(
            children: [
              const TextSpan(text: 'Listening to '),
              TextSpan(
                text: song.title,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: ' · ${song.artist}'),
            ],
          ),
          maxLines: wide ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: TextStyle(color: colors.mutedText, fontSize: 14),
        ),
        if (join != null) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            key: const Key('profile.join'),
            onPressed: join,
            icon: const Icon(Icons.headphones_rounded),
            label: const Text('Join'),
          ),
        ],
      ],
    );
  }
}
