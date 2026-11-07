import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result.dart';
import '../../player/player_service.dart';
import '../../providers.dart';
import '../../youtube/yt_models.dart';
import '../island/island_controller.dart';
import '../island/island_host.dart';
import '../remote/remote_islands.dart';

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

/// Whether [reason] is an age-restricted song that signing in (again) can
/// make playable.
bool _needsSignIn(String reason) =>
    switch (ytErrorKindOf(Failure(FailureKind.unknown, reason))) {
      YtErrorKind.ageRestricted || YtErrorKind.ageRestrictedAccount => true,
      _ => false,
    };

/// Shows an island whenever the player reports a new error or skips a song
/// (and, through [RemoteEndedIslands], when a remote link ends).
class PlayerErrorIslands extends ConsumerWidget {
  const PlayerErrorIslands({required this.child, super.key});

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
        final String reason;
        if (error != null && error != previous?.$1) {
          message = playerErrorMessage(error, notice: notice);
          reason = error;
        } else if (notice != null && !identical(notice, previous?.$2)) {
          message = playerNoticeMessage(notice);
          reason = notice.reason;
        } else {
          return;
        }
        // Looked up now: the island can outlive this widget (the shell is
        // rebuilt when the window crosses the phone width).
        final router = _needsSignIn(reason) ? GoRouter.maybeOf(context) : null;
        Islands.of(context).show(
          message,
          kind: IslandKind.failure,
          action: router != null
              ? IslandAction(
                  label: 'Sign in',
                  onPressed: () => router.go('/settings'),
                )
              : null,
        );
      },
    );
    // The same single host tells when a remote link ends.
    return RemoteEndedIslands(child: child);
  }
}
