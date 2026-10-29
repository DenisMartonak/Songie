import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songies/library/tag_reader.dart';
import 'package:songies/lyrics/file_lyrics.dart';
import 'package:songies/lyrics/lyrics.dart';
import 'package:songies/lyrics/lyrics_sources.dart';

class _Tags implements TagReader {
  _Tags({this.lyrics, this.throws = false});
  final String? lyrics;
  final bool throws;

  @override
  Future<TrackTags> read(File f) async {
    if (throws) throw const FormatException('no tags');
    return TrackTags(lyrics: lyrics);
  }
}

void main() {
  late Directory dir;
  late String audio;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lyrics_file_test');
    audio = '${dir.path}${Platform.pathSeparator}song.mp3';
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> sidecar(String text, {String ext = 'lrc'}) =>
      File('${dir.path}${Platform.pathSeparator}song.$ext').writeAsString(text);

  test('sidecar with stamps is synced from file', () async {
    await sidecar('[00:01.00] One\n[00:02.00] Two\n');
    final a = await FileLyricsSource(_Tags()).read(audio);
    final l = (a as Found).lyrics;
    expect(l.kind, LyricsKind.synced);
    expect(l.source, LyricsSource.file);
    expect(l.lines.length, 2);
    expect(l.credit, isNull);
  });

  test('uppercase .LRC sidecar is found', () async {
    await sidecar('[00:01.00] One\n[00:02.00] Two\n', ext: 'LRC');
    final a = await FileLyricsSource(_Tags()).read(audio);
    expect((a as Found).lyrics.kind, LyricsKind.synced);
  });

  test('sidecar without stamps is plain', () async {
    await sidecar('Just words\nMore words');
    final l = (await FileLyricsSource(_Tags()).read(audio) as Found).lyrics;
    expect(l.kind, LyricsKind.plain);
    expect(l.source, LyricsSource.file);
    expect(l.text, 'Just words\nMore words');
  });

  test('plain tag lyrics with one stray timestamp stay plain, whole', () async {
    const text =
        'Kettle sings at dawn\n[00:42.00] The cat ignores it\n'
        'Toast lands butter up\nNobody believes it';
    final l = (await FileLyricsSource(
      _Tags(lyrics: text),
    ).read(audio) as Found).lyrics;
    expect(l.kind, LyricsKind.plain);
    expect(l.text, text);
  });

  test('a sidecar with one timed line is plain', () async {
    await sidecar('[00:01.00] Only this\nand the rest untimed');
    final l = (await FileLyricsSource(_Tags()).read(audio) as Found).lyrics;
    expect(l.kind, LyricsKind.plain);
    expect(l.text, '[00:01.00] Only this\nand the rest untimed');
  });

  test('no sidecar, synced tag lyrics', () async {
    final a = await FileLyricsSource(
      _Tags(lyrics: '[00:01.00] One\n[00:02.00] Two'),
    ).read(audio);
    expect((a as Found).lyrics.kind, LyricsKind.synced);
  });

  test('no sidecar, no tag lyrics is Nothing', () async {
    expect(await FileLyricsSource(_Tags()).read(audio), isA<Nothing>());
  });

  test('null path is Nothing', () async {
    expect(await FileLyricsSource(_Tags()).read(null), isA<Nothing>());
  });

  test('throwing tag reader is Nothing', () async {
    expect(
      await FileLyricsSource(_Tags(throws: true)).read(audio),
      isA<Nothing>(),
    );
  });
}
