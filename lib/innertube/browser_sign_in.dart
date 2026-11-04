import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show Cookie;

import '../core/log.dart';
import '../core/result.dart';
import '../ui/island/island_controller.dart';
import '../ui/island/island_host.dart';
import 'browser_cookies.dart';
import 'yt_sign_in.dart';

/// Linux: "Use the YouTube sign-in from my browser". Asks first, then
/// lists the browser profiles found by path (nothing opened), and reads
/// (for Chromium, decrypts) only the one profile the user picks (ruling R7).
/// A profile without a YouTube sign-in says so and the list comes back.
///
/// It keeps nothing of its own: the session goes to the keyring through
/// `YtAuth.signIn`, so [forget] has nothing to do.
///
/// The constructor's hooks replace the file and keyring work in tests.
class BrowserSignIn implements YtSignInRoute {
  BrowserSignIn({
    String? home,
    Future<List<BrowserProfile>> Function()? findProfiles,
    Future<Result<List<Cookie>>> Function(BrowserProfile)? readCookies,
  }) : _findProfiles = findProfiles ?? (() => findBrowserProfiles(home: home)),
       _readCookies = readCookies ?? readBrowserCookies;

  final Future<List<BrowserProfile>> Function() _findProfiles;
  final Future<Result<List<Cookie>>> Function(BrowserProfile) _readCookies;

  @override
  String get label => 'Use the YouTube sign-in from my browser';

  /// Offered when any browser profile with a cookie database is there.
  /// Only file names are checked: nothing is opened, no keyring.
  @override
  Future<bool> supported() async {
    try {
      return (await _findProfiles()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> forget() async {}

  @override
  Future<YtSignInResult?> signIn(BuildContext context) async {
    final islands = Islands.of(context);
    if (!await _ask(context) || !context.mounted) return null;
    final profiles = await _findProfiles();
    if (!context.mounted) return null;
    if (profiles.isEmpty) {
      islands.show('No browser profile found', kind: IslandKind.failure);
      return null;
    }
    while (true) {
      if (!context.mounted) return null;
      final picked = await _pick(context, profiles);
      if (picked == null || !context.mounted) return null;
      final result = await _readCookies(picked);
      switch (result) {
        case Err(:final failure):
          // The failure's message is plain and names only the browser.
          islands.show(failure.message, kind: IslandKind.failure);
          return null;
        case Ok(:final value):
          final session = YtSessionFromCookies.build(value);
          AppLog.i(
            'yt sign-in: browser cookies read, signed in: '
            '${session != null}',
          );
          if (session != null) return YtSignInResult(session: session);
          islands.show(
            "${picked.browser} (${picked.profile}) isn't signed in to "
            'YouTube',
          );
      }
    }
  }

  Future<bool> _ask(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Use your browser's YouTube sign-in?"),
        content: const Text(
          'Pick a browser next. Songies then copies only its YouTube and '
          'Google cookies and keeps them in the keyring. For Chrome or '
          'Chromium, the keyring may ask to be unlocked. Signing out of '
          'YouTube in the browser signs Songies out too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('browserSignIn.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<BrowserProfile?> _pick(
    BuildContext context,
    List<BrowserProfile> profiles,
  ) => showDialog<BrowserProfile>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Which browser?'),
      children: [
        for (final (i, p) in profiles.indexed)
          SimpleDialogOption(
            key: Key('browserSignIn.profile.$i'),
            onPressed: () => Navigator.of(context).pop(p),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.browser),
              subtitle: Text('Profile: ${p.profile}'),
            ),
          ),
      ],
    ),
  );
}
