import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/log.dart';
import 'download_notifier.dart';
import 'download_service.dart';

const _channel = MethodChannel('songies/download_notifier');

/// Shows the queue as an Android notification, held up by a foreground
/// service so downloads survive a switched-off screen. The native side only
/// displays what it is given; the texts are made here.
class AndroidDownloadNotifier implements DownloadNotifier {
  AndroidDownloadNotifier({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const _minGap = Duration(seconds: 1);

  /// Running while a call went out less than [_minGap] ago.
  Timer? _gate;
  DownloadSnapshot? _pending;

  @override
  Future<void> update(DownloadSnapshot s) async {
    // The end of a run is `finished`'s to show.
    if (s.active + s.queued == 0) return;
    if (_gate != null) {
      _pending = s;
      return;
    }
    _startGate();
    await _invoke('update', _payload(s));
  }

  @override
  Future<void> finished(int completed, int failed) async {
    _gate?.cancel();
    _gate = null;
    _pending = null;
    // Nothing came of the run (e.g. its playlist was turned off): clear the
    // progress notification without a "Downloaded 0 songs" summary.
    if (completed + failed == 0) return _invoke('finished', {});
    final songs = completed == 1 ? 'song' : 'songs';
    await _invoke('finished', {
      'text':
          'Downloaded $completed $songs'
          '${failed > 0 ? ' · $failed failed' : ''}',
    });
  }

  void _startGate() {
    _gate = Timer(_minGap, () {
      final next = _pending;
      _pending = null;
      _gate = null;
      if (next != null) unawaited(update(next));
    });
  }

  Map<String, Object?> _payload(DownloadSnapshot s) {
    final pause = s.pause;
    final String text;
    if (pause != null) {
      text = _pausedText(pause);
    } else {
      final title = s.currentTitle;
      text =
          '${s.completedThisRun} of ${s.totalThisRun}'
          '${title == null || title.isEmpty ? '' : ' · $title'}';
    }
    return {
      'title': 'Downloading songs',
      'text': text,
      'progress': s.completedThisRun,
      'max': s.totalThisRun,
    };
  }

  String _pausedText(DownloadPause p) => p.reason == DownloadPauseReason.user
      ? 'Downloads paused'
      : 'Paused — ${downloadPauseText(p, _now())}';

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e, s) {
      AppLog.w('Download notification "$method" failed', e, s);
    }
  }
}

/// Asks for the notification permission (Android 13+ only), at most once per
/// app run. A refusal, or any failure, never blocks downloading.
class NotificationPermissionAsker {
  NotificationPermissionAsker({bool Function()? isAndroid})
    : _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final bool Function() _isAndroid;
  Future<void>? _asked;

  Future<void> ensure() => _asked ??= _ask();

  Future<void> _ask() async {
    if (!_isAndroid()) return;
    try {
      final api = await _channel.invokeMethod<int>('apiLevel');
      if (api == null || api < 33) return;
      await Permission.notification.request();
    } catch (e, s) {
      AppLog.w('Notification permission request failed', e, s);
    }
  }
}

final _asker = NotificationPermissionAsker();

/// Call when the user first enables a download or downloads a song, so the
/// progress notification can show. Never throws; no-op off Android.
Future<void> ensureNotificationPermission() => _asker.ensure();
