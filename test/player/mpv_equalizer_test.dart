import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/eq_presets.dart';
import 'package:songies/player/equalizer.dart';

/// Models mpv: `af` is an option that every new file's audio chain is built
/// from; `af-command` only changes the current file's chain; setting a
/// property never throws.
class FakeMpv implements MpvCommands {
  final live = <Object>[];
  final af = <Object, String>{};
  final commands = <(Object, List<String>)>[];

  @override
  Iterable<Object> get players => live;

  void Function(Object player)? created;

  @override
  set onPlayerCreated(void Function(Object player)? f) => created = f;

  @override
  Future<void> setFilter(Object player, String filter) async =>
      af[player] = filter;

  @override
  Future<void> command(Object player, List<String> args) async =>
      commands.add((player, args));

  Future<void> newPlayer(Object p) async {
    live.add(p);
    created?.call(p);
    await pumpEventQueue();
  }
}

void main() {
  test('the filter carries the preset: ten named stages and a preamp', () {
    final f = mpvEqFilter(EqPreset.rock);
    expect(f, startsWith('@songieseq:lavfi=['));
    expect(RegExp('equalizer@b').allMatches(f), hasLength(10));
    expect(f, contains('equalizer@b0=f=31:t=o:w=1:g=4.0'));
    expect(f, contains('equalizer@b4=f=500:t=o:w=1:g=-1.0'));
    expect(f, endsWith('volume@pre=volume=-2.0dB]'));
    expect(
      mpvEqFilter(EqPreset.off),
      contains('equalizer@b0=f=31:t=o:w=1:g=0.0'),
    );
  });

  test('a preset picked while idle reaches the next file', () async {
    final mpv = FakeMpv();
    final eq = MpvEqualizerControl(mpv: mpv);
    await mpv.newPlayer('p');
    await eq.apply(EqPreset.rock);
    // The option the next file's chain is built from holds Rock.
    expect(mpv.af['p'], mpvEqFilter(EqPreset.rock));
  });

  test('a player made later starts with the current preset', () async {
    final mpv = FakeMpv();
    final eq = MpvEqualizerControl(mpv: mpv);
    await eq.apply(EqPreset.vocal);
    await mpv.newPlayer('p2');
    expect(mpv.af['p2'], mpvEqFilter(EqPreset.vocal));
  });

  test('a change mid-song is also sent to the playing chain', () async {
    final mpv = FakeMpv();
    final eq = MpvEqualizerControl(mpv: mpv);
    await mpv.newPlayer('p');
    mpv.commands.clear();
    await eq.apply(EqPreset.bassBoost);
    final sent = {for (final (_, a) in mpv.commands) a.last: a[3]};
    expect(sent['equalizer@b0'], '6.0');
    expect(sent['volume@pre'], '-3.0dB');
  });

  test('each platform gets its equalizer; Windows none for now', () {
    MpvCommands mpv() => FakeMpv();
    expect(
      equalizerFor(android: false, windows: true, mpv: mpv),
      isA<NoEqualizer>(),
    );
    expect(
      equalizerFor(android: false, windows: false, mpv: mpv),
      isA<MpvEqualizerControl>(),
    );
  });
}
