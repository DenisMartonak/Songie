import 'package:flutter/animation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';
import '../../providers.dart';

/// The app's motion tokens; use these, never ad-hoc durations. With reduced
/// motion every token becomes [Duration.zero].
abstract final class Motion {
  /// Presses.
  static const Duration quick = Duration(milliseconds: 120);

  /// Most transitions.
  static const Duration standard = Duration(milliseconds: 250);
  static const Curve standardCurve = Curves.easeOutCubic;

  /// Page and track changes.
  static const Duration emphasized = Duration(milliseconds: 450);
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;

  /// Palette transitions.
  static const Duration colour = Duration(milliseconds: 600);
}

final _reduceMotionSettingProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(kReduceMotion, fallback: false),
);

/// Whether the device-local reduce motion setting is on. Where a context is
/// available, `MediaQuery.disableAnimationsOf` is ORed in as well.
final reduceMotionProvider = Provider<bool>(
  (ref) => ref.watch(_reduceMotionSettingProvider).value ?? false,
);
