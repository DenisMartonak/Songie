import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/update/android_update_installer.dart';
import 'package:songies/update/update_installer.dart';

/// Thrown by the fake `quit`, standing in for the process exiting.
class _Quit implements Exception {}

class _FakeLauncher implements UpdateProcessLauncher {
  final calls = <String>[];

  /// Called on each `run`, before it is recorded.
  Future<void> Function(String exe, List<String> args)? onRun;

  @override
  Future<void> startDetached(String exe, List<String> args) async {
    calls.add('start $exe ${args.join(' ')}'.trim());
  }

  @override
  Future<int> run(String exe, List<String> args) async {
    await onRun?.call(exe, args);
    calls.add('run $exe ${args.join(' ')}'.trim());
    return 0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late _FakeLauncher launcher;
  var quits = 0;

  Future<Never> quit() async {
    quits++;
    throw _Quit();
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('songies_installer_test');
    launcher = _FakeLauncher();
    quits = 0;
  });

  tearDown(() {
    // Restore write access so a read-only test folder can be removed.
    Process.runSync('chmod', ['-R', 'u+w', dir.path]);
    dir.deleteSync(recursive: true);
  });

  File write(String name, String body) =>
      File(p.join(dir.path, name))..writeAsStringSync(body);

  group('windows', () {
    test('windows starts the installer silently, then quits', () async {
      final setup = write('songies-1.1.0-windows-setup.exe', 'exe');
      final installer = WindowsUpdateInstaller(quit: quit, launcher: launcher);

      expect(await installer.canSelfUpdate(), isTrue);
      await expectLater(installer.install(setup), throwsA(isA<_Quit>()));
      expect(launcher.calls, [
        'start ${setup.path} /VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
      ]);
      expect(quits, 1);
    });
  });

  group('linux', () {
    test('linux swaps the AppImage atomically and relaunches', () async {
      final appDir = Directory(p.join(dir.path, 'apps'))..createSync();
      final current = File(p.join(appDir.path, 'Songies.AppImage'))
        ..writeAsStringSync('old');
      final download = write('songies-1.1.0-x86_64.AppImage', 'new');
      final part = p.join(appDir.path, '.Songies.AppImage.part');
      launcher.onRun = (exe, args) async {
        // chmod runs on the staged copy, before the rename.
        expect(File(part).readAsStringSync(), 'new');
        expect(current.readAsStringSync(), 'old');
      };
      final installer = LinuxUpdateInstaller(
        env: {'APPIMAGE': current.path},
        quit: quit,
        launcher: launcher,
      );

      expect(await installer.canSelfUpdate(), isTrue);
      await expectLater(installer.install(download), throwsA(isA<_Quit>()));
      expect(launcher.calls, ['run chmod 755 $part', 'start ${current.path}']);
      expect(current.readAsStringSync(), 'new');
      expect(File(part).existsSync(), isFalse);
      expect(quits, 1);
    });

    test(
      'linux re-check during an install leaves the staged copy intact',
      () async {
        final appDir = Directory(p.join(dir.path, 'apps'))..createSync();
        final current = File(p.join(appDir.path, 'Songies.AppImage'))
          ..writeAsStringSync('old');
        final download = write('songies-1.1.0-x86_64.AppImage', 'new');
        final part = p.join(appDir.path, '.Songies.AppImage.part');
        final installer = LinuxUpdateInstaller(
          env: {'APPIMAGE': current.path},
          quit: quit,
          launcher: launcher,
        );
        launcher.onRun = (exe, args) async {
          // A UI re-check lands between chmod and the rename.
          expect(await installer.canSelfUpdate(), isTrue);
          expect(File(part).readAsStringSync(), 'new');
        };

        await expectLater(installer.install(download), throwsA(isA<_Quit>()));
        expect(current.readAsStringSync(), 'new');
        expect(appDir.listSync().map((e) => p.basename(e.path)), [
          'Songies.AppImage',
        ]);
      },
    );

    test('linux without APPIMAGE cannot self update', () async {
      final download = write('songies-1.1.0-x86_64.AppImage', 'new');
      final installer = LinuxUpdateInstaller(
        env: const {},
        quit: quit,
        launcher: launcher,
      );

      expect(await installer.canSelfUpdate(), isFalse);
      expect(await installer.install(download), isA<CannotReplace>());
      expect(launcher.calls, isEmpty);
      expect(quits, 0);
    });

    test('linux in a read-only folder cannot replace', () async {
      final appDir = Directory(p.join(dir.path, 'ro'))..createSync();
      final current = File(p.join(appDir.path, 'Songies.AppImage'))
        ..writeAsStringSync('old');
      final download = write('songies-1.1.0-x86_64.AppImage', 'new');
      Process.runSync('chmod', ['555', appDir.path]);
      final installer = LinuxUpdateInstaller(
        env: {'APPIMAGE': current.path},
        quit: quit,
        launcher: launcher,
      );

      expect(await installer.canSelfUpdate(), isFalse);
      expect(await installer.install(download), isA<CannotReplace>());
      expect(current.readAsStringSync(), 'old');
      expect(appDir.listSync().map((e) => p.basename(e.path)), [
        'Songies.AppImage',
      ]);
      expect(launcher.calls, isEmpty);
      expect(quits, 0);
    });
  });

