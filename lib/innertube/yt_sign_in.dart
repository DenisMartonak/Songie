import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/log.dart';
import '../ui/settings/yt_sign_in_page.dart';
import 'browser_sign_in.dart';
import 'webkit_sign_in.dart';
import 'yt_session.dart';

/// What a sign-in route hands back: the session (cookies) and, when known,
/// the account's display name.
class YtSignInResult {
  YtSignInResult({required this.session, this.name});
  final YtSession session;
  final String? name;

  @override
  String toString() => 'YtSignInResult($session)';
}

/// One way of signing in to YouTube. [signIn] answers null when the user
/// gave up (closed the page); that is not an error.
abstract class YtSignInRoute {
  String get label;
  Future<bool> supported();
  Future<YtSignInResult?> signIn(BuildContext context);

  /// Forgets anything this route keeps outside secure storage (a web view's
  /// cookies and data). Sign out calls it; a no-op for routes that keep
  /// nothing.
  Future<void> forget();
}

/// Turns a web view's (or browser's) cookies into a [YtSession]: keeps only
/// the unexpired cookies a browser sends to `https://music.youtube.com`
/// (domain `youtube.com`, `.youtube.com` or `music.youtube.com`; R8) whose
/// name and value can go in a `Cookie` header, and needs `SAPISID` or
/// `__Secure-3PAPISID` among them. No google.com cookie of any kind. Never
/// logs a value.
abstract final class YtSessionFromCookies {
  static const _sapisidNames = {'SAPISID', '__Secure-3PAPISID'};

  static String? _domainOf(Cookie c) {
    final d = c.domain?.trim().toLowerCase();
    if (d == null || d.isEmpty) return null;
    return d.startsWith('.') ? d.substring(1) : d;
  }

  /// Whether a cookie set for [host] (a cookie's domain, with or without
  /// the leading dot) is sent to music.youtube.com.
  static bool sentToMusicHost(String? host) {
    final h = host?.trim().toLowerCase();
    if (h == null || h.isEmpty) return false;
    final d = h.startsWith('.') ? h.substring(1) : h;
    return d == 'youtube.com' || d == 'music.youtube.com';
  }

  static bool isYouTube(Cookie c) => sentToMusicHost(_domainOf(c));

  /// Whether [c] has expired by [now]; a session cookie has not.
  ///
  /// Android's cookie manager gives the expiry in milliseconds. Windows'
  /// (WebView2, through the DevTools protocol) gives seconds, and -1 for a
  /// session cookie. Below 10^11 a value can only be seconds: as
  /// milliseconds it would be 1973.
  static bool expired(Cookie c, DateTime now) {
    final raw = c.expiresDate;
    if (raw == null || raw < 0 || c.isSessionOnly == true) return false;
    final ms = raw < 100000000000 ? raw * 1000 : raw;
    return ms <= now.millisecondsSinceEpoch;
  }

  /// Android's cookie manager answers name and value only: those cookies
  /// belong to the [host] they were asked for.
  static List<Cookie> withDomain(List<Cookie> cookies, String host) => [
    for (final c in cookies)
      if (_domainOf(c) == null)
        Cookie(
          name: c.name,
          value: c.value,
          domain: host,
          path: c.path,
          isSecure: c.isSecure,
          isHttpOnly: c.isHttpOnly,
          expiresDate: c.expiresDate,
          isSessionOnly: c.isSessionOnly,
          sameSite: c.sameSite,
        )
      else
        c,
  ];

  /// The cookies that go into a session: sent to music.youtube.com,
  /// unexpired, and with a header-safe name and value.
  static List<Cookie> usable(List<Cookie> cookies, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return [
      for (final c in cookies)
        if (isYouTube(c) &&
            !expired(c, at) &&
            YtSession.validName(c.name) &&
            '${c.value ?? ''}'.isNotEmpty &&
            YtSession.validValue('${c.value}'))
          c,
    ];
  }

  /// Whether the cookies carry a signed-in YouTube session.
  static bool signedIn(List<Cookie> cookies, {DateTime? now}) =>
      usable(cookies, now: now).any((c) => _sapisidNames.contains(c.name));

  static YtSession? build(List<Cookie> cookies, {DateTime? now}) {
    final kept = usable(cookies, now: now);
    if (!kept.any((c) => _sapisidNames.contains(c.name))) return null;
    // `.youtube.com` first, so a music.youtube.com cookie of the same name
    // (the more specific one) wins.
    bool broad(Cookie c) => _domainOf(c) == 'youtube.com';
    return YtSession({
      for (final c in kept.where(broad)) c.name: '${c.value}',
      for (final c in kept.where((c) => !broad(c))) c.name: '${c.value}',
    });
  }
}

/// Google's own sign-in page for YouTube Music, inside Songies (Android
/// WebView, Windows WebView2). The page closes itself once it reaches
/// music.youtube.com signed in; its cookies are then read and the web
/// view's cookies and data cleared, so the session lives only in secure
/// storage.
///
/// The web view's data is also cleared before the page opens (a run that
/// died with the page open leaves it behind) and by [forget] (Sign out).
/// On Windows each sign-in gets its own WebView2 environment, disposed when
/// the page closes, and its user-data folder is then deleted.
///
/// The constructor's hooks replace the platform work in tests.
class WebViewSignIn implements YtSignInRoute {
  WebViewSignIn({
    Future<void> Function()? forgetStored,
    Future<PlatformWebViewEnvironment?> Function()? createEnvironment,
    Future<YtSession?> Function(BuildContext, PlatformWebViewEnvironment?)?
    openPage,
    Future<void> Function(PlatformWebViewEnvironment?)? clearAfter,
  }) : _forgetStored = forgetStored ?? forgetStoredData,
       _createEnvironment = createEnvironment ?? createWindowsEnvironment,
       _openPage = openPage ?? _push,
       _clearAfter = clearAfter ?? clearAfterSignIn;

