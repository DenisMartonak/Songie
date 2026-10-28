import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import '../../core/log.dart';
import '../../innertube/yt_session.dart';
import '../../innertube/yt_sign_in.dart';
import '../../theme/app_theme.dart';

/// Google's own sign-in page, shown full screen. The user signs in there as
/// on any website; Songies never sees the password. Once the page reaches
/// music.youtube.com with a signed-in session, it closes with that session.
/// Closing it by hand answers null.
class YtSignInPage extends StatefulWidget {
  const YtSignInPage({
    required this.startUrl,
    required this.readSession,
    this.environment,
    super.key,
  });

  final String startUrl;
  final PlatformWebViewEnvironment? environment;

  /// Reads the session from the web view's cookies; null while signed out.
  final Future<YtSession?> Function() readSession;

  @override
  State<YtSignInPage> createState() => _YtSignInPageState();
}

class _YtSignInPageState extends State<YtSignInPage> {
  bool _loading = true;
  bool _done = false;
  bool _checking = false;

  // Made once: a rebuild (the progress bar) must not recreate the web view.
  late final PlatformInAppWebViewWidget _webView = PlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams(
      webViewEnvironment: widget.environment,
      initialUrlRequest: URLRequest(url: WebUri(widget.startUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        supportMultipleWindows: false,
      ),
      onLoadStart: (_, _) {
        if (mounted) setState(() => _loading = true);
      },
      onLoadStop: (_, url) {
        if (mounted) setState(() => _loading = false);
        _check(url);
      },
      onUpdateVisitedHistory: (_, url, _) => _check(url),
    ),
  );

  @override
  void dispose() {
    _webView.dispose();
    super.dispose();
  }

  Future<void> _check(WebUri? url) async {
    if (_done || _checking || !WebViewSignIn.isDoneUrl(url)) return;
    _checking = true;
    try {
      final session = await widget.readSession();
      if (session == null || _done || !mounted) return;
      _done = true;
      Navigator.of(context).pop(session);
    } catch (e) {
      AppLog.w('yt sign-in: could not read the session (${e.runtimeType})');
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SongiesColors>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('ytSignIn.close'),
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Sign in to YouTube',
          style: colors == null ? null : TextStyle(color: colors.text),
        ),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _webView.build(context),
    );
  }
}
