import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/room/linux_link_registration.dart';

void main() {
  late Directory apps;
  late List<List<String>> calls;
  Future<void> xdg(List<String> args) async => calls.add(args);

  setUp(() {
    apps = Directory.systemTemp.createTempSync('songies_apps');
    calls = [];
  });
  tearDown(() => apps.deleteSync(recursive: true));

  test('writes the desktop file and sets the handler once', () async {
    final wrote = await registerLinuxLinks(
      appImage: '/opt/Songies.AppImage',
      applications: apps,
      xdgMime: xdg,
    );
    expect(wrote, isTrue);
    final text = File('${apps.path}/songies-links.desktop').readAsStringSync();
    expect(text, contains('Exec="/opt/Songies.AppImage" %u'));
    expect(text, contains('MimeType=x-scheme-handler/songies;'));
    expect(calls, [
      ['default', 'songies-links.desktop', 'x-scheme-handler/songies'],
    ]);
  });

  test('a second run with the same AppImage writes nothing', () async {
    Future<bool> run() => registerLinuxLinks(
      appImage: '/opt/Songies.AppImage',
      applications: apps,
      xdgMime: xdg,
    );
    await run();
    expect(await run(), isFalse);
    expect(calls, hasLength(1));
  });

  test('a moved AppImage rewrites the file', () async {
    Future<bool> run(String path) =>
        registerLinuxLinks(appImage: path, applications: apps, xdgMime: xdg);
    await run('/a/Songies.AppImage');
    expect(await run('/b/Songies.AppImage'), isTrue);
    expect(calls, hasLength(2));
  });

  test('without APPIMAGE nothing is written', () async {
    final wrote = await registerLinuxLinks(
      appImage: null,
      applications: apps,
      xdgMime: xdg,
    );
    expect(wrote, isFalse);
    expect(apps.listSync(), isEmpty);
    expect(calls, isEmpty);
  });
}
