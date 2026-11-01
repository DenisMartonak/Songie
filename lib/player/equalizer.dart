import 'dart:async';

import 'package:just_audio/just_audio.dart' show AndroidEqualizer;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';

import '../core/log.dart';
import 'eq_presets.dart';

/// Shapes the sound with a preset, on whichever engine plays it.
abstract class Equalizer {
  /// False once this engine turned out not to have an equalizer (Windows'
  /// minimal libmpv may lack the filter).
  Future<bool> get available;

  /// What [available] knows so far, without waiting: null until the engine
  /// was tried.
  bool? get knownAvailable;

  /// Applies [preset] now and to every player made later.
  Future<void> apply(EqPreset preset);
}

/// mpv as [MpvEqualizerControl] uses it; faked in tests.
abstract class MpvCommands {
  Iterable<Object> get players;
  set onPlayerCreated(void Function(Object player)? f);
  Future<void> setFilter(Object player, String af);
  Future<void> command(Object player, List<String> args);
}

const _label = 'songieseq';

/// mpv's audio filter for [preset]: one octave-wide peaking equalizer per
/// band of [kEqBandsHz] and a volume stage for the preamp, each named so a
/// gain can also be changed in the playing chain. mpv rebuilds the chain
/// from this option for every file, so the option itself carries the gains.
String mpvEqFilter(EqPreset preset) {
  final stages = [
    for (var i = 0; i < kEqBandsHz.length; i++)
      'equalizer@b$i=f=${kEqBandsHz[i]}:t=o:w=1:'
          'g=${preset.gains[i].toStringAsFixed(1)}',
    'volume@pre=volume=${eqPreampDb(preset).toStringAsFixed(1)}dB',
  ];
  return '@$_label:lavfi=[${stages.join(',')}]';
}

/// The desktop equalizer. Every mpv player's `af` option holds the current
/// preset (so the next file and a rebuilt player get it); a change while a
/// song plays is also sent to the playing chain with `af-command`s. Off is
/// every gain at 0 dB.
///
/// mpv reports neither a missing filter nor a failed command, so this can't
/// tell whether the engine has an equalizer: it is only used where the
/// filter is known to exist (see `main.dart`).
class MpvEqualizerControl implements Equalizer {
  MpvEqualizerControl({required this._mpv}) {
    _mpv.onPlayerCreated = (p) => unawaited(_setFilter(p));
  }

  final MpvCommands _mpv;
  EqPreset _preset = EqPreset.off;

  @override
  Future<bool> get available async => true;

  @override
  bool? get knownAvailable => true;

  @override
  Future<void> apply(EqPreset preset) async {
    _preset = preset;
    for (final p in _mpv.players.toList()) {
      await _sendToPlaying(p, preset);
      await _setFilter(p);
    }
  }

  Future<void> _setFilter(Object player) async {
    try {
      await _mpv.setFilter(player, mpvEqFilter(_preset));
    } catch (e) {
      AppLog.w('Equalizer: could not set the filter ($e)');
    }
  }

  Future<void> _sendToPlaying(Object player, EqPreset preset) async {
    try {
      for (var i = 0; i < kEqBandsHz.length; i++) {
        await _mpv.command(player, [
          'af-command',
          _label,
          'g',
          preset.gains[i].toStringAsFixed(1),
          'equalizer@b$i',
        ]);
      }
      await _mpv.command(player, [
        'af-command',
        _label,
        'volume',
        '${eqPreampDb(preset).toStringAsFixed(1)}dB',
        'volume@pre',
      ]);
    } catch (e) {
      AppLog.w('Equalizer: mpv refused a gain change ($e)');
    }
  }
}

/// [MpvCommands] over the patched `just_audio_media_kit` (PATCHED.md).
class MediaKitMpvCommands implements MpvCommands {
  @override
  Iterable<Object> get players => JustAudioMediaKit.livePlayers;

  @override
  set onPlayerCreated(void Function(Object player)? f) =>
      JustAudioMediaKit.onPlayerCreated = f;