  group('android', () {
    const channel = MethodChannel('songies/updater');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late Map<String, Object?> inspect;
    late bool canInstall;

    setUp(() {
      calls = [];
      inspect = {
        'sameSigner': true,
        'versionCode': 5,
        'installedVersionCode': 4,
      };
      canInstall = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'inspect':
            return inspect;
          case 'canInstall':
            return canInstall;
          default:
            return null;
        }
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    List<String> methods() => [for (final c in calls) c.method];

    test('android rejects a different signer', () async {
      final apk = write('songies-1.1.0.apk', 'apk');
      inspect['sameSigner'] = false;

      final out = await AndroidUpdateInstaller().install(apk);

      expect(out, isA<Rejected>());
      expect(methods(), isNot(contains('install')));
      expect(calls.first.arguments, {'path': apk.path});
      expect(apk.existsSync(), isFalse);
    });

    test('android rejects an older or equal versionCode', () async {
      for (final code in [4, 3]) {
        final apk = write('songies-1.1.0.apk', 'apk');
        inspect['versionCode'] = code;
        calls.clear();

        final out = await AndroidUpdateInstaller().install(apk);

        expect(out, isA<Rejected>(), reason: 'versionCode $code');
        expect(methods(), isNot(contains('install')));
      }
    });

    test('android fails closed when inspect errors or is malformed', () async {
      final apk = write('songies-1.1.0.apk', 'apk');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'inspect') {
          throw PlatformException(code: 'unreadable');
        }
        return true;
      });
      expect(await AndroidUpdateInstaller().install(apk), isA<InstallFailed>());

      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'inspect') return {'sameSigner': true};
        return true;
      });
      write('songies-1.1.0.apk', 'apk');
      expect(await AndroidUpdateInstaller().install(apk), isA<Rejected>());
      expect(methods(), isNot(contains('install')));
    });

    test('android without install permission asks for it', () async {
      final apk = write('songies-1.1.0.apk', 'apk');
      canInstall = false;
      final installer = AndroidUpdateInstaller();

      expect(await installer.install(apk), isA<NeedsPermission>());
      expect(methods(), isNot(contains('install')));
      expect(apk.existsSync(), isTrue);

      await installer.openPermissionSettings();
      expect(methods().last, 'openInstallSettings');
    });

    test('android happy path calls install', () async {
      final apk = write('songies-1.1.0.apk', 'apk');
      final installer = AndroidUpdateInstaller();

      expect(await installer.canSelfUpdate(), isTrue);
      expect(await installer.install(apk), isA<Installing>());
      expect(methods(), ['inspect', 'canInstall', 'install']);
      expect(calls.last.arguments, {'path': apk.path});
    });
  });
}
