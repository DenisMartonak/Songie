import 'dart:async';
import 'dart:io' show Platform;

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart'
    show Cookie;

import '../core/log.dart';
import 'yt_session.dart';
import 'yt_sign_in.dart';

/// Linux: Google's sign-in page for YouTube Music in its own WebKitGTK
/// window (`desktop_webview_window`). When the window reaches
/// music.youtube.com and its cookies hold a signed-in session, the cookies
/// are read and the window closes; closing it by hand gives up.
///
/// The web data (cookies, storage, cache) is cleared before the window
/// opens, after it closes and by [forget] (Sign out), so the session lives
/// only in secure storage. Watching the window's navigation is event-driven:
/// nothing polls.
///
/// The constructor's hooks replace the native window in tests.
class WebKitSignIn implements YtSignInRoute {
  WebKitSignIn({
    Future<YtSession?> Function()? openWindow,
    Future<void> Function()? clear,
  }) : _openWindow = openWindow ?? _open,
       _clear = clear ?? WebviewWindow.clearAll;

  final Future<YtSession?> Function() _openWindow;
  final Future<void> Function() _clear;

  @override
  String get label => 'Sign in to YouTube';

  @override
  Future<bool> supported() async => !kIsWeb && Platform.isLinux;

  Future<void> _safe(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      AppLog.w('yt sign-in: $what failed (${e.runtimeType})');
    }
  }

  @override
  Future<void> forget() => _safe('forget', _clear);

  @override
  Future<YtSignInResult?> signIn(BuildContext context) async {
    // A stale account must not sign the page in at once.
    await _safe('clear before', _clear);
    try {
      final session = await _openWindow();
      AppLog.i('yt sign-in: window closed, signed in: ${session != null}');
      return session == null ? null : YtSignInResult(session: session);
    } catch (e) {
      AppLog.w('yt sign-in: web view unavailable (${e.runtimeType})');
      return null;
    } finally {
      await _safe('clear after', _clear);
    }
  }

  /// The session in a window's cookies, or null when signed out.
  static YtSession? sessionFrom(List<WebviewCookie> cookies) =>
      YtSessionFromCookies.build([
        for (final c in cookies)
          Cookie(
            name: c.name,
            value: c.value,
            domain: c.domain,
            path: c.path,
            isSecure: c.secure,
            isHttpOnly: c.httpOnly,
          ),
      ]);

  static Future<YtSession?> _open() async {
    final window = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        title: 'Sign in to YouTube',
        windowWidth: 480,
        windowHeight: 720,
      ),
    );
    final done = Completer<YtSession?>();
    unawaited(
      window.onClose.then((_) {
        if (!done.isCompleted) done.complete(null);
      }),
    );
    var reading = false;
    Future<void> check() async {
      final state = window.navigationState.value;
      if (done.isCompleted || reading || state.isLoading) return;
      if (!WebViewSignIn.isDoneUrl(Uri.tryParse(state.url ?? ''))) return;
      reading = true;
      try {
        final session = sessionFrom(await window.getAllCookies());
        if (session != null && !done.isCompleted) {
          done.complete(session);
          await window.close();
        }
      } catch (e) {
        AppLog.w('yt sign-in: could not read cookies (${e.runtimeType})');
      } finally {
        reading = false;
      }
    }

    window.navigationState.addListener(check);
    try {
      await window.launch(WebViewSignIn.startUrl);
      return await done.future;
    } finally {
      window.navigationState.removeListener(check);
    }
  }
}