  final Future<void> Function() _forgetStored;
  final Future<PlatformWebViewEnvironment?> Function() _createEnvironment;
  final Future<YtSession?> Function(BuildContext, PlatformWebViewEnvironment?)
  _openPage;
  final Future<void> Function(PlatformWebViewEnvironment?) _clearAfter;

  static const startUrl =
      'https://accounts.google.com/ServiceLogin?service=youtube'
      '&continue=https://music.youtube.com/';

  /// Where the session cookies are read from: only what a browser sends
  /// to YouTube Music (R8).
  static const youtubeUrl = 'https://music.youtube.com/';

  static const _windowsDataFolder = 'yt_sign_in_webview2';

  static bool isDoneUrl(Uri? url) => url?.host == 'music.youtube.com';

  static Future<Directory> _windowsDataDir() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, _windowsDataFolder),
  );

  /// Windows: a WebView2 environment with its data in Songies' own app-data
  /// folder (next to the executable is often read-only). Null elsewhere.
  static Future<PlatformWebViewEnvironment?> createWindowsEnvironment() async {
    if (kIsWeb || !Platform.isWindows) return null;
    return PlatformWebViewEnvironment.static().create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: (await _windowsDataDir()).path,
      ),
    );
  }

  /// What a sign-in may have left on disk: Android's web view cookies and
  /// storage; Windows' WebView2 user-data folder.
  static Future<void> forgetStoredData() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) await clearWebData(null);
    if (Platform.isWindows) await _deleteWindowsData();
  }

  static Future<void> _deleteWindowsData() async {
    try {
      final dir = await _windowsDataDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      AppLog.w('yt sign-in: could not delete web data (${e.runtimeType})');
    }
  }

  /// After the page closed: clear the web view, dispose the environment and
  /// (Windows) delete its folder.
  static Future<void> clearAfterSignIn(PlatformWebViewEnvironment? env) async {
    await clearWebData(env);
    if (env != null) {
      try {
        await env.dispose();
      } catch (e) {
        AppLog.w('yt sign-in: could not close web view (${e.runtimeType})');
      }
    }
    if (!kIsWeb && Platform.isWindows) await _deleteWindowsData();
  }

  static Future<YtSession?> _push(
    BuildContext context,
    PlatformWebViewEnvironment? env,
  ) => Navigator.of(context).push<YtSession>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => YtSignInPage(
        startUrl: startUrl,
        environment: env,
        readSession: () => readSession(env),
      ),
    ),
  );

  static Future<void> _safe(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      AppLog.w('yt sign-in: $what failed (${e.runtimeType})');
    }
  }

  @override
  String get label => 'Sign in to YouTube';

  @override
  Future<bool> supported() async {
    if (Platform.isAndroid) return true;
    if (Platform.isWindows) {
      try {
        // Null when the WebView2 runtime is not installed.
        return await PlatformWebViewEnvironment.static()
                .getAvailableVersion() !=
            null;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  @override
  Future<void> forget() => _safe('forget', _forgetStored);

  @override
  Future<YtSignInResult?> signIn(BuildContext context) async {
    // A stale account must not sign the page in at once.
    await _safe('clear before', _forgetStored);
    final PlatformWebViewEnvironment? env;
    try {
      env = await _createEnvironment();
    } catch (e) {
      AppLog.w('yt sign-in: web view unavailable (${e.runtimeType})');
      return null;
    }
    try {
      if (!context.mounted) return null;
      final session = await _openPage(context, env);
      AppLog.i('yt sign-in: page closed, signed in: ${session != null}');
      return session == null ? null : YtSignInResult(session: session);
    } finally {
      await _safe('clear after', () => _clearAfter(env));
    }
  }

  /// The session, once the YouTube Music cookies hold one; else null.
  static Future<YtSession?> readSession(PlatformWebViewEnvironment? env) async {
    final yt = YtSessionFromCookies.withDomain(
      await _cookies(env).getCookies(url: WebUri(youtubeUrl)),
      'music.youtube.com',
    );
    return YtSessionFromCookies.build(yt);
  }

  static PlatformCookieManager _cookies(PlatformWebViewEnvironment? env) =>
      PlatformCookieManager(
        PlatformCookieManagerCreationParams(webViewEnvironment: env),
      );

  /// Forgets everything the sign-in page stored: cookies, web storage and
  /// cache. Each step is best effort.
  static Future<void> clearWebData(PlatformWebViewEnvironment? env) async {
    Future<void> step(String what, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        AppLog.w('yt sign-in: could not clear $what (${e.runtimeType})');
      }
    }

    await step('cookies', () => _cookies(env).deleteAllCookies());
    if (Platform.isAndroid) {
      await step(
        'storage',
        () => PlatformWebStorageManager(
          const PlatformWebStorageManagerCreationParams(),
        ).deleteAllData(),
      );
    }
    await step(
      'cache',
      () => PlatformInAppWebViewController.static().clearAllCache(),
    );
  }
}

/// The sign-in routes this platform offers, in order. Linux: Google's page
/// in a WebKitGTK window, then the browser's own sign-in.
List<YtSignInRoute> ytSignInRoutes() {
  if (kIsWeb) return const [];
  if (Platform.isAndroid || Platform.isWindows) return [WebViewSignIn()];
  if (Platform.isLinux) return [WebKitSignIn(), BrowserSignIn()];
  return const [];
}

final ytSignInRoutesProvider = Provider<List<YtSignInRoute>>(
  (ref) => ytSignInRoutes(),
);
