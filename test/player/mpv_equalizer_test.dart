import 'package:flutter_test/flutter_test.dart';
import 'package:songies/player/eq_presets.dart';
import 'package:songies/player/equalizer.dart';

class FakeMpv implements MpvCommands {
  final calls = <(Object, List<String>)>[];
  final filters = <(Object, String)>[];
  final live = <Object>[];
  bool failFilter = false;

  @override
  Iterable<Object> get players => live;

  void Function(Object player)? created;

  @override
  set onPlayerCreated(void Function(Object player)? f) => created = f;

  @override
  Future<void> setFilter(Object player, String af) async {
    if (failFilter) throw Exception('no equalizer filter');
    filters.add((player, af));
  }

  @override
  Future<void> command(Object player, List<String> args) async =>
      calls.add((player, args));

  Future<void> newPlayer(Object p) async {
    live.add(p);
    created?.call(p);
    await pumpEventQueue();
  }
}

/// The gains sent to [player], by band index (and the preamp at 'pre').
Map<String, String> gainsSent(FakeMpv mpv, Object player) => {
  for (final (p, args) in mpv.calls)
    if (identical(p, player)) args.last: args[3],
};

void main() {
  test('the filter: ten labelled octave-wide stages and a preamp', () {
    final f = mpvEqFilter();
    expect(f, startsWith('@songieseq:lavfi=['));
    expect(RegExp('equalizer@b').allMatches(f), hasLength(10));
    for (var i = 0; i < kEqBandsHz.length; i++) {
      expect(f, contains('equalizer@b$i=f=${kEqBandsHz[i]}:t=o:w=1:g=0'));
    }
    expect(f, endsWith('volume@pre=volume=0dB]'));
  });

  test('a new player gets the filter, then the current gains', () async {
    final mpv = FakeMpv();
    final eq = MpvEqualizerControl(mpv: mpv);
    await eq.apply(EqPreset.rock);
    const p = 'player1';
    await mpv.newPlayer(p);
    expect(mpv.filters.single, (p, mpvEqFilter()));
    final sent = gainsSent(mpv, p);
    expect(sent['equalizer@b0'], '4.0');
    expect(sent['equalizer@b9'], '4.0');
    expect(sent['volume@pre'], '-2.0dB');
  });

  test(
    'Off on a live player sends flat gains, never clears the filter',
    () async {
      final mpv = FakeMpv();
      final eq = MpvEqualizerControl(mpv: mpv);
      await mpv.newPlayer('p');
      await eq.apply(EqPreset.bassBoost);
      mpv.calls.clear();
      await eq.apply(EqPreset.off);
      final sent = gainsSent(mpv, 'p');
      expect(sent.values.where((v) => v != '0.0dB'), everyElement('0.0'));
      expect(sent['volume@pre'], '0.0dB');
      expect(mpv.filters, hasLength(1));
      expect(mpv.calls.map((c) => c.$2.first), everyElement('af-command'));
    },
  );

  test('without the filter it is unavailable and quiet', () async {
    final mpv = FakeMpv()..failFilter = true;
    final eq = MpvEqualizerControl(mpv: mpv);
    await mpv.newPlayer('p');
    expect(await eq.available, isFalse);
    await eq.apply(EqPreset.rock);
    expect(mpv.calls, isEmpty);
  });
}
