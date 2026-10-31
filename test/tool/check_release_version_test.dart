import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_release_version.dart'
    show ReleaseInfo, ReleaseVersionException, checkReleaseVersion, runCli;

/// The release version check the workflow runs on every tag (Plan 11 Task 7).
void main() {
  const pubspec = '''
name: songies
# version: 9.9.9+99 (a comment, not the real line)
version: 1.2.0+7

environment:
  sdk: ^3.13.5
''';
  const appVersionDart = '''
/// The app version.
const String appVersion = '1.2.0';
''';

  String previous(int build, [String version = '1.1.0']) =>
      jsonEncode({'version': version, 'build': build});

  group('checkReleaseVersion', () {
    test('matching tag passes', () {
      final info = checkReleaseVersion(
        tag: 'v1.2.0',
        pubspec: pubspec,
        appVersionSource: appVersionDart,
        previousVersionJson: previous(6),
      );
      expect(info.version, '1.2.0');
      expect(info.build, 7);
    });

    test('mismatched tag fails', () {
      for (final tag in ['v1.2.1', '1.2.0', 'v1.2', 'v1.2.0+7', 'v1.2.0-rc1']) {
        expect(
          () => checkReleaseVersion(
            tag: tag,
            pubspec: pubspec,
            appVersionSource: appVersionDart,
          ),
          throwsA(
            isA<ReleaseVersionException>().having(
              (e) => e.message,
              'message',
              allOf(contains(tag), contains('1.2.0')),
            ),
          ),
          reason: tag,
        );
      }
    });

    test('appVersion mismatch fails', () {
      expect(
        () => checkReleaseVersion(
          tag: 'v1.2.0',
          pubspec: pubspec,
          appVersionSource: "const String appVersion = '1.1.0';",
        ),
        throwsA(
          isA<ReleaseVersionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('appVersion'), contains('1.1.0')),
          ),
        ),
      );
    });

    test('build not increasing fails', () {
      for (final prev in [7, 8]) {
        expect(
          () => checkReleaseVersion(
            tag: 'v1.2.0',
            pubspec: pubspec,
            appVersionSource: appVersionDart,
            previousVersionJson: previous(prev),
          ),
          throwsA(
            isA<ReleaseVersionException>().having(
              (e) => e.message,
              'message',
              allOf(contains('build'), contains('$prev')),
            ),
          ),
          reason: 'previous build $prev',
        );
      }
    });

    test('no previous release passes', () {
      final info = checkReleaseVersion(
        tag: 'v1.2.0',
        pubspec: pubspec,
        appVersionSource: appVersionDart,
      );
      expect(info.build, 7);
    });

    test('no tag (a manual build) still checks appVersion', () {
      expect(
        checkReleaseVersion(
          pubspec: pubspec,
          appVersionSource: appVersionDart,
        ).version,
        '1.2.0',
      );
      expect(
        () => checkReleaseVersion(
          pubspec: pubspec,
          appVersionSource: "const String appVersion = '1.0.0';",
        ),
        throwsA(isA<ReleaseVersionException>()),
      );
    });

    test('a pubspec version without a build number fails', () {
      expect(
        () => checkReleaseVersion(
          tag: 'v1.2.0',
          pubspec: 'name: songies\nversion: 1.2.0\n',
          appVersionSource: appVersionDart,
        ),
        throwsA(
          isA<ReleaseVersionException>().having(
            (e) => e.message,
            'message',
            contains('X.Y.Z+N'),
          ),
        ),
      );
    });

    test('a malformed previous version.json fails', () {
      for (final bad in ['not json', '{"version":"1.1.0"}', '[1]']) {
        expect(
          () => checkReleaseVersion(
            tag: 'v1.2.0',
            pubspec: pubspec,
            appVersionSource: appVersionDart,
            previousVersionJson: bad,
          ),
          throwsA(isA<ReleaseVersionException>()),
          reason: bad,
        );
      }
    });

    test('ReleaseInfo encodes the version.json format', () {
      expect(
        jsonDecode(const ReleaseInfo(version: '1.2.0', build: 7).toJson()),
        {'version': '1.2.0', 'build': 7},
      );
    });
  });

  group('runCli', () {
    late Directory dir;
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('check_release_version_');
      File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
      File('${dir.path}/app_version.dart').writeAsStringSync(appVersionDart);
      out = StringBuffer();
      err = StringBuffer();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    int run(List<String> extra) => runCli(
      [
        '--pubspec',
        '${dir.path}/pubspec.yaml',
        '--app-version',
        '${dir.path}/app_version.dart',
        ...extra,
      ],
      out: out,
      err: err,
    );

    test('writes version.json', () {
      final target = '${dir.path}/out/version.json';
      expect(run(['--tag', 'v1.2.0', '--write', target]), 0);
      expect(File(target).readAsStringSync(), '{"version":"1.2.0","build":7}');
      // The step outputs the workflow reads with >> "$GITHUB_OUTPUT".
      expect(out.toString(), 'version=1.2.0\nbuild=7\n');
    });

    test('reads --previous and exits non-zero with the reason', () {
      final prev = File('${dir.path}/previous.json')
        ..writeAsStringSync(previous(7));
      final target = '${dir.path}/version.json';
      expect(
        run(['--tag', 'v1.2.0', '--previous', prev.path, '--write', target]),
        isNot(0),
      );
      expect(err.toString(), contains('build'));
      expect(out.toString(), isEmpty);
      expect(File(target).existsSync(), isFalse);
    });

    test('a missing --previous file fails', () {
      expect(
        run(['--tag', 'v1.2.0', '--previous', '${dir.path}/nope.json']),
        isNot(0),
      );
      expect(err.toString(), contains('nope.json'));
    });

    test('an unknown option fails with usage', () {
      expect(run(['--bogus']), 64);
      expect(err.toString(), contains('usage'));
    });
  });
}
