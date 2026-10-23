import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songies/ui/library/android_folder_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('songies/folder_picker');

  void reply(Future<Object?> Function() handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          expect(call.method, 'pick');
          return handler();
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a path reply is a picked folder', () async {
    reply(() async => {'path': '/storage/emulated/0/Music'});
    final pick = await pickFolderOnAndroid();
    expect((pick as FolderPicked).path, '/storage/emulated/0/Music');
  });

  test('a cancelled reply is cancelled', () async {
    reply(() async => {'cancelled': true});
    expect(await pickFolderOnAndroid(), isA<FolderPickCancelled>());
  });

  const codes = {
    'unsupported_location': FolderPickError.unsupportedLocation,
    'no_file_manager': FolderPickError.noFileManager,
    'busy': FolderPickError.busy,
    'unknown': FolderPickError.unknown,
    'something_else': FolderPickError.unknown,
  };
  for (final entry in codes.entries) {
    test('error code ${entry.key} maps to ${entry.value.name}', () async {
      reply(() async => throw PlatformException(code: entry.key, message: 'm'));
      final pick = await pickFolderOnAndroid();
      expect((pick as FolderPickFailed).error, entry.value);
      expect(pick.detail, 'm');
    });
  }

  test('an unexpected reply is an unknown failure', () async {
    reply(() async => {'nothing': 1});
    final pick = await pickFolderOnAndroid();
    expect((pick as FolderPickFailed).error, FolderPickError.unknown);
  });
}
