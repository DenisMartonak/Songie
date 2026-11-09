import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'yt_links.dart';

/// Source of text shared into the app (Android Share sheet).
abstract class ShareSource {
  /// Text that launched the app, if any.
  Future<String?> initialText();

  /// Texts received while the app is running.
  Stream<String> get texts;
}

class ChannelShareSource implements ShareSource {
  ChannelShareSource({MethodChannel? method, EventChannel? events})
    : _method = method ?? const MethodChannel('songies/share'),
      _events = events ?? const EventChannel('songies/share/events');

  final MethodChannel _method;
  final EventChannel _events;

  @override
  Future<String?> initialText() => _method.invokeMethod<String>('initialText');

  @override
  Stream<String> get texts =>
      _events.receiveBroadcastStream().where((e) => e is String).cast<String>();
}

/// Canonical playlist links from shared text. Empty off Android unless a
/// [source] is injected.
Stream<String> sharedPlaylistLinks(ShareSource? source) {
  final src = source ?? (Platform.isAndroid ? ChannelShareSource() : null);
  if (src == null) return const Stream<String>.empty();
  late final StreamController<String> out;
  StreamSubscription<String>? sub;
  void emit(String text) {
    final l = extractLinkFromSharedText(text);
    if (l != null && !out.isClosed) out.add(l);
  }

  out = StreamController<String>(
    onListen: () {
      // Subscribe first so a share arriving during initialText() isn't lost.
      sub = src.texts.listen(emit, onError: (Object _) {});
      src
          .initialText()
          .then((t) {
            if (t != null) emit(t);
          })
          .catchError((Object _) {});
    },
    onCancel: () => sub?.cancel(),
  );
  return out.stream;
}

/// Opens Android's share menu for [text] (a room link, say).
Future<void> shareText(String text) =>
    const MethodChannel('songies/share').invokeMethod<void>('shareText', text);
