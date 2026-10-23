import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_service.dart';
import '../../providers.dart';
import '../../youtube/yt_models.dart';
import '../widgets/page_snack_bar.dart';

/// What the user is told for a [PlayerState.error]. [notice] supplies the last
/// failure's reason for [PlayerService.tooManyFailuresError].
String playerErrorMessage(String error, {PlayerNotice? notice}) =>
    switch (error) {
      PlayerService.noPlayableFilesError =>
        "Couldn't play — the song files are missing",
      PlayerService.engineFailedError => "Couldn't play these songs",
      PlayerService.tooManyFailuresError =>
        "Stopped — ${PlayerService.maxConsecutiveSkips} songs in a row "
            "couldn't play."
            '${notice == null ? '' : ' ${skipReasonMessage(notice.reason)}'}',
      _ when error.startsWith('ytdlp:') => ytErrorUserMessageFromText(error),
      _ => error,
    };

/// User copy for a [PlayerNotice.reason].
String skipReasonMessage(String reason) => switch (reason) {
  PlayerService.fileMissingReason => 'file is missing',
  PlayerService.playbackFailedError => "it couldn't be played",
  _ when reason.startsWith('ytdlp:') => ytErrorUserMessageFromText(reason),
  _ => reason,
};

/// What the user is told when a song was skipped.
String playerNoticeMessage(PlayerNotice notice) =>
    "Skipped '${notice.trackTitle}' — ${skipReasonMessage(notice.reason)}";

/// Shows a snack bar whenever the player reports a new error or skips a song.
/// Wraps the page area of a shell, so the bar clears the shell's own bottom
/// overlays.
class PlayerErrorSnacks extends ConsumerWidget {
  const PlayerErrorSnacks({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select` only reports changes, so later ticks of the same error are quiet.
    // An error and a notice that arrive together show as the error alone.
    ref.listen(
      playerStateProvider.select((s) => (s.value?.error, s.value?.notice)),
      (previous, next) {
        final (error, notice) = next;
        final String message;
        if (error != null && error != previous?.$1) {
          message = playerErrorMessage(error, notice: notice);
        } else if (notice != null && !identical(notice, previous?.$2)) {
          message = playerNoticeMessage(notice);
        } else {
          return;
        }
        PageSnackBars.of(context)
          ..clear()
          ..show(content: Text(message));
      },
    );
    return child;
  }
}
