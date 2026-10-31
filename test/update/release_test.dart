import 'package:flutter_test/flutter_test.dart';
import 'package:songies/update/release.dart';

Map<String, Object?> _json({
  String tag = 'v1.2.3',
  bool draft = false,
  bool prerelease = false,
  Object? body = 'Notes',
  List<String> assets = const [],
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'body': body,
  'html_url': 'https://github.com/DenisMartonak/Songie/releases/tag/$tag',
  'assets': [
    for (final a in assets)
      {
        'name': a,
        'browser_download_url': 'https://example.test/dl/$a',
        'size': 42,
      },
  ],
};

void main() {
  test('parses v1.2.3 and 1.2.3+7 the same', () {
    final a = AppVersion.tryParse('v1.2.3')!;
    final b = AppVersion.tryParse('1.2.3+7')!;
    expect(a.compareTo(b), 0);
    expect(a.toString(), '1.2.3');
    expect(b.toString(), '1.2.3');
    expect((a.major, a.minor, a.patch), (1, 2, 3));
  });

  test('rejects 1.2 and 1.2.3.4 and empty', () {
    expect(AppVersion.tryParse('1.2'), isNull);
    expect(AppVersion.tryParse('1.2.3.4'), isNull);
    expect(AppVersion.tryParse(''), isNull);
    expect(AppVersion.tryParse('1.x.3'), isNull);
    expect(AppVersion.tryParse('v'), isNull);
  });

  test('orders 1.10.0 above 1.9.9', () {
    final hi = AppVersion.tryParse('1.10.0')!;
    final lo = AppVersion.tryParse('1.9.9')!;
    expect(hi.compareTo(lo), greaterThan(0));
    expect(lo.compareTo(hi), lessThan(0));
  });

  test('fromGitHubJson skips drafts and prereleases', () {
    expect(Release.fromGitHubJson(_json(draft: true)), isNull);
    expect(Release.fromGitHubJson(_json(prerelease: true)), isNull);
    expect(Release.fromGitHubJson(_json(tag: 'nightly')), isNull);
    expect(Release.fromGitHubJson(_json(tag: '1.2')), isNull);
    final r = Release.fromGitHubJson(_json(body: null))!;
    expect(r.version.toString(), '1.2.3');
    expect(r.notes, '');
    expect(r.htmlUrl.host, 'github.com');
  });

  test('pickAsset finds each platform file and returns null when missing', () {
    final v = AppVersion.tryParse('1.2.3')!;
    final full = Release.fromGitHubJson(
      _json(
        assets: [
          for (final p in UpdatePlatform.values) p.assetName(v),
          'SHA256SUMS',
        ],
      ),
    )!;
    expect(UpdatePlatform.android.assetName(v), 'songies-1.2.3.apk');
    expect(
      UpdatePlatform.windows.assetName(v),
      'songies-1.2.3-windows-setup.exe',
    );
    expect(UpdatePlatform.linux.assetName(v), 'songies-1.2.3-x86_64.AppImage');
    for (final p in UpdatePlatform.values) {
      expect(full.pickAsset(p)!.name, p.assetName(v));
      expect(full.pickAsset(p)!.size, 42);
    }
    expect(full.checksums!.name, 'SHA256SUMS');

    final partial = Release.fromGitHubJson(
      _json(assets: ['songies-1.2.3.apk']),
    )!;
    expect(partial.pickAsset(UpdatePlatform.android), isNotNull);
    expect(partial.pickAsset(UpdatePlatform.windows), isNull);
    expect(partial.pickAsset(UpdatePlatform.linux), isNull);
    expect(partial.checksums, isNull);
  });

  test('parseSha256Sums reads sha256sum output and skips junk lines', () {
    final h1 = 'A' * 64;
    final h2 = 'b' * 64;
    final map = parseSha256Sums(
      '$h1  songies-1.2.3.apk\n'
      '\n'
      'not a checksum line\n'
      '$h2 *songies-1.2.3-x86_64.AppImage\r\n'
      'abc123  short.bin\n',
    );
    expect(map, {
      'songies-1.2.3.apk': 'a' * 64,
      'songies-1.2.3-x86_64.AppImage': h2,
    });
  });
}
