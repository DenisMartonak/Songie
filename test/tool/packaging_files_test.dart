import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Static checks on the packaging scripts (Plan 11 Task 6). The installer and
/// the AppImage themselves are built in CI; these guard the values the
/// in-app updater relies on.
void main() {
  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return file.readAsStringSync();
  }

  bool isExecutable(String path) =>
      File(path).statSync().mode & 0x49 != 0; // any of u+x, g+x, o+x

  group('windows/installer/songies.iss', () {
    late String iss;
    setUp(() => iss = read('windows/installer/songies.iss'));

    test('installs per user into the local Programs folder', () {
      expect(iss, contains('PrivilegesRequired=lowest'));
      expect(iss, contains(r'DefaultDirName={localappdata}\Programs\Songies'));
    });

    test('has a fixed, escaped AppId GUID', () {
      expect(
        RegExp(
          r'^AppId=\{\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
          r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}\s*$',
          multiLine: true,
        ).hasMatch(iss),
        isTrue,
      );
    });

    test('takes AppVersion and SourceDir and names the setup file', () {
      expect(iss, contains('{#AppVersion}'));
      expect(iss, contains('{#SourceDir}'));
      expect(
        iss,
        contains('OutputBaseFilename=songies-{#AppVersion}-windows-setup'),
      );
    });

    test('closes the running app and lets [Run] relaunch it', () {
      expect(iss, contains('CloseApplications=yes'));
      expect(iss, contains('RestartApplications=no'));
    });

    test('[Run] launches Songies even under /VERYSILENT', () {
      final run = RegExp(
        r'^\[Run\]\s*\n(.*?)(?=^\[|\z)',
        multiLine: true,
        dotAll: true,
      ).firstMatch(iss);
      expect(run, isNotNull, reason: 'no [Run] section');
      final launch = run!
          .group(1)!
          .split('\n')
          .firstWhere(
            (l) => l.contains('songies.exe') || l.contains('{#AppExeName}'),
            orElse: () => '',
          );
      expect(launch, isNotEmpty, reason: 'no [Run] entry for songies.exe');
      final flags = RegExp(r'Flags:\s*([^;]+)')
          .firstMatch(launch)!
          .group(1)!
          .trim()
          .split(RegExp(r'\s+'));
      expect(flags, containsAll(['nowait', 'postinstall']));
      expect(flags, isNot(contains('skipifsilent')));
      expect(flags, isNot(contains('unchecked')));
    });

    test('uninstall asks before deleting %APPDATA%\\Songies, default No', () {
      expect(iss, contains('CurUninstallStepChanged'));
      expect(iss, contains(r'{userappdata}\Songies'));
      expect(iss, contains('MB_DEFBUTTON2'));
      expect(iss, contains('UninstallSilent'));
    });

    test(
      'Yes also deletes the sign-in folder %APPDATA%\\com.songies\\Songies',
      () {
        expect(
          iss,
          contains(r"ExpandConstant('{userappdata}\com.songies\Songies')"),
        );
        expect(iss, contains('DelTree(SupportDir, True, True, True)'));
      },
    );
  });

  group('linux packaging', () {
    test('desktop file names the binary and the icon', () {
      final desktop = read('linux/packaging/songies.desktop');
      expect(desktop, startsWith('[Desktop Entry]'));
      expect(desktop, contains('\nType=Application\n'));
      expect(desktop, contains('\nName=Songies\n'));
      expect(desktop, contains('\nExec=songies'));
      expect(desktop, contains('\nIcon=songies\n'));
    });

    test('the bundle ships the icon and the window loads it', () {
      expect(
        read('linux/CMakeLists.txt'),
        contains(
          'install(FILES "\${CMAKE_CURRENT_SOURCE_DIR}/packaging/songies.png"',
        ),
      );
      final runner = read('linux/runner/my_application.cc');
      expect(runner, contains('"data", "songies.png"'));
      expect(runner, contains('gtk_window_set_icon_from_file'));
    });

    test('the AppImage uses the 512 px app icon', () {
      final script = read('tool/build_appimage.sh');
      expect(script, contains('ICON_SRC="\$PACKAGING/songies.png"'));
      final png = File('linux/packaging/songies.png').readAsBytesSync();
      // PNG signature, then the IHDR width and height (big-endian).
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      final size = ByteData.sublistView(png, 16, 24);
      expect([size.getUint32(0), size.getUint32(4)], [512, 512]);
    });

    test('AppRun is executable and never only appends library paths', () {
      const path = 'linux/packaging/AppRun';
      final appRun = read(path);
      expect(isExecutable(path), isTrue);
      // Set from this mount, never inherited from the process that started it.
      expect(appRun, contains(r'LIBMPV_LIBRARY_PATH="$APPDIR/usr/lib/'));
      expect(appRun, contains('export LIBMPV_LIBRARY_PATH'));
      expect(
        RegExp(r'''LD_LIBRARY_PATH=["']?\$\{?LD_LIBRARY_PATH''')
            .hasMatch(appRun),
        isFalse,
        reason: 'an inherited LD_LIBRARY_PATH must never come first',
      );
    });

    test('build_appimage.sh names the output and excludes desktop libs', () {
      const path = 'tool/build_appimage.sh';
      final script = read(path);
      expect(isExecutable(path), isTrue);
      expect(script, contains(r'songies-${VERSION}-x86_64.AppImage'));
      expect(script, contains('build/linux/x64/release/bundle'));
      expect(script, contains('linuxdeploy'));
      for (final lib in [
        'libgtk-',
        'libglib-',
        'libsecret-',
        'libdbus-',
        'libavahi-',
      ]) {
        expect(script, contains("'$lib"), reason: 'must exclude $lib*');
      }
    });
  }, skip: Platform.isWindows ? 'POSIX file modes' : null);
}
