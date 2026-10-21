import 'package:flutter/material.dart';

/// Floating snack bars that clear the page's bottom overlays (on phones: the
/// mini-player and bottom nav), using the padding of the context they were
/// created from. Create one before an `await` to keep using it afterwards.
class PageSnackBars {
  PageSnackBars._(this._messenger, this._bottom);

  factory PageSnackBars.of(BuildContext context) => PageSnackBars._(
    ScaffoldMessenger.of(context),
    MediaQuery.paddingOf(context).bottom,
  );

  final ScaffoldMessengerState _messenger;
  final double _bottom;

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show({
    required Widget content,
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    return _messenger.showSnackBar(
      SnackBar(
        content: content,
        action: action,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(8, 0, 8, _bottom + 8),
      ),
    );
  }

  void clear() => _messenger.clearSnackBars();
}

/// Shows a message snack bar on the page [context] belongs to.
void showPageSnackBar(
  BuildContext context, {
  required Widget content,
  SnackBarAction? action,
}) {
  PageSnackBars.of(context).show(content: content, action: action);
}
