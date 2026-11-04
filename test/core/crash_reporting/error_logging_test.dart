import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/core/log.dart';

void main() {
  test(
    'an uncaught error is still written to the log with Sentry installed',
    () async {
      final dir = await Directory.systemTemp.createTemp('songies_log_');
      addTearDown(() => dir.delete(recursive: true));
      await AppLog.init(dir);

      final testOnError = FlutterError.onError;
      final testDispatcherOnError = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = testOnError;
        PlatformDispatcher.instance.onError = testDispatcherOnError;
      });
      // Stand-in for the default presenter, so the test runner doesn't fail.
      var presented = 0;
      FlutterError.onError = (_) => presented++;

      installErrorLogging();

      // Like the SDK's FlutterErrorIntegration and OnErrorIntegration: capture,
      // then hand the error to the handler that was there before.
      final sentFlutter = <Object>[];
      final sentPlatform = <Object>[];
      final loggingOnError = FlutterError.onError!;
      FlutterError.onError = (d) {
        sentFlutter.add(d.exception);
        loggingOnError(d);
      };
      final loggingDispatcher = PlatformDispatcher.instance.onError!;
      PlatformDispatcher.instance.onError = (e, s) {
        sentPlatform.add(e);
        return loggingDispatcher(e, s);
      };

      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('widget boom')),
      );
      PlatformDispatcher.instance.onError!(
        StateError('async boom'),
        StackTrace.current,
      );
      await AppLog.flush();

      final log = File('${dir.path}/songies.log').readAsStringSync();
      expect(log, contains('widget boom'));
      expect(log, contains('async boom'));
      expect(sentFlutter, hasLength(1));
      expect(sentPlatform, hasLength(1));
      expect(presented, 1, reason: 'the default presentation is kept');
    },
  );
}
