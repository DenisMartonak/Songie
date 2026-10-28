import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show Cookie;

import '../core/log.dart';
import '../core/result.dart';
import '../ui/widgets/page_snack_bar.dart';
import 'browser_cookies.dart';
import 'yt_sign_in.dart';

/// Linux: "Use the YouTube sign-in from my browser". Lists the browser
/// profiles that hold a YouTube sign-in, lets the user pick one and
/// confirm, and only then reads (and, for Chromium, decrypts) that
/// profile's YouTube/Google cookies.
///
/// It keeps nothing of its own: the session goes to the keyring through
/// `YtAuth.signIn`, so [forget] has nothing to do.
///
/// The constructor's hooks replace the file and keyring work in tests.
class BrowserSignIn implements YtSignInRoute {
  BrowserSignIn({
    String? home,
    Future<List<BrowserProfile>> Function()? findProfiles,
    Future<bool> Function(BrowserProfile)? hasSession,
    Future<Result<List<Cookie>>> Function(BrowserProfile)? readCookies,
  }) : _findProfiles = findProfiles ?? (() => findBrowserProfiles(home: home)),
       _hasSession = hasSession ?? hasYouTubeSession,
       _readCookies = readCookies ?? readBrowserCookies;

  final Future<List<BrowserProfile>> Function() _findProfiles;
  final Future<bool> Function(BrowserProfile) _hasSession;
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
    final snacks = PageSnackBars.of(context);
    final profiles = <BrowserProfile>[];
    for (final p in await _findProfiles()) {
      if (await _hasSession(p)) profiles.add(p);
    }
    if (!context.mounted) return null;
    if (profiles.isEmpty) {
      snacks.show(
        content: const Text(
          'No browser here is signed in to YouTube. Sign in to YouTube in '
          'your browser, then try again.',
        ),
      );
      return null;
    }
    final picked = profiles.length == 1
        ? profiles.single
        : await _pick(context, profiles);
    if (picked == null || !context.mounted) return null;
    if (!await _confirm(context, picked)) return null;

    final result = await _readCookies(picked);
    switch (result) {
      case Err(:final failure):
        // The failure's message is plain and names only the browser.
        snacks.show(content: Text(failure.message));
        return null;
      case Ok(:final value):
        final session = YtSessionFromCookies.build(value);
        AppLog.i(
          'yt sign-in: browser cookies read, signed in: '
          '${session != null}',
        );
        if (session == null) {
          snacks.show(
            content: Text('${picked.browser} is not signed in to YouTube'),
          );
          return null;
        }
        return YtSignInResult(session: session);
    }
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

  Future<bool> _confirm(BuildContext context, BrowserProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Use ${p.browser}'s YouTube sign-in?"),
        content: Text(
          'Songies copies only the YouTube and Google cookies from this '
          'profile (${p.profile}) and keeps them in the keyring. '
          '${p.isFirefox ? '' : 'Your keyring may ask to be unlocked. '}'
          'Signing out of YouTube in the browser signs Songies out too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('browserSignIn.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use this sign-in'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
