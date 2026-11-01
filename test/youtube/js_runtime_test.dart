import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:songies/youtube/js_runtime.dart';

void main() {
  final bin = Directory('/data/bin');

  JsRuntimeFinder finder(
    Set<String> present, {
    bool isAndroid = false,
    bool isWindows = false,
    Map<String, String> environment = const {'PATH': '/a:/b'},
  }) => JsRuntimeFinder(
    binDir: bin,
    isAndroid: isAndroid,
    isWindows: isWindows,
    environment: environment,
    exists: present.contains,
  );

  test("Songies' own Deno comes first", () async {
    final r = await finder({p.join(bin.path, 'deno'), '/a/node'}).find();
    expect(r!.kind, JsRuntimeKind.songiesDeno);
    expect(r.args, ['--js-runtimes', 'deno:${p.join(bin.path, 'deno')}']);
  });

  test('then deno on PATH', () async {
    final r = await finder({'/b/deno', '/a/node'}).find();
    expect(r!.kind, JsRuntimeKind.systemDeno);
    expect(r.args, ['--js-runtimes', 'deno']);
  });

  test('then node on PATH', () async {
    final r = await finder({'/b/node'}).find();
    expect(r!.kind, JsRuntimeKind.systemNode);
    expect(r.args, ['--js-runtimes', 'node']);
  });

  test('nothing found is null', () async {
    expect(await finder({}).find(), isNull);
  });

  test('Windows: ; separator, .exe names, Path key', () async {
    final r = await finder(
      {r'C:\tools\node.exe'},
      isWindows: true,
      environment: {'Path': r'C:\x;C:\tools'},
    ).find();
    expect(r!.kind, JsRuntimeKind.systemNode);
  });

  test('songiesDeno is deno.exe on Windows', () {
    expect(
      p.windows.basename(finder({}, isWindows: true).songiesDeno.path),
      'deno.exe',
    );
  });

  test('Android always has the bundled QuickJS', () async {
    final r = await finder({}, isAndroid: true).find();
    expect(r!.kind, JsRuntimeKind.bundled);
    expect(r.args, isEmpty);
  });
}
