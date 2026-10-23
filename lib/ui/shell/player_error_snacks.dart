import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_service.dart';
import '../../providers.dart';
import '../../youtube/yt_models.dart';
import '../widgets/page_snack_bar.dart';

/// What the user is told for a [PlayerState.error].
String playerErrorMessage(String error) => switch (error) {
  PlayerService.noPlayableFilesError =>
    "Couldn't play — the song files are missing",
  PlayerService.engineFailedError => "Couldn't play these songs",
  _ when error.startsWith('ytdlp:') => ytErrorUserMessageFromText(error),
  _ => error,
};

/// Shows a snack bar whenever the player reports a new error. Wraps the page
/// area of a shell, so the bar clears the shell's own bottom overlays.
class PlayerErrorSnacks extends ConsumerWidget {
  const PlayerErrorSnacks({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select` only reports changes, so later ticks of the same error are quiet.
    ref.listen(playerStateProvider.select((s) => s.value?.error), (_, error) {
      if (error == null) return;
      PageSnackBars.of(context)
        ..clear()
        ..show(content: Text(playerErrorMessage(error)));
    });
    return child;
  }
}
