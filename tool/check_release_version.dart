// Release version check, run by .github/workflows/release.yml (Plan 11).
//
//   dart tool/check_release_version.dart [--tag vX.Y.Z]
//       [--pubspec pubspec.yaml] [--app-version lib/core/app_version.dart]
//       [--previous version.json] [--write version.json]
//
// Fails (exit 1, the reason on stderr) when:
//   - the tag is not exactly `v` + the X.Y.Z of `version: X.Y.Z+N` in pubspec;
//   - `appVersion` in lib/core/app_version.dart is not that X.Y.Z;
//   - N is not greater than the `build` of the previous release's
//     version.json.
// Without --tag (a manual build) only the pubspec/appVersion agreement is
// checked. On success it prints `version=X.Y.Z` and `build=N` (for
// $GITHUB_OUTPUT) and, with --write, writes {"version":"X.Y.Z","build":N}.
//
// Only dart:io and dart:convert, so it runs without `flutter pub get`.
import 'dart:convert';
import 'dart:io';

/// A release's version and its build number, as stored in version.json.
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.build});

  final String version;
  final int build;

  /// The version.json asset: `{"version":"X.Y.Z","build":N}`.
  String toJson() => jsonEncode({'version': version, 'build': build});
}

/// A failed check; [message] says what to fix.
class ReleaseVersionException implements Exception {
  ReleaseVersionException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _pubspecVersion = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true);
final _fullVersion = RegExp(r'''^['"]?(\d+\.\d+\.\d+)\+(\d+)['"]?$''');
final _appVersion = RegExp(
  r'''^\s*const\s+String\s+appVersion\s*=\s*['"]([^'"]*)['"]\s*;''',
  multiLine: true,
);

/// Checks the sources of a release and returns its version.json contents.
///
/// [pubspec] and [appVersionSource] are file contents. [tag] is null for a
/// build that is not a release. [previousVersionJson] is the latest
/// release's version.json, or null when there is no release yet.
ReleaseInfo checkReleaseVersion({
  String? tag,
  required String pubspec,
  required String appVersionSource,
  String? previousVersionJson,
}) {
  final versionLine = _pubspecVersion.firstMatch(pubspec);
  if (versionLine == null) {
    throw ReleaseVersionException('pubspec.yaml has no `version:` line.');
  }
  final full = _fullVersion.firstMatch(versionLine.group(1)!);
  if (full == null) {
    throw ReleaseVersionException(
      'pubspec.yaml version "${versionLine.group(1)}" is not X.Y.Z+N '
      '(the build number N is required).',
    );
  }
  final version = full.group(1)!;
  final build = int.parse(full.group(2)!);

  if (tag != null && tag != 'v$version') {
    throw ReleaseVersionException(
      'Tag "$tag" does not match pubspec.yaml version $version '
      '(expected tag "v$version").',
    );
  }

  final app = _appVersion.firstMatch(appVersionSource);
  if (app == null) {
    throw ReleaseVersionException(
      'No `const String appVersion = \'X.Y.Z\';` in lib/core/app_version.dart.',
    );
  }
  if (app.group(1) != version) {
    throw ReleaseVersionException(
      'appVersion "${app.group(1)}" in lib/core/app_version.dart does not '
      'match pubspec.yaml version $version.',
    );
  }

  if (previousVersionJson != null) {
    final previous = _parsePrevious(previousVersionJson);
    if (build <= previous.build) {
      throw ReleaseVersionException(
        'pubspec.yaml build $build must be greater than the previous '
        'release\'s build ${previous.build} (${previous.version}). '
        'Raise the number after the + in pubspec.yaml.',
      );
    }
  }

  return ReleaseInfo(version: version, build: build);
}

ReleaseInfo _parsePrevious(String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (e) {
    throw ReleaseVersionException(
      'The previous version.json is not JSON: ${e.message}',
    );
  }
  if (decoded is Map &&
      decoded['version'] is String &&
      decoded['build'] is int) {
    return ReleaseInfo(
      version: decoded['version'] as String,
      build: decoded['build'] as int,
    );
  }
  throw ReleaseVersionException(
    'The previous version.json is not {"version":"X.Y.Z","build":N}: $source',
  );
}

const _usage =
    'usage: dart tool/check_release_version.dart [--tag vX.Y.Z] '
    '[--pubspec pubspec.yaml] [--app-version lib/core/app_version.dart] '
    '[--previous version.json] [--write version.json]';

/// The command line: returns the exit code (0 ok, 1 check failed, 64 usage).
int runCli(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  final options = <String, String>{
    '--pubspec': 'pubspec.yaml',
    '--app-version': 'lib/core/app_version.dart',
  };
  const known = {
    '--tag',
    '--pubspec',
    '--app-version',
    '--previous',
    '--write',
  };
  for (var i = 0; i < args.length; i++) {
    final name = args[i];
    if (!known.contains(name) || i + 1 >= args.length) {
      err.writeln(_usage);
      return 64;
    }
    options[name] = args[++i];
  }

  String read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ReleaseVersionException('File not found: $path');
    }
    return file.readAsStringSync();
  }

  try {
    final previousPath = options['--previous'];
    final info = checkReleaseVersion(
      tag: options['--tag'],
      pubspec: read(options['--pubspec']!),
      appVersionSource: read(options['--app-version']!),
      previousVersionJson: previousPath == null ? null : read(previousPath),
    );
    final writePath = options['--write'];
    if (writePath != null) {
      File(writePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(info.toJson());
    }
    out
      ..writeln('version=${info.version}')
      ..writeln('build=${info.build}');
    return 0;
  } on ReleaseVersionException catch (e) {
    err.writeln('Release version check failed: ${e.message}');
    return 1;
  }
}

void main(List<String> args) {
  exitCode = runCli(args, out: stdout, err: stderr);
}
