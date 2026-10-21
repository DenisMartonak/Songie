import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/library/file_hasher.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('songies_hash_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('sha256File returns the hex digest of the file content', () async {
    final f = File('${tmp.path}/abc.bin')..writeAsStringSync('abc');
    expect(
      await sha256File(f),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('sha256File of an empty file is the empty-input digest', () async {
    final f = File('${tmp.path}/empty.bin')..writeAsBytesSync(const []);
    expect(
      await sha256File(f),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('sha256File propagates FileSystemException for a missing file', () {
    final f = File('${tmp.path}/missing.bin');
    expect(sha256File(f), throwsA(isA<FileSystemException>()));
  });
}
