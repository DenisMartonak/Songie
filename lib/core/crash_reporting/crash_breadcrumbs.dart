import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../player/player_service.dart';

/// A position jump bigger than this (or any jump back) is a seek; ticks
/// arrive every 200 ms.
const _seekForward = Duration(seconds: 2);
const _seekBack = Duration(seconds: 1);

/// The route template go_router matched (such as `/playlist/:id`), never the
/// location with its ids.
String routeTemplate(String matchedFullPath) =>
    matchedFullPath.isEmpty ? '/' : matchedFullPath;

/// Adds a navigation breadcrumb for [template] while Sentry is running.
void recordRoute(String template) {
  if (!Sentry.isEnabled) return;
  Sentry.addBreadcrumb(
    Breadcrumb(category: 'navigation', type: 'navigation', message: template),
  );
}

/// What happened between two player states, from a fixed set of words: play,
/// pause, next, previous, seek and track change. Never titles or ids.
List<String> playerEvents(PlayerState previous, PlayerState next) {
  final before = previous.current;
  final after = next.current;
  final events = <String>[];
  if (after != null && before?.id != after.id) {
    final sameQueue = identical(previous.queue, next.queue);
    if (sameQueue && next.index == previous.index + 1) {
      events.add('next');
    } else if (sameQueue && next.index == previous.index - 1) {
      events.add('previous');
    } else {
      events.add('track change');
    }
  } else if (after != null) {
    final moved = next.position - previous.position;
    if (moved > _seekForward || moved < -_seekBack) events.add('seek');
  }
  if (!previous.playing && next.playing) events.add('play');
  if (previous.playing && !next.playing) events.add('pause');
  return events;
}

/// Adds a player breadcrumb for each of [playerEvents] while Sentry is
/// running.
void recordPlayer(PlayerState previous, PlayerState next) {
  if (!Sentry.isEnabled) return;
  for (final e in playerEvents(previous, next)) {
    Sentry.addBreadcrumb(Breadcrumb(category: 'player', message: e));
  }
}

/// Records the route template each time [router] moves to a different one
/// (pushed pages included). Returns a function that stops listening.
VoidCallback followRoutes(
  GoRouter router, {
  void Function(String template) record = recordRoute,
}) {
  String? last;
  void onChange() {
    final template = routeTemplate(router.state.fullPath ?? '');
    if (template == last) return;
    last = template;
    record(template);
  }

  router.routerDelegate.addListener(onChange);
  return () => router.routerDelegate.removeListener(onChange);
}

/// Records what changes between consecutive player [states].
StreamSubscription<PlayerState> followPlayer(
  Stream<PlayerState> states, {
  void Function(PlayerState previous, PlayerState next) record = recordPlayer,
}) {
  var previous = const PlayerState();
  return states.listen((s) {
    record(previous, s);
    previous = s;
  });
}
