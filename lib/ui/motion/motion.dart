import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';
import '../../providers.dart';

/// The app's motion tokens; use these, never ad-hoc durations. Widgets read
/// them through [Motion.of], which makes every duration [Duration.zero] when
/// motion is reduced (the Reduce animations setting, or the system's
/// "remove animations").
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

  /// The tokens to use under [context]: all zero when motion is reduced,
  /// either by the setting (published by a [MotionScope] above) or by
  /// `MediaQuery.disableAnimations`. Depends on both, so the caller
  /// rebuilds when either changes.
  static MotionDurations of(BuildContext context) {
    final setting =
        context
            .dependOnInheritedWidgetOfExactType<_ReduceMotionSetting>()
            ?.reduce ??
        false;
    final system = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return setting || system ? MotionDurations.zero : MotionDurations.full;
  }
}

/// The durations of the [Motion] tokens in effect; see [Motion.of].
@immutable
class MotionDurations {
  const MotionDurations._({
    required this.quick,
    required this.standard,
    required this.emphasized,
    required this.colour,
  });

  /// The tokens as specified.
  static const full = MotionDurations._(
    quick: Motion.quick,
    standard: Motion.standard,
    emphasized: Motion.emphasized,
    colour: Motion.colour,
  );

  /// Reduced motion: everything happens at once.
  static const zero = MotionDurations._(
    quick: Duration.zero,
    standard: Duration.zero,
    emphasized: Duration.zero,
    colour: Duration.zero,
  );

  final Duration quick;
  final Duration standard;
  final Duration emphasized;
  final Duration colour;

  /// Whether motion is reduced (every duration is zero).
  bool get reduced => quick == Duration.zero;
}

final _reduceMotionSettingProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watchBool(kReduceMotion, fallback: false),
);

/// The device-local Reduce animations setting (off until it has loaded, or
/// when it can't be read). Widgets don't read this directly: [Motion.of]
/// combines it, via [MotionScope], with `MediaQuery.disableAnimations`.
final reduceMotionProvider = Provider<bool>(
  (ref) => ref.watch(_reduceMotionSettingProvider).value ?? false,
);

/// Publishes [reduceMotionProvider] to [Motion.of] for the subtree. The app
/// puts one above its navigator.
class MotionScope extends ConsumerWidget {
  const MotionScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ReduceMotionSetting(
    reduce: ref.watch(reduceMotionProvider),
    child: child,
  );
}

class _ReduceMotionSetting extends InheritedWidget {
  const _ReduceMotionSetting({required this.reduce, required super.child});

  final bool reduce;

  @override
  bool updateShouldNotify(_ReduceMotionSetting old) => reduce != old.reduce;
}
