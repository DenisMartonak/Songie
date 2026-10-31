import 'dart:convert';
import 'dart:io';

import '../data/settings_repository.dart';
import 'release.dart';

const String kUpdateRepo = String.fromEnvironment(
  'SONGIES_UPDATE_REPO',
  defaultValue: 'DenisMartonak/Songie',
);

/// Returns the decoded JSON, null on 404, and throws on any other failure.
typedef FetchJson = Future<Map<String, Object?>?> Function(Uri url);

/// The default [FetchJson]: anonymous GitHub API call with a 10 s timeout.
Future<Map<String, Object?>?> fetchJsonOverHttp(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(url).timeout(const Duration(seconds: 10));
    req.headers.set('Accept', 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) {
      await res.drain<void>();
      return null;
    }
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(body);
    if (json is! Map) throw const FormatException('Not a JSON object');
    return json.cast<String, Object?>();
  } finally {
    client.close(force: true);
  }
}

sealed class UpdateCheck {
  const UpdateCheck();
}

class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.release, this.asset);
  final Release release;
  final ReleaseAsset asset;
}

class UpToDate extends UpdateCheck {
  const UpToDate();
}

class CheckFailed extends UpdateCheck {
  const CheckFailed(this.error);
  final Object error;
}

class UpdateChecker {
  const UpdateChecker({
    this.fetch = fetchJsonOverHttp,
    required this.settings,
    required this.current,
    required this.platform,
    this.repo = kUpdateRepo,
    this.now = DateTime.now,
  });

  static const throttle = Duration(hours: 12);

  final FetchJson fetch;
  final SettingsRepository settings;
  final AppVersion current;
  final UpdatePlatform platform;
  final String repo;
  final DateTime Function() now;

  /// Null when throttled or when the result is the skipped version. Never
  /// throws.
  Future<UpdateCheck?> checkAtStartup() async {
    try {
      final nowMs = now().millisecondsSinceEpoch;
      final last = int.tryParse(
        await settings.getString(kUpdateLastCheckMs) ?? '',
      );
      if (last != null &&
          nowMs >= last &&
          nowMs - last < throttle.inMilliseconds) {
        return null;
      }
      await settings.setString(kUpdateLastCheckMs, '$nowMs');
      final result = await checkNow();
      if (result is UpdateAvailable) {
        final skipped = await settings.getString(kUpdateSkippedVersion);
        if (skipped == result.release.version.toString()) return null;
      }
      return result;
    } catch (e) {
      return CheckFailed(e);
    }
  }

  /// Ignores the throttle and the skip. Never throws.
  Future<UpdateCheck> checkNow() async {
    try {
      final json = await fetch(
        Uri.https('api.github.com', '/repos/$repo/releases/latest'),
      );
      if (json == null) return const UpToDate();
      final release = Release.fromGitHubJson(json);
      if (release == null) return const UpToDate();
      if (release.version.compareTo(current) <= 0) return const UpToDate();
      final asset = release.pickAsset(platform);
      if (asset == null) return const UpToDate();
      return UpdateAvailable(release, asset);
    } catch (e) {
      return CheckFailed(e);
    }
  }

  Future<void> skip(AppVersion v) =>
      settings.setString(kUpdateSkippedVersion, v.toString());
}
