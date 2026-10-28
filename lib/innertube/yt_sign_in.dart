import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/log.dart';
import '../ui/settings/yt_sign_in_page.dart';
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
}

/// Turns a web view's cookies into a [YtSession]: keeps only the YouTube
/// (`.youtube.com`) and Google (`.google.com`) cookies, and needs `SAPISID`
/// or `__Secure-3PAPISID` among the YouTube ones. Never logs a value.
abstract final class YtSessionFromCookies {
  static const _sapisidNames = {'SAPISID', '__Secure-3PAPISID'};

  static bool _under(String domain, String site) =>
      domain == site || domain.endsWith('.$site');

  static String? _domainOf(Cookie c) {
    final d = c.domain?.trim().toLowerCase();
    if (d == null || d.isEmpty) return null;
    return d.startsWith('.') ? d.substring(1) : d;
  }

  static bool isYouTube(Cookie c) {
    final d = _domainOf(c);
    return d != null && _under(d, 'youtube.com');
  }

  static bool isGoogle(Cookie c) {
    final d = _domainOf(c);
    return d != null && _under(d, 'google.com');
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

  /// Whether the YouTube cookies carry a signed-in session.
  static bool signedIn(List<Cookie> cookies) => cookies.any(
    (c) =>
        isYouTube(c) &&
        _sapisidNames.contains(c.name) &&
        '${c.value ?? ''}'.isNotEmpty,
  );

  static YtSession? build(List<Cookie> cookies) {
    if (!signedIn(cookies)) return null;
    final out = <String, String>{};
    // Google first, so a YouTube cookie of the same name wins: the session
    // is sent to music.youtube.com.
    for (final keep in [isGoogle, isYouTube]) {
      for (final c in cookies) {
        if (!keep(c)) continue;
        final value = '${c.value ?? ''}';
        if (c.name.isEmpty || value.isEmpty) continue;
        out[c.name] = value;
      }
    }
    return YtSession(out);
  }
}

/// Google's own sign-in page for YouTube Music, inside Songies (Android
/// WebView, Windows WebView2). The page closes itself once it reaches
/// music.youtube.com signed in; its cookies are then read and the web
/// view's cookies and data cleared, so the session lives only in secure
/// storage.
class WebViewSignIn implements YtSignInRoute {
  WebViewSignIn();

  static const startUrl =
      'https://accounts.google.com/ServiceLogin?service=youtube'
      '&continue=https://music.youtube.com/';

  /// Where the session cookies are read from.
  static const youtubeUrl = 'https://music.youtube.com/';
  static const googleUrl = 'https://www.google.com/';

  static bool isDoneUrl(Uri? url) => url?.host == 'music.youtube.com';

  static Future<PlatformWebViewEnvironment?>? _env;

  /// Windows: WebView2 with its data in Songies' own app-data folder (next
  /// to the executable is often read-only). Null elsewhere.
  static Future<PlatformWebViewEnvironment?> environment() =>
      _env ??= _createEnvironment();

  static Future<PlatformWebViewEnvironment?> _createEnvironment() async {
    if (kIsWeb || !Platform.isWindows) return null;
    final support = await getApplicationSupportDirectory();
    return PlatformWebViewEnvironment.static().create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: p.join(support.path, 'yt_sign_in_webview2'),
      ),
    );
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
  Future<YtSignInResult?> signIn(BuildContext context) async {
    final PlatformWebViewEnvironment? env;
    try {
      env = await environment();
    } catch (e) {
      AppLog.w('yt sign-in: web view unavailable (${e.runtimeType})');
      return null;
    }
    if (!context.mounted) return null;
    try {
      final session = await Navigator.of(context).push<YtSession>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => YtSignInPage(
            startUrl: startUrl,
            environment: env,
            readSession: () => readSession(env),
          ),
        ),
      );
      AppLog.i('yt sign-in: page closed, signed in: ${session != null}');
      return session == null ? null : YtSignInResult(session: session);
    } finally {
      await clearWebData(env);
    }
  }

  /// The session, once the YouTube cookies hold one; else null.
  static Future<YtSession?> readSession(PlatformWebViewEnvironment? env) async {
    final cookies = _cookies(env);
    final yt = YtSessionFromCookies.withDomain(
      await cookies.getCookies(url: WebUri(youtubeUrl)),
      'music.youtube.com',
    );
    if (!YtSessionFromCookies.signedIn(yt)) return null;
    final google = YtSessionFromCookies.withDomain(
      await cookies.getCookies(url: WebUri(googleUrl)),
      'www.google.com',
    );
    return YtSessionFromCookies.build([...google, ...yt]);
  }

  /// Forgets everything the sign-in page stored: cookies, web storage and
  /// cache. Each step is best effort.
  static PlatformCookieManager _cookies(PlatformWebViewEnvironment? env) =>
      PlatformCookieManager(
        PlatformCookieManagerCreationParams(webViewEnvironment: env),
      );

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

/// The sign-in routes this platform offers, in order. Linux has none yet.
List<YtSignInRoute> ytSignInRoutes() {
  if (kIsWeb) return const [];
  if (Platform.isAndroid || Platform.isWindows) return [WebViewSignIn()];
  return const [];
}

final ytSignInRoutesProvider = Provider<List<YtSignInRoute>>(
  (ref) => ytSignInRoutes(),
);
