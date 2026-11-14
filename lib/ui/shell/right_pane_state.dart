import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';
import '../../providers.dart';

/// What the desktop right pane shows.
enum RightPaneContent { friends, lyrics, queue }

final _rightPaneOpenSettingProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(kRightPaneOpen, fallback: true),
);

/// Whether the right pane is open: the stored, device-local flag (open by
/// default), or null until it has loaded.
final rightPaneOpenProvider = Provider<bool?>(
  (ref) => ref.watch(_rightPaneOpenSettingProvider).value,
);

/// What the right pane shows. Session only: always starts on Friends.
final rightPaneContentProvider =
    NotifierProvider<RightPaneContentNotifier, RightPaneContent>(
      RightPaneContentNotifier.new,
    );

class RightPaneContentNotifier extends Notifier<RightPaneContent> {
  @override
  RightPaneContent build() => RightPaneContent.friends;

  void show(RightPaneContent content) => state = content;
}

/// Opens, closes and switches the right pane.
final rightPaneProvider = Provider<RightPaneController>(
  RightPaneController.new,
);

class RightPaneController {
  RightPaneController(this._ref);

  final Ref _ref;

  Future<void> _store(bool open) =>
      _ref.read(settingsRepositoryProvider).setBool(kRightPaneOpen, open);

  Future<void> close() => _store(false);

  Future<void> showFriends() {
    _ref.read(rightPaneContentProvider.notifier).show(RightPaneContent.friends);
    return _store(true);
  }

  /// Shows [content]; if the pane already shows it (and it isn't Friends),
  /// goes back to Friends instead. Either way the pane ends up open.
  Future<void> toggle(RightPaneContent content) {
    final open = _ref.read(rightPaneOpenProvider) ?? false;
    final showing = _ref.read(rightPaneContentProvider);
    if (open && showing == content && content != RightPaneContent.friends) {
      return showFriends();
    }
    _ref.read(rightPaneContentProvider.notifier).show(content);
    return _store(true);
  }
}
