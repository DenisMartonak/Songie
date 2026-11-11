import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/data/settings_repository.dart';
import 'package:songies/player/volume_memory.dart';

import '../helpers/test_db.dart';

void main() {
  group('restoreVolume', () {
    test('applies the saved volume', () async {
      double? applied;
      await restoreVolume(
        read: () async => '0.35',
        apply: (v) async => applied = v,
      );
      expect(applied, 0.35);
    });

    test('nothing saved, or junk saved: leaves the volume alone', () async {
      for (final saved in [null, '', 'loud', 'NaN']) {
        double? applied;
        await restoreVolume(
          read: () async => saved,
          apply: (v) async => applied = v,
        );
        expect(applied, isNull, reason: 'saved: $saved');
      }
    });

    test('an out-of-range value is clamped', () async {
      double? applied;
      await restoreVolume(
        read: () async => '1.7',
        apply: (v) async => applied = v,
      );
      expect(applied, 1.0);
    });
  });

  group('rememberVolume', () {
    test('saves the volume once the slider has stopped moving', () {
      fakeAsync((async) {
        final volumes = StreamController<double>();
        final writes = <String>[];
        rememberVolume(volumes.stream, write: (v) async => writes.add(v));

        // A drag: many values in quick succession, one write at the end.
        for (final v in [0.9, 0.8, 0.7, 0.6]) {
          volumes.add(v);
          async.elapse(const Duration(milliseconds: 50));
        }
        expect(writes, isEmpty);
        async.elapse(const Duration(milliseconds: 400));
        expect(writes, ['0.600']);
      });
    });

    test('an unchanged volume is not written again', () {
      fakeAsync((async) {
        final volumes = StreamController<double>();
        final writes = <String>[];
        rememberVolume(volumes.stream, write: (v) async => writes.add(v));

        volumes.add(0.5);
        async.elapse(const Duration(seconds: 1));
        // Player state is emitted for many reasons; the volume stays 0.5.
        volumes
          ..add(0.5)
          ..add(0.5);
        async.elapse(const Duration(seconds: 1));
        expect(writes, ['0.500']);
      });
    });
  });

  test('a volume saved in settings comes back on the next start', () async {
    final db = testDb();
    addTearDown(db.close);
    final settings = SettingsRepository(db);

    // This run: the slider settles at 0.42.
    final volumes = StreamController<double>();
    final sub = rememberVolume(
      volumes.stream,
      write: (v) => settings.setString(kVolume, v),
      quiet: Duration.zero,
    );
    volumes.add(0.42);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    // Next start.
    double? applied;
    await restoreVolume(
      read: () => settings.getString(kVolume),
      apply: (v) async => applied = v,
    );
    expect(applied, 0.42);
  });
}
