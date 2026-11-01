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

/// The audio filter put on every mpv player once: one octave-wide peaking
/// equalizer per band of [kEqBandsHz] and a volume stage for the preamp,
/// each named so [MpvEqualizerControl] can change its gain in place.
String mpvEqFilter() {
  final stages = [
    for (var i = 0; i < kEqBandsHz.length; i++)
      'equalizer@b$i=f=${kEqBandsHz[i]}:t=o:w=1:g=0',
    'volume@pre=volume=0dB',
  ];
  return '@$_label:lavfi=[${stages.join(',')}]';
}

/// The desktop equalizer: the filter is set once per mpv player and preset
/// changes send `af-command`s, so switching is seamless. Off is every gain
/// at 0 dB.
class MpvEqualizerControl implements Equalizer {
  MpvEqualizerControl({required this._mpv}) {
    _mpv.onPlayerCreated = (p) => unawaited(_setUp(p));
  }

  final MpvCommands _mpv;
  final _availability = Completer<bool>();
  bool? _known;
  EqPreset _preset = EqPreset.off;

  @override
  Future<bool> get available => _availability.future;

  @override
  bool? get knownAvailable => _known;

  @override
  Future<void> apply(EqPreset preset) async {
    _preset = preset;
    if (_known == false) return;
    for (final p in _mpv.players.toList()) {
      await _send(p, preset);
    }
  }

  Future<void> _setUp(Object player) async {
    if (_known == false) return;
    try {
      await _mpv.setFilter(player, mpvEqFilter());
      _settle(true);
    } catch (e) {
      AppLog.w('Equalizer unavailable: mpv refused its filter ($e)');
      _settle(false);
      return;
    }
    await _send(player, _preset);
  }

  void _settle(bool ok) {
    _known = ok;
    if (!_availability.isCompleted) _availability.complete(ok);
  }

  Future<void> _send(Object player, EqPreset preset) async {
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
      if (preset == EqPreset.off) {
        await _port.setEnabled(false);
        return;
      }
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
      await _port.setEnabled(true);
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