  @override
  Future<void> setFilter(Object player, String af) =>
      ((player as Player).platform! as NativePlayer).setProperty('af', af);

  @override
  Future<void> command(Object player, List<String> args) =>
      ((player as Player).platform! as NativePlayer).command(args);
}

/// The phone's equalizer as [AndroidEqualizerControl] uses it; faked in
/// tests.
abstract class AndroidEqualizerPort {
  Future<({List<double> centersHz, double minDb, double maxDb})> bands();
  Future<void> setEnabled(bool on);
  Future<void> setBandGain(int i, double db);
}

/// The Android equalizer: the system's own bands, each given the nearest
/// preset band's gain with the preamp folded in. Off disables the effect.
class AndroidEqualizerControl implements Equalizer {
  AndroidEqualizerControl(this._port);

  final AndroidEqualizerPort _port;

  @override
  Future<bool> get available async => true;

  @override
  bool? get knownAvailable => true;

  @override
  Future<void> apply(EqPreset preset) async {
    try {
      // Recorded at once and sent when the player starts; the bands are only
      // known once a song has loaded, so their gains follow in the
      // background (just_audio replays them whenever the player restarts).
      await _port.setEnabled(preset != EqPreset.off);
    } catch (e) {
      AppLog.w('Equalizer: the system equalizer refused a change ($e)');
    }
    if (preset != EqPreset.off) unawaited(_setGains(preset));
  }

  Future<void> _setGains(EqPreset preset) async {
    try {
      final b = await _port.bands();
      final pre = eqPreampDb(preset);
      final gains = mapGains(
        preset,
        b.centersHz,
        minDb: b.minDb - pre,
        maxDb: b.maxDb - pre,
      );
      for (var i = 0; i < gains.length; i++) {
        await _port.setBandGain(i, (gains[i] + pre).clamp(b.minDb, b.maxDb));
      }
    } catch (e) {
      AppLog.w('Equalizer: the system equalizer refused a change ($e)');
    }
  }
}

/// [AndroidEqualizerPort] over just_audio's [AndroidEqualizer].
class JustAudioEqualizerPort implements AndroidEqualizerPort {
  JustAudioEqualizerPort(this.effect);

  final AndroidEqualizer effect;

  @override
  Future<({List<double> centersHz, double minDb, double maxDb})> bands() async {
    final p = await effect.parameters;
    return (
      centersHz: [for (final b in p.bands) b.centerFrequency],
      minDb: p.minDecibels,
      maxDb: p.maxDecibels,
    );
  }

  @override
  Future<void> setEnabled(bool on) => effect.setEnabled(on);

  @override
  Future<void> setBandGain(int i, double db) async =>
      (await effect.parameters).bands[i].setGain(db);
}

/// No equalizer (tests, and platforms without one).
class NoEqualizer implements Equalizer {
  const NoEqualizer();

  @override
  Future<bool> get available async => false;

  @override
  bool? get knownAvailable => false;

  @override
  Future<void> apply(EqPreset preset) async {}
}

/// Applies the preset stored on this device (Off when none).
Future<void> applyStoredEqPreset({
  required Future<String?> Function() read,
  required Future<void> Function(EqPreset p) apply,
}) async => apply(eqPresetFromName(await read()));

/// The equalizer for this platform: Android's system effect ([androidEq],
/// which must be in the player's pipeline), mpv's filter on Linux, and none
/// on Windows for now. Windows' bundled libmpv may lack the filter, and mpv
/// can't report that: with the filter installed and missing, every song
/// would play silent. Enable it there once a Windows run shows it works.
Equalizer equalizerFor({
  required bool android,
  required bool windows,
  AndroidEqualizer? androidEq,
  required MpvCommands Function() mpv,
}) {
  if (android && androidEq != null) {
    return AndroidEqualizerControl(JustAudioEqualizerPort(androidEq));
  }
  if (windows) return const NoEqualizer();
  return MpvEqualizerControl(mpv: mpv());
}
